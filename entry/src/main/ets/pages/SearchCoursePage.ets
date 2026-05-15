import { curves, promptAction } from '@kit.ArkUI';
import { CourseAndActivity, ClassInfo } from '../utils/classFun';
import { DatabaseManager } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { hdsEffect } from '@kit.UIDesignKit';

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
  @Prop index: number
  @State courseImage: image.PixelMap | null = null
  @State isPressed: boolean = false
  @State itemOpacity: number = 0
  @State translateY: number = 20
  @State itemScale: number = 0.95
  onCourseClick?: (course: ClassInfo) => void

  build() {
    Row() {
      // 课程图片
      if (this.courseImage) {
        Image(this.courseImage)
          .width(60)
          .height(60)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      } else {
        Column()
          .width(60)
          .height(60)
          .borderRadius(8)
          .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
      }

      // 课程信息
      Column() {
        Text(this.course.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.course.teacherfactor) {
          Text(`教师: ${this.course.teacherfactor}`)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: '#00000018',
      offsetX: 0,
      offsetY: 2
    })
    .opacity(this.itemOpacity)
    .translate({ y: this.translateY })
    .scale({ x: this.itemScale, y: this.itemScale })
    .onClick(() => {
      if (this.onCourseClick) {
        this.onCourseClick(this.course)
      }
    })
    .onAppear(async () => {
      // Staggered animation for list items - each item animates with a delay based on its index
      animateTo({
        duration: 400,
        curve: curves.springMotion(0.6, 0.8),
        delay: this.index * 50
      }, () => {
        this.itemOpacity = 1
        this.translateY = 0
        this.itemScale = 1
      })

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
  @State pageOpacity: number = 0
  @State contentTranslateY: number = 30
  @State backButtonScale: number = 0.8
  @State backButtonOpacity: number = 0
  @State shineTranslateBack: string = '-100%'
  @State backButtonLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  async aboutToAppear() {
    await this.loadCourses()

    // Animate the page entrance
    animateTo({
      duration: 500,
      curve: curves.springMotion(0.6, 0.9),
      delay: 100
    }, () => {
      this.pageOpacity = 1
      this.contentTranslateY = 0
    })

    // Animate back button
    animateTo({
      duration: 400,
      curve: curves.springMotion(0.6, 0.8),
      delay: 150
    }, () => {
      this.backButtonScale = 1
      this.backButtonOpacity = 1
    })
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
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.img'))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
          }
          .width(40)
            .height(40)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .shadow({
              radius: 4,
              color: '#00000010',
              offsetX: 0,
              offsetY: 1
            })
            .scale({ x: this.backButtonScale, y: this.backButtonScale })
            .opacity(this.backButtonOpacity)
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.backButtonLight,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                  this.backButtonLight = hdsEffect.PointLightSourceType.BRIGHT;
                })
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                  this.backButtonLight = hdsEffect.PointLightSourceType.NONE;
                })
              }
            })
            .onClick(() => {
              this.onArrowClicked();
            })

          Search({ placeholder: '搜索课程名称或教师', value: $$this.searchText })
            .height(40)
            .placeholderColor($r('sys.color.ohos_id_color_text_secondary'))
            .layoutWeight(1)
            .borderRadius(20)
            .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
            .geometryTransition('SEARCH_ONE_SHOT_DEMO_TRANSITION_ID')
            .transition(TransitionEffect.opacity(0.99))
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
          .opacity(this.pageOpacity)
          .translate({ y: this.contentTranslateY })
        } else if (this.filteredCourses.length === 0) {
          Column() {
            Image($r('app.media.ic_public_quit')) // 使用一个通用图标，或者 envelope
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
          .opacity(this.pageOpacity)
          .translate({ y: this.contentTranslateY })
        } else {
          Column() {
            Text(`找到 ${this.filteredCourses.length} 个课程`)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })
              .opacity(this.pageOpacity)

            List({ space: 12 }) {
              ForEach(this.filteredCourses, (course: ClassInfo, index: number) => {
                ListItem() {
                  CourseItem({
                    course: course,
                    index: index,
                    onCourseClick: (c: ClassInfo) => this.handleCourseClick(c)
                  })
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16 })
            .opacity(this.pageOpacity)
            .translate({ y: this.contentTranslateY })
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
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    }
    // .transition(TransitionEffect.OPACITY)
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.ohos_id_color_background'))
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
    this.pageInfos.pop(false);
  }
}
// [End bind_id]
