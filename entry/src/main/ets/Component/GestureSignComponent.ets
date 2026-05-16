import { Sign, SignInfoResult } from '../utils/sign';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';

const TAG = 'GestureSignComponent';
const DOMAIN = 0x0009;
const GESTURE_GRID_SIZE = 9; // 手势网格大小（3x3）

/**
 * 手势签到组件
 */
@Component
export struct GestureSignComponent {
  @Prop activityId: string;
  @Prop courseId: string;
  @Prop classId: string;
  @Prop cookies: string;
  @Prop uid: number;
  @Prop uname: string;
  @Prop fid: number;
  
  @State signInfo: SignInfoResult | null = null;
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State gesturePattern: number[] = []; // 手势顺序
  @State isSignSuccess: boolean = false;
  @State signResultMsg: string = '';
  @State gesturePoints: boolean[] = Array(GESTURE_GRID_SIZE).fill(false);
  @State shineTranslateReset: string = '-100%';
  @State shineTranslateSubmit: string = '-100%';
  @State shineTranslateSignOut: string = '-100%';
  @State resetBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State submitBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State signoutBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  async aboutToAppear() {
    await this.loadSignInfo();
  }

  async loadSignInfo() {
    try {
      this.isLoading = true;
      this.signInfo = await Sign.GetSignInfo(this.cookies, this.activityId);
      hilog.info(DOMAIN, TAG, 'Sign info loaded successfully');
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Load sign info failed: ${e.message}`);
      this.errorMsg = `加载失败: ${e.message}`;
    } finally {
      this.isLoading = false;
    }
  }

  onGesturePointClick(index: number) {
    if (this.isSignSuccess) return;
    
    if (!this.gesturePoints[index]) {
      this.gesturePoints[index] = true;
      this.gesturePattern.push(index + 1);
      hilog.debug(DOMAIN, TAG, `Gesture pattern: ${this.gesturePattern.join(',')}`);
    }
  }

  resetGesture() {
    this.gesturePoints = Array(GESTURE_GRID_SIZE).fill(false);
    this.gesturePattern = [];
    this.signResultMsg = '';
  }

  async submitGesture() {
    if (this.gesturePattern.length === 0) {
      promptAction.showToast({ message: '请绘制手势' });
      return;
    }

    try {
      this.isLoading = true;
      const gestureCode = this.gesturePattern.join('');
      
      const isCorrect = await Sign.CheckSignCode(this.cookies, this.activityId, gestureCode);
      
      if (!isCorrect) {
        this.signResultMsg = '手势错误，请重新绘制';
        this.resetGesture();
        return;
      }

      const queryParams = Sign.buildSignQueryParams(
        this.activityId,
        this.uid,
        this.uname,
        this.fid
      );

      const result = await Sign.DoSignWithCode(this.cookies, queryParams, gestureCode);
      
      if (result === 'success') {
        this.isSignSuccess = true;
        this.signResultMsg = '签到成功！';
        promptAction.showToast({ message: '签到成功' });
      } else if (result === '您已签到过了') {
        this.signResultMsg = '您已签到过了';
      } else if (result === 'validate') {
        this.signResultMsg = '需要验证码，请稍后重试';
      } else {
        this.signResultMsg = `签到失败: ${result}`;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Gesture sign failed: ${e.message}`);
      this.signResultMsg = `签到失败: ${e.message}`;
    } finally {
      this.isLoading = false;
    }
  }

  async doSignOut() {
    try {
      if (!this.signInfo) {
        promptAction.showToast({ message: '获取信息失败' });
        return;
      }
      const result = await Sign.DoSignOut(this.cookies, this.signInfo.signInId, this.signInfo.signOutId);
      promptAction.showToast({ message: '签退成功' });
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Sign out failed: ${e.message}`);
      promptAction.showToast({ message: `签退失败: ${e.message}` });
    }
  }

  build() {
    Column() {
      if (this.isLoading && !this.signInfo) {
        LoadingProgress()
          .width(50)
          .height(50)
          .margin({ top: 50 })
      } else if (this.errorMsg) {
        Text(this.errorMsg)
          .fontSize(16)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .margin({ top: 50 })
      } else {
        Column() {
          Text('手势签到')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 20, bottom: 10 })

          Text('请绘制手势图案进行签到')
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .margin({ bottom: 30 })

          // 手势绘制区域
          Grid() {
            ForEach(Array.from<number, number>({ length: GESTURE_GRID_SIZE }, (_, i: number) => i), (index: number) => {
              GridItem() {
                Circle({ width: 60, height: 60 })
                  .fill(this.gesturePoints[index] ? 
                    $r('sys.color.ohos_id_color_emphasize') : 
                    $r('sys.color.ohos_id_color_component_normal'))
                  .onClick(() => this.onGesturePointClick(index))
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr')
          .rowsTemplate('1fr 1fr 1fr')
          .width(250)
          .height(250)
          .columnsGap(20)
          .rowsGap(20)
          .margin({ bottom: 30 })

          // 手势顺序显示
          if (this.gesturePattern.length > 0) {
            Text(`手势顺序: ${this.gesturePattern.join(' → ')}`)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .margin({ bottom: 20 })
          }

          // 结果信息
          if (this.signResultMsg) {
            Text(this.signResultMsg)
              .fontSize(16)
              .fontColor(this.isSignSuccess ? 
                $r('sys.color.ohos_id_color_emphasize') : 
                $r('sys.color.ohos_id_color_warning'))
              .margin({ bottom: 20 })
          }

          // 操作按钮
          Row() {
            Button('重置')
              .width(100)
              .fontColor($r('app.color.text_on_primary'))
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.resetBtnLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                    this.resetBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
                  })
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                    this.resetBtnLight = hdsEffect.PointLightSourceType.NONE;
                  })
                }
              })
              .onClick(() => {
                this.resetGesture()
              })
              .enabled(!this.isSignSuccess)
              .margin({ right: 10 })

            Button('提交')
              .width(100)
              .fontColor($r('app.color.text_on_primary'))
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.submitBtnLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                    this.submitBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
                  })
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                    this.submitBtnLight = hdsEffect.PointLightSourceType.NONE;
                  })
                }
              })
              .onClick(() => {
                this.submitGesture()
              })
              .enabled(!this.isSignSuccess && this.gesturePattern.length > 0)
          }
          .margin({ bottom: 20 })

          // 签退按钮
          if (this.signInfo && this.signInfo.signOutId > 0 && 
              this.signInfo.signOutPublishTimeStamp > 0 && this.isSignSuccess) {
            Button('签退')
              .width(150)
              .fontColor($r('app.color.text_on_primary'))
              .margin({ top: 20 })
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.signoutBtnLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                    this.signoutBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
                  })
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                    this.signoutBtnLight = hdsEffect.PointLightSourceType.NONE;
                  })
                }
              })
              .onClick(() => {
                this.doSignOut()
              })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
  }
}
