import { Sign, SignInfoResult, CommonSignParams, parseSignResult, SignUserParam, UserQueryObject } from '../utils/sign';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';

const TAG = 'GestureSignComponent';
const DOMAIN = 0x0009;
const GESTURE_GRID_SIZE = 9; // 手势网格大小（3x3）
const NEXT_SIGN_INTERVAL_MS = 200; // 对齐上游：代签用户之间的间隔

/**
 * 手势签到组件（支持全部勾选用户代签）
 */
@Component
export struct GestureSignComponent {
  @Prop activityId: string;
  /** 主用户 Cookie，用于加载签到详情与校验手势码 */
  @Prop hostCookies: string;
  /** 返回当前勾选的用户列表 */
  usersProvider: () => Promise<SignUserParam[]>
  /** 需要验证码时弹出验证码并等待 validate，跳过返回 null */
  requestCaptcha?: (cookies: string, uname: string, uid: string) => Promise<string | null>

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
      this.signInfo = await Sign.GetSignInfo(this.hostCookies, this.activityId);
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

    const users = await this.usersProvider();
    if (users.length === 0) {
      promptAction.showToast({ message: '请先选择用户' });
      return;
    }

    try {
      this.isLoading = true;
      const gestureCode = this.gesturePattern.join('');

      const isCorrect = await Sign.CheckSignCode(this.hostCookies, this.activityId, gestureCode);

      if (!isCorrect) {
        this.signResultMsg = '手势错误，请重新绘制';
        this.resetGesture();
        return;
      }

      const commonQueryParams: CommonSignParams = {
        activeId: this.activityId,
        latitude: '',
        longitude: '',
        address: '',
        enc: '',
        signCode: gestureCode
      };

      const results: string[] = [];
      let hasSuccess = false;
      for (let i = 0; i < users.length; i++) {
        const user = users[i];
        try {
          const userQueryParams: UserQueryObject = {
            uid: user.uid,
            name: user.uname,
            fid: user.fid
          };
          let raw = await Sign.DoSignInV2(user.cookies, commonQueryParams, userQueryParams);
          let outcome = parseSignResult(raw);
          if (outcome.needCaptcha && this.requestCaptcha) {
            const validate = await this.requestCaptcha(user.cookies, user.uname, user.uid);
            if (validate) {
              raw = await Sign.DoSignInV2(user.cookies, commonQueryParams, userQueryParams, validate);
              outcome = parseSignResult(raw);
            } else {
              outcome = { kind: 'error', message: '验证码校验被跳过', needCaptcha: false };
            }
          }
          if (outcome.kind === 'success') {
            hasSuccess = true;
          }
          results.push(`${user.uname}: ${outcome.message}`);
        } catch (e) {
          hilog.error(DOMAIN, TAG, `User ${user.uname} sign failed: ${(e as Error).message}`);
          results.push(`${user.uname}: 签到异常`);
        }
        if (i < users.length - 1) {
          await new Promise<void>((resolve) => setTimeout(resolve, NEXT_SIGN_INTERVAL_MS));
        }
      }

      this.isSignSuccess = hasSuccess;
      this.signResultMsg = results.join('\n');
      if (hasSuccess) {
        promptAction.showToast({ message: '签到成功' });
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
      const result = await Sign.DoSignOut(this.hostCookies, this.signInfo.signInId, this.signInfo.signOutId);
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

          Text('请绘制手势图案进行签到（为所有勾选用户代签）')
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
              .fontSize(14)
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

            Button(this.isLoading ? '签到中...' : '提交')
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
              .enabled(!this.isSignSuccess && this.gesturePattern.length > 0 && !this.isLoading)
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
