import { StyleConstants } from '../common/StyleConstants';
import { RouterConstants } from '../common/RouterConstants';
import { TodayDashboard } from '../components/TodayDashboard';
import { ReminderListPage } from './ReminderListPage';
import { SettingsPage } from './SettingsPage';
import { ReminderDetailPage } from './ReminderDetailPage';
import { ReminderEditPage } from './ReminderEditPage';

/**
 * 应用唯一 @Entry 根页面：
 * Navigation + NavPathStack 组件导航体系（详情/编辑/设置为 NavDestination 子页，由 pageMap 注册）；
 * 主界面为两 Tab（今日/全部）。设置不再是并列 Tab，而是由首页右上角齿轮进入的 NavDestination。
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

  @Builder
  tabItem(index: number, label: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(this.currentTabIndex === index ? 16 : 14)
        .fontWeight(this.currentTabIndex === index ? 900 : FontWeight.Medium)
        .fontColor($r('app.color.surface_primary'))
        .opacity(this.currentTabIndex === index ? 1 : 0.6)
      Column()
        .width(18)
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.currentTabIndex === index ? $r('app.color.accent_primary') : Color.Transparent)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(StyleConstants.TAB_BAR_HEIGHT)
  }

  @Builder
  pageMap(name: string) {
    if (name === RouterConstants.PAGE_REMINDER_DETAIL) {
      ReminderDetailPage({ pathStack: this.pathStack })
    } else if (name === RouterConstants.PAGE_REMINDER_EDIT) {
      ReminderEditPage({ pathStack: this.pathStack })
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
        .tabBar(this.tabItem(1, '全部'))
      }
      .barHeight(StyleConstants.TAB_BAR_HEIGHT)
      .barMode(BarMode.Fixed)
      .barBackgroundColor($r('app.color.text_primary'))
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
      .width('100%')
      .height('100%')
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.background_primary'))
  }
}
