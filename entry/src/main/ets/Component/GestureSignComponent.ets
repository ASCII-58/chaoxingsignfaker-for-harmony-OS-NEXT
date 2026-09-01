import { Sign } from '../utils/sign';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';

const TAG = 'GestureSignComponent';
const DOMAIN = 0x0009;
const GESTURE_GRID_SIZE = 9; // 手势网格大小（3x3）

/**
 * 手势签到输入组件（纯输入）：
 * 绘制手势并校验通过后通过 onSignCode 回传手势码；
 * 签到执行由 SignerPage 统一编排，组件不发起签到请求。
 */
@Component
export struct GestureSignComponent {
  @Prop activityId: string;
  /** 主用户 Cookie，仅用于即时校验手势码 */
  @Prop hostCookies: string;
  /** 校验通过回传手势码，重置/失效回传 '' */
  onSignCode: (code: string) => void

  @State gesturePattern: number[] = []; // 手势顺序
  @State gesturePoints: boolean[] = Array(GESTURE_GRID_SIZE).fill(false);
  @State codeReady: boolean = false;
  @State resultMsg: string = '';
  @State isValidating: boolean = false;
  @State resetBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State submitBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  onGesturePointClick(index: number) {
    if (this.codeReady) {
      return;
    }
    if (!this.gesturePoints[index]) {
      this.gesturePoints[index] = true;
      this.gesturePattern.push(index + 1);
      hilog.debug(DOMAIN, TAG, `Gesture pattern: ${this.gesturePattern.join(',')}`);
    }
  }

  resetGesture() {
    this.gesturePoints = Array(GESTURE_GRID_SIZE).fill(false);
    this.gesturePattern = [];
    this.resultMsg = '';
    if (this.codeReady) {
      this.codeReady = false;
      this.onSignCode('');
    }
  }

  async submitGesture() {
    if (this.gesturePattern.length === 0) {
      promptAction.showToast({ message: '请绘制手势' });
      return;
    }

    try {
      this.isValidating = true;
      const gestureCode = this.gesturePattern.join('');

      const isCorrect = await Sign.CheckSignCode(this.hostCookies, this.activityId, gestureCode);

      if (!isCorrect) {
        this.resultMsg = '手势错误，请重新绘制';
        this.resetGesture();
        return;
      }

      this.resultMsg = '手势校验通过，请点击下方按钮签到';
      this.codeReady = true;
      this.onSignCode(gestureCode);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Gesture validate failed: ${(e as Error).message}`);
      this.resultMsg = `手势校验失败: ${(e as Error).message}`;
    } finally {
      this.isValidating = false;
    }
  }

  build() {
    Column() {
      Text('请绘制手势图案（为所有勾选用户代签）')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .margin({ bottom: 24 })

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
      .margin({ bottom: 24 })

      // 手势顺序显示
      if (this.gesturePattern.length > 0) {
        Text(`手势顺序: ${this.gesturePattern.join(' → ')}`)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .margin({ bottom: 16 })
      }

      // 校验结果信息
      if (this.resultMsg) {
        Text(this.resultMsg)
          .fontSize(14)
          .fontColor(this.codeReady ?
            $r('sys.color.ohos_id_color_emphasize') :
            $r('sys.color.ohos_id_color_warning'))
          .margin({ bottom: 16 })
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
          .margin({ right: 10 })

        Button(this.isValidating ? '校验中...' : '校验手势')
          .width(120)
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
          .enabled(!this.codeReady && this.gesturePattern.length > 0 && !this.isValidating)
      }
      .margin({ bottom: 8 })
    }
    .width('100%')
    .padding(20)
  }
}
