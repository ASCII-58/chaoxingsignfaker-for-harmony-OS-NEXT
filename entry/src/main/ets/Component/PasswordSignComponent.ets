import { Sign, SignInfoResult } from '../utils/sign';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';

const TAG = 'PasswordSignComponent';
const DOMAIN = 0x000A;

/**
 * 签到码签到组件
 */
@Component
export struct PasswordSignComponent {
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
      this.signInfo = await Sign.GetSignInfo(this.cookies, this.activityId);
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

    try {
      this.isLoading = true;
      
      const isCorrect = await Sign.CheckSignCode(this.cookies, this.activityId, this.signCode);
      
      if (!isCorrect) {
        this.signResultMsg = '签到码错误，请重新输入';
        this.signCode = '';
        return;
      }

      const queryParams = Sign.buildSignQueryParams(
        this.activityId,
        this.uid,
        this.uname,
        this.fid
      );

      const result = await Sign.DoSignWithCode(this.cookies, queryParams, this.signCode);
      
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
          Text('签到码签到')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 20, bottom: 10 })

          if (this.numberCount > 0) {
            Text(`请输入${this.numberCount}位签到码`)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ bottom: 30 })
          } else {
            Text('请输入签到码')
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
              .fontSize(16)
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
