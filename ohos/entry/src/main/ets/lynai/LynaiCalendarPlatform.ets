/*
 * LynAI 鸿蒙日程提醒插件。
 *
 * 对应 Dart 侧 `CalendarPlatformBridge`（lib/services/calendar_platform_bridge.dart）
 * 使用的 `lynai/calendar_platform` 通道。Android 侧由 CalendarProjectionStore +
 * ScheduleNotificationReceiver 落库并重排 AlarmManager 通知；鸿蒙没有等价的
 * 「应用自己排定时通知」能力，普通应用要定时提醒必须使用系统的后台代理提醒
 * （reminderAgentManager）——到达时间点后由系统服务代为弹出通知，即使应用已被冻结。
 *
 * 通道约定（与 Android 一致）：
 * - syncProjection 入参 { projection }：解析 Dart 生成的版本化投影，
 *   只消费其中 `notificationTriggers`（未来触发的提醒），先取消本应用已发布的
 *   代理提醒再按投影重建，保证「投影是唯一权威」且可重入。
 * - requestNotificationPermission：仅由明确的用户操作调用，内部走
 *   notificationManager.requestEnableNotification；同步投影绝不隐式弹窗。
 *
 * 约束：
 * - 普通应用最多 30 个有效代理提醒，因此按触发时间取最近的 30 条（超出部分
 *   会在下次同步时随着时间推进重新纳入）。
 * - 需要在 module.json5 声明 ohos.permission.PUBLISH_AGENT_REMINDER
 *   （normal 级别、system_grant）。
 */
import {
  FlutterEngine,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { formBindingData, formProvider } from '@kit.FormKit';
import { cardPayload } from '../entryformability/EntryFormAbility';
import { listFormIds, writeWidgetOccurrences } from './WidgetStore';
import {
  MAX_REMINDERS,
  PlannedReminder,
  planReminders,
  ReminderTriggerInput,
} from './ReminderPlan';

const CHANNEL_NAME: string = 'lynai/calendar_platform';

/** 读取 Map 或普通对象上的字段，兼容 StandardMessageCodec 的两种解码形态。 */
function fieldValue(source: Object | null, key: string): Object | null {
  if (source === null) {
    return null;
  }
  if (source instanceof Map) {
    const value = (source as Map<string, Object>).get(key);
    return value === undefined ? null : value;
  }
  const record = source as Record<string, Object>;
  const value = record[key];
  return value === undefined ? null : value;
}

function stringField(source: Object | null, key: string): string {
  const value = fieldValue(source, key);
  return value === null ? '' : `${value}`;
}

function numberField(source: Object | null, key: string): number | null {
  const value = fieldValue(source, key);
  if (value === null || typeof value !== 'number') {
    return null;
  }
  return value as number;
}

function listField(source: Object | null, key: string): Object[] {
  const value = fieldValue(source, key);
  return Array.isArray(value) ? (value as Object[]) : [];
}

export class LynaiCalendarPlatform implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'LynaiCalendarPlatform';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'syncProjection':
        this.syncProjection(call, result);
        break;
      case 'requestNotificationPermission':
        this.requestNotificationPermission(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private syncProjection(call: MethodCall, result: MethodResult): void {
    const projection = call.argument('projection') as Object | null;
    if (projection === null) {
      result.error('invalid_projection', '缺少日历平台投影', null);
      return;
    }
    this.syncWidget(projection);
    const desired = this.desiredReminders(projection);
    this.replaceReminders(desired)
      .then(() => {
        result.success(null);
      })
      .catch((err: BusinessError) => {
        result.error('reminder_sync_failed', err.message, err.code);
      });
  }

  /**
   * 把投影里的小组件发生记录落盘，并刷新已经添加的服务卡片。
   *
   * 卡片（FormExtensionAbility）与这里属于不同上下文，通过 WidgetStore 的文件
   * 交换数据；刷新失败不影响提醒同步，因此单独 try/catch。
   */
  private syncWidget(projection: Object): void {
    try {
      writeWidgetOccurrences(
        this.context,
        listField(projection, 'widgetOccurrences'),
      );
    } catch (err) {
      return;
    }
    listFormIds(this.context)
      .then((formIds: string[]) => {
        if (formIds.length === 0) {
          return;
        }
        const data = formBindingData.createFormBindingData(
          cardPayload(listField(projection, 'widgetOccurrences')),
        );
        for (const formId of formIds) {
          formProvider
            .updateForm(formId, data)
            .catch((err: BusinessError) => {});
        }
      })
      .catch((err: BusinessError) => {});
  }

  /**
   * 把投影里的触发点折算成要发布的提醒。
   *
   * 时间解析、过滤、排序与截断都在 `ReminderPlan.ts` 里，并有 Node 单元测试
   * （scripts/ohos-arkts-tests/）；这里只负责把 StandardMessageCodec 解出的
   * Map/对象字段喂给它。
   */
  private desiredReminders(projection: Object): PlannedReminder[] {
    const triggers: ReminderTriggerInput[] = [];
    for (const trigger of listField(projection, 'notificationTriggers')) {
      const epoch = numberField(trigger, 'triggerAtEpochMillis');
      triggers.push({
        triggerAtEpochMillis: epoch === null ? undefined : epoch,
        triggerAtLocal: stringField(trigger, 'triggerAtLocal'),
        title: stringField(trigger, 'title'),
        note: stringField(trigger, 'note'),
      });
    }
    return planReminders(triggers, Date.now(), MAX_REMINDERS);
  }

  /** 先清空本应用已发布的代理提醒，再按投影重建（投影是唯一权威）。 */
  private async replaceReminders(desired: PlannedReminder[]): Promise<void> {
    const existing: reminderAgentManager.ReminderInfo[] =
      await reminderAgentManager.getAllValidReminders();
    for (const info of existing) {
      try {
        await reminderAgentManager.cancelReminder(info.reminderId);
      } catch (err) {
        // 单条取消失败（例如已被用户关闭）不影响整体重建。
      }
    }
    for (const item of desired) {
      await reminderAgentManager.publishReminder(
        this.reminderRequest(item),
      );
    }
  }

  private reminderRequest(item: PlannedReminder): reminderAgentManager.ReminderRequestCalendar {
    const at = new Date(item.triggerAt);
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: at.getFullYear(),
        month: at.getMonth() + 1,
        day: at.getDate(),
        hour: at.getHours(),
        minute: at.getMinutes(),
        second: 0,
      },
      title: item.title,
      content: item.content,
      expiredContent: item.content,
      wantAgent: {
        pkgName: this.context.abilityInfo.bundleName,
        abilityName: this.context.abilityInfo.name,
      },
    };
    return request;
  }

  private requestNotificationPermission(result: MethodResult): void {
    notificationManager.requestEnableNotification(this.context)
      .then(() => {
        result.success(null);
      })
      .catch((err: BusinessError) => {
        // 用户拒绝或系统不允许时只上报错误，Dart 侧按 best-effort 处理。
        result.error('notification_permission_failed', err.message, err.code);
      });
  }

  static register(flutterEngine: FlutterEngine, context: common.UIAbilityContext): void {
    flutterEngine.getPlugins()?.add(new LynaiCalendarPlatform(context));
  }
}
