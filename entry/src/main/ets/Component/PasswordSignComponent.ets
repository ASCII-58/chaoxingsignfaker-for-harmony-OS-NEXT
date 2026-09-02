import { Sign } from '../utils/sign';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { LightButton } from './LightButton';

const TAG = 'PasswordSignComponent';
const DOMAIN = 0x000A;

/**
 * 签到码签到输入组件（纯输入）：
 * 输入签到码并校验通过后通过 onSignCode 回传；
 * 签到执行由 SignerPage 统一编排，组件不发起签到请求。
 */
@Component
export struct PasswordSignComponent {
  @Prop activityId: string;
  /** 主用户 Cookie，仅用于即时校验签到码 */
  @Prop hostCookies: string;
  /** 签到码位数（0 表示不限制） */
  @Prop codeLength: number = 0;
  /** 校验通过回传签到码，输入变更/清空回传 '' */
  onSignCode?: (code: string) => void

  @State signCode: string = '';
  @State codeReady: boolean = false;
  @State resultMsg: string = '';
  @State isValidating: boolean = false;

  private invalidate() {
    if (this.codeReady) {
      this.codeReady = false;
    }
    this.resultMsg = '';
    this.onSignCode?.('');
  }

  async submitSignCode() {
    if (!this.signCode || this.signCode.length === 0) {
      promptAction.showToast({ message: '请输入签到码' });
      return;
    }

    if (this.codeLength > 0 && this.signCode.length !== this.codeLength) {
      promptAction.showToast({ message: `签到码应为${this.codeLength}位` });
      return;
    }

    try {
      this.isValidating = true;

      const isCorrect = await Sign.CheckSignCode(this.hostCookies, this.activityId, this.signCode);

      if (!isCorrect) {
        this.resultMsg = '签到码错误，请重新输入';
        this.signCode = '';
        this.invalidate();
        return;
      }

      this.resultMsg = '签到码校验通过，请点击下方按钮签到';
      this.codeReady = true;
      this.onSignCode?.(this.signCode);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Sign code validate failed: ${(e as Error).message}`);
      this.resultMsg = `签到码校验失败: ${(e as Error).message}`;
    } finally {
      this.isValidating = false;
    }
  }

  build() {
    Column() {
      if (this.codeLength > 0) {
        Text(`请输入${this.codeLength}位签到码（为所有勾选用户代签）`)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ bottom: 24 })
      } else {
        Text('请输入签到码（为所有勾选用户代签）')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ bottom: 24 })
      }

      // 签到码输入框
      Column() {
        TextInput({ placeholder: '请输入签到码', text: this.signCode })
          .type(InputType.Number)
          .maxLength(this.codeLength > 0 ? this.codeLength : 10)
          .width(250)
          .fontSize(20)
          .textAlign(TextAlign.Center)
          .onChange((value: string) => {
            this.signCode = value;
            this.invalidate();
          })
      }
      .margin({ bottom: 24 })

      // 校验结果信息
      if (this.resultMsg) {
        Text(this.resultMsg)
          .fontSize(14)
          .fontColor(this.codeReady ?
            $r('sys.color.ohos_id_color_emphasize') :
            $r('sys.color.ohos_id_color_warning'))
          .margin({ bottom: 16 })
      }

      // 校验按钮
      LightButton({
        label: this.isValidating ? '校验中...' : '校验签到码',
        btnEnabled: !this.isValidating,
        onButton: () => {
          this.submitSignCode()
        }
      })
        .width(200)
        .margin({ bottom: 8 })
    }
    .width('100%')
    .padding(20)
  }
}
