import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { StyleConstants } from '../common/StyleConstants';
import { UiMode } from '../common/UiMode';
import { Theme } from '../common/Theme';
import { parseAIProviderConfig } from '../ai/provider/AIProviderConfig';
import { LOCAL_AI_CONFIG_FILENAME } from '../ai/provider/LocalAIConfigReader';

/**
 * 开发联调用：在应用内粘贴 AI 配置，写进沙箱 files/ai.config.local.json。
 *
 * 正式渠道不依赖外部文件，凭证也不应该随包分发；这里只是让真机/模拟器
 * 在不方便 hdc 的环境下也能切换真实 Provider。配置在应用启动时读取，
 * 保存后需要重启应用才生效。
 */
@Component
export struct AiConfigSheet {
  onClose: () => void = () => {};

  @State text: string = '';
  @State message: string = '';
  @State configured: boolean = false;
  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  private filePath(): string {
    return `${getContext(this).filesDir}/${LOCAL_AI_CONFIG_FILENAME}`;
  }

  aboutToAppear(): void {
    this.configured = this.aiConfigExists();
    if (this.configured) {
      this.text = this.readConfig();
    }
  }

  private aiConfigExists(): boolean {
    try {
      return fs.accessSync(this.filePath());
    } catch (_) {
      return false;
    }
  }

  private readConfig(): string {
    try {
      const path: string = this.filePath();
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      return new util.TextDecoder().decodeToString(new Uint8Array(buffer));
    } catch (_) {
      return '';
    }
  }

  private save(): void {
    const trimmed: string = this.text.trim();
    if (trimmed === '') {
      this.message = '先粘贴配置内容';
      return;
    }
    if (parseAIProviderConfig(trimmed) === undefined) {
      this.message = '格式不正确：需要 apiKey、endpoint、model 三个字段';
      return;
    }
    try {
      const file = fs.openSync(this.filePath(),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, trimmed);
      fs.closeSync(file);
    } catch (_) {
      this.message = '写入失败，请重试';
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '已保存，重启应用后生效' });
    this.onClose();
  }

  private clear(): void {
    try {
      if (fs.accessSync(this.filePath())) {
        fs.unlinkSync(this.filePath());
      }
    } catch (_) {
    }
    this.text = '';
    this.configured = false;
    this.message = '';
    this.getUIContext().getPromptAction().showToast({ message: '已清除，重启应用后回到示例模式' });
    this.onClose();
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
          Text('AI 配置')
            .fontSize(15)
            .fontWeight(900)
            .fontColor(Theme.text(this.uiMode))
          Blank()
          Text('保存')
            .fontSize(14)
            .fontWeight(900)
            .fontColor(Theme.accent(this.uiMode))
            .height(StyleConstants.TOUCH_TARGET_MIN)
            .padding({ left: 8, right: 8 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: 10 }) {
            Text('粘贴 AI 配置 JSON，保存到本机应用沙箱，重启应用后生效；凭证只保存在本机。')
              .fontSize(11)
              .fontColor(Theme.sub(this.uiMode))
              .width('100%')

            TextArea({
              placeholder: '{\n  "apiKey": "…",\n  "endpoint": "https://open.bigmodel.cn/api/paas/v4/chat/completions",\n  "model": "glm-5.3-flash",\n  "timeoutMs": 15000\n}',
              text: this.text
            })
              .onChange((value: string) => {
                this.text = value;
                this.message = '';
              })
              .fontSize(12)
              .fontColor(Theme.text(this.uiMode))
              .placeholderColor(Theme.sub(this.uiMode))
              .backgroundColor(Theme.subtleBg(this.uiMode))
              .height(220)
              .width('100%')

            Row({ space: 10 }) {
              Text(this.configured ? '已配置（重启后生效）' : '当前未配置：解析使用内置示例')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.configured ? Theme.accent(this.uiMode) : Theme.sub(this.uiMode))
                .layoutWeight(1)
              if (this.configured) {
                Text('清除配置')
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.alert(this.uiMode))
                  .height(32)
                  .padding({ left: 8, right: 8 })
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.clear();
                  })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.message !== '') {
              Text(this.message)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.alert(this.uiMode))
                .width('100%')
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
      .height('80%')
      .padding(StyleConstants.SPACE_LG)
      .backgroundColor(Theme.surface(this.uiMode))
      .borderRadius({ topLeft: 0, topRight: StyleConstants.RADIUS_LG, bottomLeft: 0, bottomRight: 0 })
    }
    .width('100%')
    .height('100%')
  }
}
