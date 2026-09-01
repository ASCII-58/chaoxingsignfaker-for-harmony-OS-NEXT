import { Sign, SignInfoResult, CommonSignParams, parseSignResult, SignUserParam, UserQueryObject } from '../utils/sign';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';

const TAG = 'PasswordSignComponent';
const DOMAIN = 0x000A;
const NEXT_SIGN_INTERVAL_MS = 200; // 对齐上游：代签用户之间的间隔

/**
 * 签到码签到组件（支持全部勾选用户代签）
 */
@Component
export struct PasswordSignComponent {
  @Prop activityId: string;
  /** 主用户 Cookie，用于加载签到详情与校验签到码 */
  @Prop hostCookies: string;
  /** 返回当前勾选的用户列表 */
  usersProvider: () => Promise<SignUserParam[]>
  /** 需要验证码时弹出验证码并等待 validate，跳过返回 null */
  requestCaptcha?: (cookies: string, uname: string, uid: string) => Promise<string | null>

  @State signInfo: SignInfoResult | null = null;
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State signCode: string = '';
  @State isSignSuccess: boolean = false;
  @State signResultMsg: string = '';
  @State numberCount: number = 0;
  @State shineTranslateSubmit: string = '-100%';
  @State shineTranslateSignOut: string = '-100%';
  @State submitBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State signoutBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  async aboutToAppear() {
    await this.loadSignInfo();
  }

  async loadSignInfo() {
    try {
      this.isLoading = true;
      this.signInfo = await Sign.GetSignInfo(this.hostCookies, this.activityId);
      this.numberCount = this.signInfo.numberCount || 4;
      hilog.info(DOMAIN, TAG, `Sign info loaded, code length: ${this.numberCount}`);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Load sign info failed: ${e.message}`);
      this.errorMsg = `加载失败: ${e.message}`;
    } finally {
      this.isLoading = false;
    }
  }

  async submitSignCode() {
    if (!this.signCode || this.signCode.length === 0) {
      promptAction.showToast({ message: '请输入签到码' });
      return;
    }

    if (this.numberCount > 0 && this.signCode.length !== this.numberCount) {
      promptAction.showToast({ message: `签到码应为${this.numberCount}位` });
      return;
    }

    const users = await this.usersProvider();
    if (users.length === 0) {
      promptAction.showToast({ message: '请先选择用户' });
      return;
    }

    try {
      this.isLoading = true;

      const isCorrect = await Sign.CheckSignCode(this.hostCookies, this.activityId, this.signCode);

      if (!isCorrect) {
        this.signResultMsg = '签到码错误，请重新输入';
        this.signCode = '';
        return;
      }

      const commonQueryParams: CommonSignParams = {
        activeId: this.activityId,
        latitude: '',
        longitude: '',
        address: '',
        enc: '',
        signCode: this.signCode
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
      hilog.error(DOMAIN, TAG, `Password sign failed: ${e.message}`);
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
          Text('签到码签到')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 20, bottom: 10 })

          if (this.numberCount > 0) {
            Text(`请输入${this.numberCount}位签到码（为所有勾选用户代签）`)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ bottom: 30 })
          } else {
            Text('请输入签到码（为所有勾选用户代签）')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ bottom: 30 })
          }

          // 签到码输入框
          Column() {
            TextInput({ placeholder: '请输入签到码', text: this.signCode })
              .type(InputType.Number)
              .maxLength(this.numberCount > 0 ? this.numberCount : 10)
              .width(250)
              .fontSize(20)
              .textAlign(TextAlign.Center)
              .onChange((value: string) => {
                this.signCode = value;
              })
              .enabled(!this.isSignSuccess)
          }
          .margin({ bottom: 30 })

          // 结果信息
          if (this.signResultMsg) {
            Text(this.signResultMsg)
              .fontSize(14)
              .fontColor(this.isSignSuccess ?
                $r('sys.color.ohos_id_color_emphasize') :
                $r('sys.color.ohos_id_color_warning'))
              .margin({ bottom: 20 })
          }

          // 提交按钮
          Button(this.isLoading ? '签到中...' : '提交签到')
            .width(200)
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
              this.submitSignCode()
            })
            .enabled(!this.isSignSuccess && !this.isLoading)
            .margin({ bottom: 20 })

          // 签退按钮
          if (this.signInfo && this.signInfo.signOutId > 0 &&
              this.signInfo.signOutPublishTimeStamp > 0 && this.isSignSuccess) {
            Column() {
              Divider()
                .width(200)
                .margin({ top: 20, bottom: 20 })

              Text('签退可用')
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .margin({ bottom: 10 })

              Button('签退')
                .width(150)
                .fontColor($r('app.color.text_on_primary'))
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
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
  }
}
