/**
 * 便签上的文字内容。今日页的便签和涂鸦弹层里的预览**共用这一个组件**，
 * 所以预览和保存后的样子在字号、行高、位置上完全一致。
 */
@Component
export struct NoteContent {
  entryNo: string = '';
  time: string = '';
  title: string = '';
  place: string = '';
  featured: boolean = false;
  completed: boolean = false;

  build() {
    if (this.featured) {
      Column({ space: 6 }) {
        Row({ space: 10 }) {
          Text('当前')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.accent_primary'))
            .letterSpacing(2)
          Column()
            .width(40)
            .height(1.5)
            .backgroundColor($r('app.color.accent_mustard'))
          Blank()
          Text(this.time)
            .fontFamily('serif')
            .fontSize(20)
            .fontWeight(900)
            .fontColor($r('app.color.archive_ink'))
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.title)
          .fontSize(26)
          .fontWeight(900)
          .fontColor($r('app.color.archive_ink'))
          .lineHeight(34)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .decoration({ type: this.completed ? TextDecorationType.LineThrough : TextDecorationType.None })

        if (this.place !== '') {
          Text(this.place)
            .fontSize(12)
            .fontColor($r('app.color.archive_ink'))
            .opacity(0.75)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Row({ space: 12 }) {
        if (this.entryNo !== '') {
          Text(this.entryNo)
            .fontFamily('serif')
            .fontSize(14)
            .fontWeight(900)
            .fontColor($r('app.color.brand_primary'))
            .letterSpacing(1)
            .width(26)
        }
        Column({ space: 4 }) {
          Text(this.time)
            .fontFamily('serif')
            .fontSize(44)
            .minFontSize(30)
            .maxFontSize(44)
            .fontWeight(900)
            .fontColor($r('app.color.archive_ink'))
            .letterSpacing(-1)
            .maxLines(1)
          Text(this.title)
            .fontSize(24)
            .fontWeight(900)
            .fontColor($r('app.color.archive_ink'))
            .lineHeight(32)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .decoration({ type: this.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
          if (this.place !== '') {
            Text(this.place)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.archive_ink'))
              .opacity(0.75)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }
}
