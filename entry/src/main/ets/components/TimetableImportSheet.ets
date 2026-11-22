import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { parseTimetableData, TimetableDataParseResult } from '../timetable/parse/TimetableDataParser';
import { CourseDraft, TimetableDraft } from '../timetable/model/TimetableTypes';
import { FakeTimetableImageParser } from '../timetable/provider/FakeTimetableImageParser';
import { TimetableProviderResult } from '../timetable/contract/TimetableImageParser';

/**
 * 课程表导入弹层。
 *
 * 两条入口都汇聚到 `TimetableDraft`：
 *   ① 粘贴教务 JSON → parseTimetableData → 预览；
 *   ② 示例识别：FakeTimetableImageParser 返回预置 JSON → 同一个解析器 → 预览。
 * 只有点「确认导入」才会交给页面调用 saveTimetable，解析本身不写任何数据。
 */
@Component
export struct TimetableImportSheet {
  onApply: (draft: TimetableDraft) => void = () => {};
  onClose: () => void = () => {};

  @State text: string = '';
  @State draft: TimetableDraft | undefined = undefined;
  @State issuesText: string = '';
  @State busy: boolean = false;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  aboutToAppear(): void {
    this.text = this.sampleJson();
  }

  /** 示例数据按"今天 = 第 1 周"生成，保证导入后能生成本周/下周的提醒 */
  private todayIso(): string {
    const d: Date = new Date();
    const m: string = d.getMonth() + 1 < 10 ? `0${d.getMonth() + 1}` : `${d.getMonth() + 1}`;
    const day: string = d.getDate() < 10 ? `0${d.getDate()}` : `${d.getDate()}`;
    return `${d.getFullYear()}-${m}-${day}`;
  }

  private sampleJson(): string {
    return `{"semesterName":"2026-2027 学年第一学期","anchorDate":"${this.todayIso()}","anchorWeek":1,` +
      `"courses":[` +
      `{"name":"高等数学","teacher":"张老师","location":"教三-401","dayOfWeek":1,"startTime":"08:00","endTime":"09:40","weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]},` +
      `{"name":"大学英语","location":"外语楼-203","dayOfWeek":1,"startTime":"10:00","endTime":"11:40","weeks":[1,2,3,4,5,6,7,8]},` +
      `{"name":"数据结构","teacher":"王老师","location":"计算机楼-305","dayOfWeek":3,"startTime":"14:00","endTime":"15:40","weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]},` +
      `{"name":"人工智能导论","dayOfWeek":5,"startTime":"15:00","endTime":"16:40","weeks":[3,4,5,6,7,8]}` +
      `]}`;
  }

  private parse(raw: string): void {
    const result: TimetableDataParseResult = parseTimetableData(raw);
    if (result.value !== undefined && result.issues.length === 0) {
      this.draft = result.value;
      this.issuesText = '';
      return;
    }
    this.draft = undefined;
    const messages: string[] = [];
    for (let i = 0; i < result.issues.length && i < 3; i++) {
      messages.push(result.issues[i].message);
    }
    this.issuesText = messages.length === 0 ? '解析失败，请检查 JSON 格式' : messages.join('；');
  }

  /** 示例识别：走与正式视觉模型相同的端口，只是返回预置 JSON */
  private async recognizeSample(): Promise<void> {
    this.busy = true;
    const fixtures: Map<string, string> = new Map<string, string>();
    fixtures.set('demo', this.sampleJson());
    const parser: FakeTimetableImageParser = new FakeTimetableImageParser(fixtures);
    const result: TimetableProviderResult = await parser.requestTimetableParse('demo', {
      now: Date.now(),
      timeZone: 'Asia/Shanghai'
    });
    this.busy = false;
    if (result.rawResponse === undefined) {
      this.issuesText = '示例识别失败（Fake 数据集没有对应条目）';
      return;
    }
    this.text = result.rawResponse;
    this.parse(result.rawResponse);
  }

  private draftCourses(): CourseDraft[] {
    return this.draft === undefined ? [] : this.draft.courses;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.archive_ink'))
        .opacity(0.35)
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Row() {
          Text('取消')
            .fontSize(14)
            .fontColor(Theme.sub(this.uiMode))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })
          Blank()
          Text('导入课程表')
            .fontSize(15)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
          Blank()
          Text('确认导入')
            .fontSize(14)
            .fontWeight(900)
            .fontColor(this.draft === undefined ? Theme.sub(this.uiMode) : Theme.accent(this.uiMode))
            .opacity(this.draft === undefined ? 0.4 : 1)
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.draft !== undefined) {
                this.onApply(this.draft);
              }
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: 10 }) {
            Text('粘贴教务 JSON，或先用「示例识别」看一条完整链路（Fake 视觉模型 → 解析 → 预览）。')
              .fontSize(11)
              .fontColor(Theme.sub(this.uiMode))
              .width('100%')

            TextArea({ text: this.text, placeholder: '在此粘贴课程表 JSON' })
              .onChange((value: string) => {
                this.text = value;
                this.draft = undefined;
                this.issuesText = '';
              })
              .fontSize(12)
              .fontColor(Theme.text(this.uiMode))
              .backgroundColor(Theme.subtleBg(this.uiMode))
              .height(170)
              .width('100%')

            Row({ space: 10 }) {
              Text('解析 JSON')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.accent(this.uiMode))
                .height(36)
                .padding({ left: 10, right: 10 })
                .textAlign(TextAlign.Center)
                .border({ width: 1, color: Theme.rule(this.uiMode) })
                .borderRadius({ topLeft: 0, topRight: 8, bottomLeft: 0, bottomRight: 8 })
                .onClick(() => {
                  this.parse(this.text);
                })
              Text(this.busy ? '识别中…' : '示例识别')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.accent(this.uiMode))
                .height(36)
                .padding({ left: 10, right: 10 })
                .textAlign(TextAlign.Center)
                .border({ width: 1, color: Theme.rule(this.uiMode) })
                .borderRadius({ topLeft: 0, topRight: 8, bottomLeft: 0, bottomRight: 8 })
                .onClick(() => {
                  this.recognizeSample();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.issuesText !== '') {
              Text(this.issuesText)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.alert(this.uiMode))
                .width('100%')
            }

            if (this.draft !== undefined) {
              Column({ space: 6 }) {
                Text(`识别到 ${this.draftCourses().length} 门课 · ${this.draft === undefined ? '' : this.draft.semesterName}`)
                  .fontSize(12)
                  .fontWeight(900)
                  .fontColor(Theme.text(this.uiMode))
                ForEach(this.draftCourses(), (c: CourseDraft) => {
                  Row({ space: 8 }) {
                    Text(`周${c.dayOfWeek}`)
                      .fontSize(10)
                      .fontColor(Theme.sub(this.uiMode))
                      .width(24)
                    Text(`${c.startTime}-${c.endTime}`)
                      .fontSize(10)
                      .fontColor(Theme.sub(this.uiMode))
                      .width(78)
                    Text(`${c.name}${c.location === undefined ? '' : ' · ' + c.location}`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Theme.text(this.uiMode))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }, (c: CourseDraft, idx: number) => `import-${idx}-${c.name}-${c.dayOfWeek}-${c.startTime}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .border({ width: 1, color: Theme.rule(this.uiMode) })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 10, bottom: 12 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('86%')
      .padding(StyleConstants.SPACE_LG)
      .backgroundColor(Theme.surface(this.uiMode))
      .borderRadius({ topLeft: 0, topRight: StyleConstants.RADIUS_LG, bottomLeft: 0, bottomRight: 0 })
    }
    .width('100%')
    .height('100%')
  }
}
