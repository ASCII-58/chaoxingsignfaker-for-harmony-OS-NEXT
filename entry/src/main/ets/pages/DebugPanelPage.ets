import { promptAction } from '@kit.ArkUI';
import { DebugPage } from '../Component/DebugPage';

// Debug 面板路由页：
// 1. 以 NavDestination 全屏呈现 DebugPage——替代旧的 bindSheet 承载方式，
//    sheet 之上 pushPath 的子页面会被全屏 sheet 遮挡（模型对比页"看不见"）。
// 2. 密码门内置于本页：头像连点直接进入本页，未解锁时先校验密码
//    （TextInput 支持键盘 Enter 提交），通过后再渲染 DebugPage。
@Builder
export function init() {
  DebugPanelPage()
}

@Component
struct DebugPanelPage {
  @State unlocked: boolean = false;
  @State pwdInput: string = '';

  confirmPwd() {
    if (this.pwdInput === 'nnn') {
      this.unlocked = true;
      this.pwdInput = '';
    } else {
      promptAction.showToast({ message: '密码错误' });
      this.pwdInput = '';
    }
  }

  build() {
    NavDestination() {
      if (this.unlocked) {
        DebugPage()
      } else {
        Column() {
          Text('输入调试密码')
            .fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .margin({ bottom: 24 })
          TextInput({ placeholder: '请输入密码', text: $$this.pwdInput })
            .type(InputType.Password)
            .enterKeyType(EnterKeyType.Done)
            .width('80%').height(50)
            .backgroundColor($r('sys.color.ohos_id_color_text_field_sub_bg'))
            .borderRadius(12)
            .margin({ bottom: 20 })
            .onSubmit(() => { this.confirmPwd() })
          Button('确认')
            .width('80%').height(50)
            .fontColor($r('app.color.text_on_primary'))
            .backgroundColor($r('app.color.class_button'))
            .borderRadius(25)
            .onClick(() => { this.confirmPwd() })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      }
    }
    .height('100%')
    .width('100%')
  }
}
