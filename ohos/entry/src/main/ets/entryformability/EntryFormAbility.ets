/*
 * LynAI 鸿蒙服务卡片（FormExtensionAbility）。
 *
 * 对应 Android 侧的桌面小组件：展示最近一条日程（文案与 Android
 * ScheduleWidgetLogic 一致：「今天 / 明天 / N 天后 / 进行中 · 标题」，
 * 无日程时「近期无日程」），并附一两条后续日程。
 *
 * 数据来自日历插件在同步投影时写入文件的发生记录（WidgetStore），这里在
 * 卡片添加/刷新时读取并用 WidgetPlan 计算文案，然后通过 formBindingData
 * 交给卡片页面渲染。
 */
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { planWidget, WidgetOccurrenceInput } from './../lynai/WidgetPlan';
import { readWidgetOccurrences, rememberFormId, forgetFormId } from './../lynai/WidgetStore';

/** 卡片 id 在 want 参数里的键（formInfo.FormParam.IDENTITY_KEY）。 */
function formIdOf(want: Want): string {
  const parameters = want.parameters;
  if (parameters === undefined) {
    return '';
  }
  const value = parameters[formInfo.FormParam.IDENTITY_KEY];
  return typeof value === 'string' ? value : '';
}

/** 卡片渲染数据：卡片只能接收字符串，因此在这里就格式化好。 */
export interface WidgetCardPayload {
  headline: string;
  updatedAt: string;
  row1: string;
  row2: string;
}

/** 由当前发生记录计算卡片要显示的文案。 */
export function cardPayload(occurrences: Object[]): WidgetCardPayload {
  const plan = planWidget(occurrences as WidgetOccurrenceInput[], Date.now());
  const payload: WidgetCardPayload = {
    headline: plan.headline,
    updatedAt: `更新于 ${plan.updatedAt}`,
    row1: plan.rows.length > 0 ? plan.rows[0] : '',
    row2: plan.rows.length > 1 ? plan.rows[1] : '',
  };
  return payload;
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = formIdOf(want);
    // 记录卡片 id，便于日历数据变化后主动刷新。
    rememberFormId(this.context, formId).catch((err: BusinessError) => {});
    const data = cardPayload(readWidgetOccurrences(this.context));
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    const data = cardPayload(readWidgetOccurrences(this.context));
    formProvider
      .updateForm(formId, formBindingData.createFormBindingData(data))
      .catch((err: BusinessError) => {});
  }

  onRemoveForm(formId: string): void {
    forgetFormId(this.context, formId).catch((err: BusinessError) => {});
  }
}
