/*
 * 服务卡片的数据存取。
 *
 * 卡片（FormExtensionAbility）与主应用（UIAbility）是两个上下文，但共享同一个
 * 应用沙箱，因此用「文件 + preferences」交换数据：
 * - files/lynai_widget_occurrences.json：最近一次同步投影里的 widgetOccurrences，
 *   由日历插件写入；卡片在 onAddForm/onUpdateForm 时读取并计算要显示的文案。
 * - preferences(lynai_widget)：当前已添加的卡片 id 列表，日历插件据此在数据变化
 *   后主动 updateForm 刷新卡片。
 *
 * 存取的文件内容都是 Dart 侧投影的原始 JSON，避免两边各自维护一套模型。
 */
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';

const OCCURRENCES_FILE: string = 'lynai_widget_occurrences.json';
const PREFERENCES_NAME: string = 'lynai_widget';
const FORM_IDS_KEY: string = 'formIds';

function occurrencesPath(context: common.Context): string {
  return `${context.filesDir}/${OCCURRENCES_FILE}`;
}

/** 写入最近一次投影里的日历发生记录（原始 JSON 字符串数组）。 */
export function writeWidgetOccurrences(
  context: common.Context,
  occurrences: Object[],
): void {
  const path = occurrencesPath(context);
  const payload = JSON.stringify(occurrences);
  const file = fileIo.openSync(
    path,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
  );
  try {
    fileIo.writeSync(file.fd, payload);
  } finally {
    fileIo.closeSync(file);
  }
}

/** 读取发生记录；文件缺失或损坏时返回空数组（卡片显示「近期无日程」）。 */
export function readWidgetOccurrences(context: common.Context): Object[] {
  const path = occurrencesPath(context);
  if (!fileIo.accessSync(path)) {
    return [];
  }
  let content = '';
  try {
    // readTextSync 按 UTF-8 解码，中文标题不会乱码。
    content = fileIo.readTextSync(path);
  } catch (err) {
    return [];
  }
  try {
    const parsed: Object | null = JSON.parse(content) as Object | null;
    return Array.isArray(parsed) ? (parsed as Object[]) : [];
  } catch (err) {
    return [];
  }
}

async function loadFormIds(context: common.Context): Promise<string[]> {
  const store = await preferences.getPreferences(context, PREFERENCES_NAME);
  const raw = await store.get(FORM_IDS_KEY, '[]');
  try {
    const parsed: Object | null = JSON.parse(`${raw}`) as Object | null;
    return Array.isArray(parsed) ? (parsed as string[]) : [];
  } catch (err) {
    return [];
  }
}

async function saveFormIds(context: common.Context, formIds: string[]): Promise<void> {
  const store = await preferences.getPreferences(context, PREFERENCES_NAME);
  await store.put(FORM_IDS_KEY, JSON.stringify(formIds));
  await store.flush();
}

/** 记录一个新添加的卡片 id（重复添加时去重）。 */
export async function rememberFormId(
  context: common.Context,
  formId: string,
): Promise<void> {
  if (formId.length === 0) {
    return;
  }
  const formIds = await loadFormIds(context);
  if (formIds.includes(formId)) {
    return;
  }
  formIds.push(formId);
  await saveFormIds(context, formIds);
}

/** 移除已删除的卡片 id。 */
export async function forgetFormId(
  context: common.Context,
  formId: string,
): Promise<void> {
  const formIds = await loadFormIds(context);
  const next = formIds.filter((value: string) => value !== formId);
  if (next.length === formIds.length) {
    return;
  }
  await saveFormIds(context, next);
}

/** 当前已添加的卡片 id 列表，供日历插件在同步后刷新卡片。 */
export async function listFormIds(context: common.Context): Promise<string[]> {
  return loadFormIds(context);
}
