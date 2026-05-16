import { curves, promptAction } from '@kit.ArkUI';
import { CourseAndActivity, ClassInfo } from '../utils/classFun';
import { DatabaseManager } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';


const TAG = 'SearchCoursePage';
const DOMAIN = 0x0007;

@Builder
export function init() {
  SearchLongTakeTransitionPageTwo()
}

// 课程项组件
@Reusable
@Component
struct CourseItem {
  @Prop course: ClassInfo
  @State courseImage: image.PixelMap | null = null
  @State isPressed: boolean = false
  onCourseClick?: (course: ClassInfo) => void

  build() {
    Row() {
      if (this.courseImage) {
        Image(this.courseImage)
          .width(44)
          .height(44)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)
      } else {
        Column()
          .width(44)
          .height(44)
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
      }

      Column() {
        Text(this.course.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.course.teacherfactor) {
          Text(`教师: ${this.course.teacherfactor}`)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .height(68)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .padding({ left: 16, right: 16 })
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
    .onClick(() => {
      if (this.onCourseClick) {
        this.onCourseClick(this.course)
      }
    })
    .onAppear(async () => {
      if (this.course.imageurl) {
        try {
          this.courseImage = await loginFunction.GetPic(this.course.imageurl) as image.PixelMap
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'Failed to load course image', e)
        }
      }
    })
  }
}

// [Start bind_id]
@Component
export default struct SearchLongTakeTransitionPageTwo {
  private pageInfos: NavPathStack = new NavPathStack();
  @State searchText: string = ''
  @State allCourses: ClassInfo[] = []
  @State filteredCourses: ClassInfo[] = []
  @State isLoading: boolean = false

  async aboutToAppear() {
    await this.loadCourses()
  }

  async loadCourses() {
    this.isLoading = true
    try {
      const dbManager = DatabaseManager.getInstance()
      const userData = await dbManager.getUserByPosition(1, true)

      if (userData) {
        const result = await CourseAndActivity.getClassList(userData.cookies)
        if (result.msg) {
          this.allCourses = result.classList
          this.filteredCourses = result.classList
        } else {
          promptAction.showToast({ message: '获取课程列表失败', duration: 2000 })
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to load courses', e)
      promptAction.showToast({ message: '加载课程失败', duration: 2000 })
    } finally {
      this.isLoading = false
    }
  }

  handleSearch(value: string) {
    this.searchText = value
    if (!value) {
      this.filteredCourses = this.allCourses
    } else {
      const searchLower = value.toLowerCase()
      this.filteredCourses = this.allCourses.filter(course =>
        course.name.toLowerCase().includes(searchLower) ||
        (course.teacherfactor && course.teacherfactor.toLowerCase().includes(searchLower))
      )
    }
  }

  handleCourseClick(course: ClassInfo): void {
    // 返回上一页并传递选中的课程信息

    // 这里可以添加导航到课程详情或签到页面的逻辑
    this.pageInfos.pushPath({ name: 'ActivityListPage', param: course })
  }

  build() {
    NavDestination() {
      Column() {
        // 搜索栏
        Row({ space: 12 }) {
          Column() {
            Image($r('app.media.arrow_right'))
              .width(20).height(20)
              .fillColor($r('app.color.icon'))
              .rotate({ angle: 180 })
          }
          .width(40).height(40)
          .borderRadius(12)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => { this.onArrowClicked(); })

          Search({ placeholder: '搜索课程名称或教师', value: $$this.searchText })
            .height(40)
            .placeholderColor($r('sys.color.ohos_id_color_text_secondary'))
            .layoutWeight(1)
            .borderRadius(20)
            .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
            .geometryTransition('SEARCH_ONE_SHOT_DEMO_TRANSITION_ID')
            .defaultFocus(true)
            .focusOnTouch(true)
            .onSubmit((value: string) => {
              this.handleSearch(value)
            })
            .onChange((value: string) => {
              this.handleSearch(value)
            })
        }
        .width('100%')
        .height(64)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        // 搜索结果
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color($r('sys.color.ohos_id_color_emphasize'))
            Text('加载中...')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.filteredCourses.length === 0) {
          Column() {
            Image($r('app.media.ic_public_quit'))
              .width(80)
              .height(80)
              .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
              .margin({ bottom: 16 })
              .opacity(0.5)

            Text(this.searchText ? '未找到匹配的课程' : '暂无课程')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))

            if (this.searchText) {
              Text('换个关键词试试看')
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
                .margin({ top: 8 })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            Text(`找到 ${this.filteredCourses.length} 个课程`)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })

            List({ space: 0 }) {
              ForEach(this.filteredCourses, (course: ClassInfo, index: number) => {
                ListItem() {
                  CourseItem({
                    course: course,
                    onCourseClick: (c: ClassInfo) => this.handleCourseClick(c)
                  })
                }
              })
            }
            .divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider'), startMargin: 72, endMargin: 16 })
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 0, right: 0 })
            .cachedCount(5)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .size({
        width: '100%',
        height: '100%'
      })
      .backgroundColor($r('app.color.page_background'))
    }
    .transition(TransitionEffect.OPACITY)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
    })
    .onBackPressed(() => {
      // 返回时也使用动画
      this.getUIContext().animateTo({
        curve: curves.interpolatingSpring(0, 1, 342, 38)
      }, () => {
        this.pageInfos.pop(false);
      })
      return true;
    })
  }

  private onArrowClicked(): void {
    this.getUIContext().animateTo({
      curve: curves.interpolatingSpring(0, 1, 342, 38)
    }, () => {
      this.pageInfos.pop(false);
    })
  }
}
// [End bind_id]
