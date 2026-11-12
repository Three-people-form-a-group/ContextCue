import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants } from '../common/RouterConstants';
import { UiMode } from '../common/UiMode';
import { PaperStore } from '../common/PaperStore';
import { DraftStore } from '../common/DraftStore';
import { Theme } from '../common/Theme';
import { TodayDashboard } from '../components/TodayDashboard';
import { ReminderListPage } from './ReminderListPage';
import { SettingsPage } from './SettingsPage';
import { ReminderDetailPage } from './ReminderDetailPage';
import { ReminderEditPage } from './ReminderEditPage';
import { DraftListPage } from './DraftListPage';

/**
 * 应用唯一 @Entry 根页面：
 * Navigation + NavPathStack 组件导航体系（详情/编辑/设置为 NavDestination 子页，由 pageMap 注册）；
 * 主界面为三 Tab（今日/日程/设置）。日程页内含 列表/日历/课表 三种视图。
 *
 * TabBar 背景使用 Tabs 自带 barBackgroundColor。
 * 修复说明：原实现在 Stack 中于 Tabs 之上叠加了一个等高的不透明渐变块，
 * 它会遮住 TabBar 文字；现已移除，改由 Tabs 自身绘制底色。
 */
@Entry
@Component
struct Index {
  pathStack: NavPathStack = new NavPathStack();
  @State currentTabIndex: number = 0;

  @StorageLink('uiMode') uiMode: string = UiMode.JOURNAL;

  aboutToAppear(): void {
    // 读回上次选择的界面模式（极简 / 手账）
    UiMode.init(getContext(this));
    PaperStore.init(getContext(this));
    DraftStore.init(getContext(this));
  }

  /**
   * 暖纸色导航：与画布同色，像同一张档案纸的页脚。
   * 选中 = 墨蓝绿文字 + 砖红小标记；未选中 = 次级灰文字。
   */
  @Builder
  tabItem(index: number, label: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(this.currentTabIndex === index ? 16 : 14)
        .fontWeight(this.currentTabIndex === index ? 900 : FontWeight.Medium)
        .fontColor(this.currentTabIndex === index
          ? Theme.text(this.uiMode)
          : Theme.sub(this.uiMode))
        .opacity(this.currentTabIndex === index ? 1 : 0.75)
      Column()
        .width(18)
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.currentTabIndex === index
          ? Theme.accent(this.uiMode)
          : Color.Transparent)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(StyleConstants.TAB_BAR_HEIGHT)
    // 三个 Tab 各自的顶边合成一条连续的暖灰细线，给导航一个轻边界
    .border({
      width: { top: StyleConstants.HAIRLINE_HEIGHT },
      color: Theme.rule(this.uiMode)
    })
  }

  @Builder
  pageMap(name: string) {
    if (name === RouterConstants.PAGE_REMINDER_DETAIL) {
      ReminderDetailPage({ pathStack: this.pathStack })
    } else if (name === RouterConstants.PAGE_REMINDER_EDIT) {
      ReminderEditPage({ pathStack: this.pathStack })
    } else if (name === RouterConstants.PAGE_DRAFT_LIST) {
      DraftListPage({ pathStack: this.pathStack })
    } else if (name === RouterConstants.PAGE_SETTINGS) {
      NavDestination() {
        SettingsPage({ pathStack: this.pathStack })
      }
      .hideTitleBar(true)
    }
  }

  build() {
    Navigation(this.pathStack) {
      Tabs({ index: this.currentTabIndex, barPosition: BarPosition.End }) {
        TabContent() {
          TodayDashboard({ pathStack: this.pathStack })
        }
        .tabBar(this.tabItem(0, '今日'))

        TabContent() {
          ReminderListPage({ pathStack: this.pathStack })
        }
        .tabBar(this.tabItem(1, '日程'))

        TabContent() {
          SettingsPage({ pathStack: this.pathStack, showBack: false })
        }
        .tabBar(this.tabItem(2, '设置'))
      }
      .barHeight(StyleConstants.TAB_BAR_HEIGHT)
      .barMode(BarMode.Fixed)
      // 左右滑不再切 Tab：日程页的课表要用左右滑翻周/翻日，
      // 而且斜向的竖向滚动会被 Tabs 误判成换页，直接跳到设置
      .scrollable(false)
      .barBackgroundColor(Theme.bg(this.uiMode))
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
      .width('100%')
      .height('100%')
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor(Theme.bg(this.uiMode))
  }
}
