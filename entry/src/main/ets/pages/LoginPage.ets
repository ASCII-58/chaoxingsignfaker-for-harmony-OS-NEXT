import { curves, promptAction, router } from '@kit.ArkUI';
import { DatabaseManager, UserData } from '../utils/DataBase';
import { ChaoxingUtils } from '../utils/utils';
import { loginFunction } from '../utils/Login';
import { common, Want } from '@kit.AbilityKit';

@Component
struct FloatingTextInput {
  @Prop label: string = ''
  @Prop inputType: InputType = InputType.Normal
  @Prop value: string = ''
  @State isFocused: boolean = false
  onChange: (value: string) => void = () => {}
  onSubmit: () => void = () => {}

  build() {
    Stack() {
      TextInput({ text: this.value })
        .type(this.inputType)
        .showPasswordIcon(this.inputType === InputType.Password)
        .cancelButton({ style: CancelButtonStyle.INPUT })
        .enterKeyType(this.inputType === InputType.Password ? EnterKeyType.Go : EnterKeyType.Next)
        .onChange(this.onChange)
        .onSubmit(this.onSubmit)
        .onFocus(() => {
          this.isFocused = true
        })
        .onBlur(() => {
          this.isFocused = false
        })
        .placeholderFont({ size: 16 })
        .height(56)
        .width('100%')
        .backgroundColor($r('sys.color.ohos_id_color_text_field_bg'))
        .borderRadius(16)
        .padding({ left: 20, right: 20, top: this.isFocused || this.value ? 20 : 0 })
        .border({
          width: this.isFocused ? 2 : 0,
          color: this.isFocused ? $r('sys.color.ohos_id_color_emphasize') : Color.Transparent
        })
      Column() {
        Text(this.label)
          .fontSize(this.isFocused || this.value ? 12 : 16)
          .fontColor(this.isFocused ? $r('sys.color.ohos_id_color_emphasize') :
            $r('app.color.tittle_text'))
          .position({
            left: this.isFocused || this.value ? 12 : 20,
            top: this.isFocused || this.value ? 8 : 18
          })
          .animation({ duration: 200, curve: Curve.EaseOut }) // 关键修复：让属性变化平滑过渡
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%').hitTestBehavior(HitTestMode.None)  // 关键：让触摸穿透到输入框

    }
    .height(56)
    .width('100%')
  }
}
@Builder
export function init(){
  Login()
}

@Component
export default struct Login {
  @State username: string = '';
  @State password: string = '';
  @State LoginEnable: boolean = false
  @State titleOpacity: number = 0
  @State titleTranslateY: number = -50
  @State formOpacity: number = 0
  @State formTranslateY: number = 30
  @State isLoading: boolean = false
  @State shakeTranslateY: number = 0
  @State shakeScale: number = 1
  private pageInfos: NavPathStack = new NavPathStack();
  aboutToAppear() {
    // 标题入口动画
    animateTo({ duration: 600, curve: curves.springMotion(0.6, 0.8), delay: 100 }, () => {
      this.titleOpacity = 1
      this.titleTranslateY = 0
    })
    // 表单入口动画
    animateTo({ duration: 600, curve: curves.springMotion(0.6, 0.8), delay: 300 }, () => {
      this.formOpacity = 1
      this.formTranslateY = 0
    })
  }

  async handleLogin() {
    this.isLoading = true
    try {
      const uname = ChaoxingUtils.encryptByAES(this.username)
      const pwd = ChaoxingUtils.encryptByAES(this.password)
      const result = await loginFunction.LoginChaoXing(ChaoxingUtils.getLoginBody(uname, pwd))

      if (result && result !== '服务器错误，请稍后重试') {
        try {
          const cookies = result
          const info = await loginFunction.getUserInfo(cookies)
          const dbManager = DatabaseManager.getInstance()
          const userData: UserData = {
            phone: this.username,
            pwd: pwd,
            cookies: cookies,
            uid: info.uid
          };
          await dbManager.insertUser(userData, true)

          promptAction.showToast({ message: '登录成功', duration: 2000 })
          this.pageInfos.replacePath({name : "HomePage"},false)
        } catch (e) {
          this.username = '';
          this.password = '';
          if (e instanceof Error) {
            if (e.message.includes('主用户已登录')) {
              promptAction.showToast({ message: '主用户已登录,请勿重复登录', duration: 2000 })
            } else {
              promptAction.showToast({
                message: '登录失败: ' + e.message,
                duration: 2000
              })
            }
            this.triggerShakeAnimation()
          }
        }
      } else {
        promptAction.showToast({
          message: result || '登录失败',
          duration: 1500,
          bottom: '20%'
        });
        this.username = '';
        this.password = '';
        this.triggerShakeAnimation()
      }
    } catch (error) {
      promptAction.showToast({ message: '发生错误，请重试' });
      this.triggerShakeAnimation()
    } finally {
      this.isLoading = false
    }
  }

  build() {
    NavDestination(){
      Scroll() {
        Column() {
          Column().height('15%')

          Text('学习通账号\n登录')
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .width('90%')
            .margin({ bottom: 40 })
            .opacity(this.titleOpacity)
            .translate({ y: this.titleTranslateY })

          Column({ space: 24 }) {
            FloatingTextInput({
              label: '手机号',
              inputType: InputType.PhoneNumber,
              value: this.username,
              onChange: (value: string) => {
                this.username = value;
                if (this.username && this.password) {
                  this.LoginEnable = true
                }
              }
            })

            FloatingTextInput({
              label: '密码',
              inputType: InputType.Password,
              value: this.password,
              onChange: (value: string) => {
                this.password = value;
                if (this.username && this.password) {
                  this.LoginEnable = true
                }
              },
              onSubmit: () => {
                if (this.LoginEnable && !this.isLoading) {
                  this.handleLogin()
                }
              }
            })

            Button() {
              Row() {
                if (this.isLoading) {
                  LoadingProgress().width(24).height(24).color(Color.White).margin({ right: 10 })
                  Text('登录中...').fontColor($r('sys.color.ohos_id_color_text_primary_activated')).fontSize(18)
                    .fontWeight(FontWeight.Medium)
                } else {
                  Text('登录').fontColor($r('sys.color.ohos_id_color_text_primary_activated')).fontSize(18)
                    .fontWeight(FontWeight.Medium)
                }
              }
            }
            .type(ButtonType.Capsule)
            .enabled(this.LoginEnable && !this.isLoading)
            .width('100%')
            .height(56)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .shadow({ radius: 10, color: 'rgba(10, 89, 247, 0.2)', offsetY: 5 })
            .onClick(() => {
              this.handleLogin()
            })
            .margin({ top: 20 })
          }
          .width('90%')
          .opacity(this.formOpacity)
          .translate({ y: this.formTranslateY, x: this.shakeTranslateY })
          .scale({ x: this.shakeScale, y: this.shakeScale }) // 修复：应用缩放变化
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    }.onBackPressed(() => {
      const context = getContext(this) as common.UIAbilityContext;
      context.terminateSelf(); // 这会完全退出应用，进程结束
      return true
    })
    .height('100%')
    .width('100%')
    .hideBackButton(true)
  }

  private triggerShakeAnimation() {
    animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
      this.shakeTranslateY = 10
      this.shakeScale = 0.98
    })
    setTimeout(() => {
      animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
        this.shakeTranslateY = -10
      })
      setTimeout(() => {
        animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
          this.shakeTranslateY = 0
          this.shakeScale = 1
        })
      }, 100)
    }, 100)
  }
}
