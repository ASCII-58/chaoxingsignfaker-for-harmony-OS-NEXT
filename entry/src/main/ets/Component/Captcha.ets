import { CaptchaPhotosParam, CaptchaPhotosResult, CaptchaApi } from '../utils/captchaApi'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'CaptchaComponent';
const DOMAIN = 0x000B;
const CAPTCHA_MEMORY_PREF = 'captcha_memory'
// 与上游一致的滑块归一化：x = slider / sliderMax * 280 - 8
const CAPTCHA_NORMALIZED_MAX = 280
const CAPTCHA_NORMALIZED_OFFSET = -8

/**
 * 发起验证码的用户上下文
 */
export interface CaptchaUserParam {
  cookies: string
  uname: string
  /** preSign 引用参数：courseId/classId/activePrimaryId/uid(puid) */
  refererParams: CaptchaPhotosParam
}

@Component
export struct CaptchaComponent {
  captchaUser: CaptchaUserParam | null = null
  onValidated?: (validate: string) => void
  onSkip?: () => void
  @State info: CaptchaPhotosResult = {
    token: '',
    imageVerificationVo: {
      shadeImage: '',
      cutoutImage: ''
    },
    captchaId: '',
    type: '',
    version: '',
    captchaKey: '',
    iv: ''
  }
  @State sliderValue: number = 0
  @State containerWidth: number = 0
  @State isLoading: boolean = false
  @State isChecking: boolean = false
  @State errMsg: string = ''
  private readonly sliderMax: number = 280

  aboutToAppear(): void {
    this.refresh()
  }

  async refresh() {
    if (!this.captchaUser) {
      this.errMsg = '缺少验证码用户信息'
      return
    }
    this.isLoading = true
    this.errMsg = ''
    this.sliderValue = 0
    try {
      this.info = await CaptchaApi.getCaptchaPhotos(this.captchaUser.refererParams, this.captchaUser.cookies)
      await this.tryMemoryCheck()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Load captcha failed: ${(e as Error).message}`)
      this.errMsg = '获取验证码失败，请刷新重试'
    } finally {
      this.isLoading = false
    }
  }

  /** 本地验证码记忆：命中则自动校验一次（对齐上游 captchaMemories） */
  private async tryMemoryCheck() {
    if (!this.captchaUser || !this.info.token) {
      return
    }
    try {
      const context = getContext(this) as common.UIAbilityContext
      const pref = await preferences.getPreferences(context, CAPTCHA_MEMORY_PREF)
      const memoryX = await pref.get(this.info.token, -1) as number
      if (memoryX >= 0) {
        const validate = await this.checkPosition(memoryX)
        if (validate) {
          this.finish(validate)
          return
        }
        await pref.delete(this.info.token)
        await pref.flush()
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Captcha memory check failed: ${(e as Error).message}`)
    }
  }

  private async checkPosition(normalizedX: number): Promise<string | null> {
    if (!this.captchaUser) {
      return null
    }
    this.isChecking = true
    try {
      return await CaptchaApi.checkCaptchaResult(this.info, normalizedX, this.captchaUser.refererParams,
        this.captchaUser.cookies)
    } finally {
      this.isChecking = false
    }
  }

  private async saveMemory(normalizedX: number) {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const pref = await preferences.getPreferences(context, CAPTCHA_MEMORY_PREF)
      await pref.put(this.info.token, normalizedX)
      await pref.flush()
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Save captcha memory failed: ${(e as Error).message}`)
    }
  }

  private finish(validate: string) {
    this.onValidated?.(validate)
  }

  private skip() {
    this.onSkip?.()
  }

  private async onSliderEnd(value: number) {
    const normalizedX = Math.round(value / this.sliderMax * CAPTCHA_NORMALIZED_MAX + CAPTCHA_NORMALIZED_OFFSET)
    const validate = await this.checkPosition(normalizedX)
    if (validate) {
      await this.saveMemory(normalizedX)
      this.finish(validate)
    } else {
      promptAction.showToast({ message: '验证码校验失败，请重试', duration: 1500 })
      this.sliderValue = 0
    }
  }

  build() {
    Column() {
      Text(this.captchaUser ? `为 ${this.captchaUser.uname} 完成验证` : '验证码')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .margin({ bottom: 12 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
        }
        .width('100%')
        .aspectRatio(2)
        .justifyContent(FlexAlign.Center)
      } else if (this.errMsg) {
        Column() {
          Text(this.errMsg)
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_warning'))
        }
        .width('100%')
        .aspectRatio(2)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.Start }) {
          Image(this.info.imageVerificationVo.shadeImage)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
          Image(this.info.imageVerificationVo.cutoutImage)
            .position({
              x: this.sliderValue / this.sliderMax * (this.containerWidth - 56)
            })
            .height('100%')
            .aspectRatio(0.35)
            .objectFit(ImageFit.Fill)
        }
        .width('100%')
        .aspectRatio(2)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.containerWidth = newValue.width as number
        })
      }

      Slider({ value: $$this.sliderValue, max: this.sliderMax })
        .blockColor($r('sys.color.ohos_id_color_emphasize'))
        .trackColor($r('sys.color.comp_divider'))
        .selectedColor($r('sys.color.ohos_id_color_emphasize'))
        .enabled(!this.isLoading && !this.errMsg && !this.isChecking)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End) {
            this.onSliderEnd(value)
          }
        })

      Row({ space: 12 }) {
        Button('刷新')
          .layoutWeight(1)
          .fontSize(14)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .enabled(!this.isLoading && !this.isChecking)
          .onClick(() => {
            this.refresh()
          })
        Button('跳过该用户')
          .layoutWeight(1)
          .fontSize(14)
          .backgroundColor($r('sys.color.ohos_id_color_warning'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .enabled(!this.isChecking)
          .onClick(() => {
            this.skip()
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 24 })
  }
}
