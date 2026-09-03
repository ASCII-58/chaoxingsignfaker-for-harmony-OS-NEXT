import { ActivityItem, ClassInfo, CourseAndActivity } from '../utils/classFun';
import { ChaoxingUtils } from '../utils/utils';
import { promptAction } from '@kit.ArkUI';
import { DatabaseManager } from '../utils/DataBase';
import { JSON } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ActivityListPage';
const DOMAIN = 0x0005;

/**
 * @param signType '0' 普通/拍照签到 | '2' 扫码签到 | '3' 手势签到 | '4' 位置签到 | '5' 签到码签到
 */
export interface ActivityInfo {
  ActivityId: string;
  CourseId: string;
  ClassId: string;
  signType: SignType
  /** 活动列表返回的 data.ext，preSign 时使用 */
  ext: string
}

export enum SignType {
  NORMAL = '0',
  QRCODE = '2',
  GESTURE = '3',
  LOCATION = '4',
  PASSWORD = '5'
}
@Reusable
@Component
struct signIcon {
  @Prop signType: string;
  @Prop isEnded: boolean = false;
  @State icon: ResourceStr = $r('app.media.foreground')
  @State isLoaded: boolean = false

  build() {
    Row() {
      Image(this.icon)
        .width(44)
        .height(44)
        .fillColor(this.isEnded ? $r('app.color.secondary_text') : $r('app.color.icon'))
        .borderColor(this.isEnded ? $r('sys.color.comp_divider') : $r('app.color.class_icon_border'))
        .borderWidth(2)
        .borderRadius(12)
        .margin(10)
        .backgroundColor($r('app.color.card_background'))
        .opacity(this.isEnded ? 0.5 : 1)
        .onAppear(() => {
          if (this.signType === '0') {
            this.icon = $r('app.media.hand_tap')
          } else if (this.signType === '2') {
            this.icon = $r('app.media.qrcode')
          } else if (this.signType === '3') {
            this.icon = $r('app.media.gesture')
          } else if (this.signType === '4') {
            this.icon = $r('app.media.map_badge_local')
          } else if (this.signType === '5') {
            this.icon = $r('app.media.password')
          }
          this.isLoaded = true
        })
    }
  }
}

@Builder
export function initClassInfo(name: string, classInfo: ClassInfo) {
  if (name) {
    ActivityListPage({
      classInfo: classInfo
    })
  }
}


@Component
export struct ActivityListPage {
  classInfo: ClassInfo | null = null;
  pathInfos: NavPathStack = new NavPathStack();
  @State courseId: string = ''; // 课程id
  @State teacherfactor: string = '';
  @State classId: string = ''; // 班级id
  @State name: string = '';
  @State ActivityList: ActivityItem[] | null = null
  @State activityExt: string = ''
  @State isRefreshing: boolean = false
  private loadEpoch: number = 0 // 每次拉取递增：让 ForEach 生成新 key，强制重建条目

  build() {
    NavDestination() {
      if (this.ActivityList) {
        List({ space: 0, initialIndex: 0 }) {
          ForEach(this.ActivityList, (Activity: ActivityItem, index: number) => {
            if (!(Activity.type != 2 && Activity.type != 74)) {
              ListItem() {
                Row() {
                  signIcon({ signType: Activity.otherId.toString(),
                    isEnded: this.isActivityEnded(Activity) })
                  Column() {
                    Text(Activity.nameOne)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isActivityEnded(Activity)
                        ? $r('app.color.secondary_text')
                        : $r('app.color.primary_text'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.getStatusText(Activity))
                      .fontSize(13)
                      .fontColor(this.getStatusColor(Activity))
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 12 })

                  Image($r('sys.media.ohos_ic_public_arrow_right'))
                    .width(14)
                    .height(14)
                    .fillColor($r('app.color.secondary_text'))
                    .opacity(this.isActivityEnded(Activity) ? 0.4 : 1)
                }
                .width('100%')
                .height(68)
                .backgroundColor($r('app.color.card_background'))
                .padding({ left: 16, right: 16 })
                .border({
                  width: { left: this.isActivityEnded(Activity) ? 0 : 3 },
                  color: { left: this.isActivityEnded(Activity)
                    ? 'transparent'
                    : (this.isActivityActive(Activity)
                      ? $r('app.color.signed')
                      : $r('app.color.selected')) }
                })
                .animation({ duration: 150, curve: Curve.EaseInOut })
              }
              .width('100%')
              .onClick(() => {
                if (this.isActivityEnded(Activity)) {
                  promptAction.showToast({ message: '该签到已结束' })
                  return
                }
                if (typeof Activity.endTime === 'number') {
                  if (!ChaoxingUtils.isSignActivityActive(Activity.startTime, Activity.endTime) ||
                    !ChaoxingUtils.isSignActivityStarted(Activity.startTime)) {
                    promptAction.showToast({ message: '不在可签到时间内, 无法签到' })
                    return
                  }
                }
                const activityInfo: ActivityInfo = {
                  ActivityId: Activity.id,
                  CourseId: this.courseId,
                  ClassId: this.classId,
                  signType: Activity.otherId.toString() as SignType,
                  ext: this.activityExt
                }
                this.pathInfos.pushPath({ name: 'SignerPage', param: activityInfo })
              })
            }
          }, (Activity: ActivityItem) => `${this.loadEpoch}_${Activity.id}`)
        }
        .divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider'), startMargin: 72, endMargin: 16 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .height('100%')
      } else if (this.isRefreshing) {
        Column() {
          LoadingProgress()
            .width(44)
            .height(44)
            .color($r('app.color.icon'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text('暂无签到活动，可点击右上角刷新')
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.page_background'))
    .title(`${this.name}`)
    .menus([{
      value: '刷新签到活动',
      icon: $r('app.media.ic_refresh'),
      action: () => {
        this.loadActivities(true)
      }
    }])
    .onReady((ctx: NavDestinationContext) => {
      this.pathInfos = ctx.pathStack;
    })
    .onAppear(async () => {
      if (!this.classInfo) {
        hilog.error(DOMAIN, TAG, 'No class info');
        promptAction.showToast({ message: '未获取到课程信息' })
        return
      }
      this.courseId = this.classInfo.id; // 课程id
      hilog.debug(DOMAIN, TAG, `Course ID: ${this.courseId}`);
      this.teacherfactor = this.classInfo?.teacherfactor as string;
      hilog.debug(DOMAIN, TAG, `Teacher: ${this.teacherfactor}`);
      this.classId = this.classInfo.classId; // 班级id
      this.name = this.classInfo?.name as string
      hilog.debug(DOMAIN, TAG, `Class name: ${this.name}`);
      await this.loadActivities(false)
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /**
   * 拉取签到活动列表(首载与手动刷新共用)
   * @param isManualRefresh 手动点刷新按钮时为 true,成功后给出提示
   */
  private async loadActivities(isManualRefresh: boolean): Promise<void> {
    if (this.isRefreshing) {
      return
    }
    this.isRefreshing = true
    try {
      const dbManager = DatabaseManager.getInstance()
      const cookies = (await dbManager.getUserByPosition(1, true))?.cookies
      if (!cookies) {
        throw new Error('用户登录信息错误')
      }
      hilog.debug(DOMAIN, TAG, 'Loading activity list');
      const activityResult = await CourseAndActivity.getActivityList(cookies, this.classId, this.courseId);
      this.loadEpoch++ // key 变化后条目全部重建，签到状态/倒计时随之更新
      this.ActivityList = activityResult ? activityResult.activities : null;
      this.activityExt = activityResult ? activityResult.ext : '';
      hilog.debug(DOMAIN, TAG, `Activity list loaded: ${this.ActivityList ? 'success' : 'failed'}`);
      if (this.ActivityList) {
        this.ActivityList.forEach(element => {
          hilog.debug(DOMAIN, TAG, `Activity: ${JSON.stringify(element)}`);
        });
      } else {
        throw new Error('签到列表获取为空')
      }
      if (isManualRefresh) {
        promptAction.showToast({ message: '签到活动已刷新' })
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Error in loadActivities: ${(e as Error).message}`);
      promptAction.showToast({ message: `刷新签到活动失败: ${(e as Error).message}` })
    } finally {
      this.isRefreshing = false
    }
  }

  private getStatusText(Activity: ActivityItem): string {
    if (typeof Activity.endTime === 'string') {
      return ChaoxingUtils.isSignActivityStarted(Activity.startTime) ? '无截止日期' :
        `${ChaoxingUtils.getRemainingTime(Activity.startTime) / 60000 << 0}分钟开始签到`
    } else {
      if (ChaoxingUtils.isSignActivityEnded(Activity.endTime)) {
        return '已结束'
      } else if (ChaoxingUtils.isSignActivityActive(Activity.startTime, Activity.endTime)) {
        return `进行中 · ${ChaoxingUtils.getRemainingTime(Activity.endTime) / 60000 << 0}分钟后结束`
      } else {
        return `${ChaoxingUtils.getRemainingTime(Activity.startTime) / 60000 << 0}分钟后开始签到`
      }
    }
  }

  private getStatusColor(Activity: ActivityItem): Resource {
    if (typeof Activity.endTime === 'string') {
      return $r('app.color.secondary_text')
    }
    if (ChaoxingUtils.isSignActivityEnded(Activity.endTime)) {
      return $r('app.color.unsignable')
    } else if (ChaoxingUtils.isSignActivityActive(Activity.startTime, Activity.endTime)) {
      return $r('app.color.signed')
    } else {
      return $r('app.color.selected')
    }
  }

  private isActivityEnded(Activity: ActivityItem): boolean {
    return typeof Activity.endTime === 'number' && ChaoxingUtils.isSignActivityEnded(Activity.endTime)
  }

  private isActivityActive(Activity: ActivityItem): boolean {
    return typeof Activity.endTime === 'number' &&
    ChaoxingUtils.isSignActivityActive(Activity.startTime, Activity.endTime)
  }
}