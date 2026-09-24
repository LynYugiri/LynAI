/*
 * LynAI 服务卡片页面（ArkTS 卡片）。
 *
 * 只做渲染：数据通过 formBindingData 注入 LocalStorage，
 * 结构见 EntryFormAbility.cardPayload（headline + row1/row2 + updatedAt）。
 * 点击卡片跳回主应用。
 */
let storage: LocalStorage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('headline') headline: string = '近期无日程';
  @LocalStorageProp('row1') row1: string = '';
  @LocalStorageProp('row2') row2: string = '';
  @LocalStorageProp('updatedAt') updatedAt: string = '';

  build() {
    Column() {
      Row() {
        Text('LynAI')
          .fontSize(12)
          .fontColor('#5A5A5A')
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(this.updatedAt)
          .fontSize(10)
          .fontColor('#9A9A9A')
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(this.headline)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.row1.length > 0) {
        Text(this.row1)
          .fontSize(12)
          .fontColor('#5A5A5A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 4 })
      }
      if (this.row2.length > 0) {
        Text(this.row2)
          .fontSize(12)
          .fontColor('#5A5A5A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor('#F5F7FA')
    .borderRadius(12)
    .onClick(() => {
      // 拉起主应用（卡片点击的常规入口）。
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          from: 'widget',
        },
      });
    })
  }
}
