import { promptAction } from '@kit.ArkUI';
import { DatabaseManager, UserData, UserDataAndId } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import { ChaoxingUtils } from '../utils/utils';
import { hdsEffect } from '@kit.UIDesignKit';

@Reusable
@Component
export struct loginByCommon {
  @Link otherUserList: UserDataAndId[];
  @State username: string = '';
  @State password: string = '';
  @State LoginEnable: boolean = false
  @Link isShow: boolean
  @State commonTranslateY: number = 0
  @State commonScale: number = 1
  @State isLoading: boolean = false
  @State isPasswordVisible: boolean = false
  @State loginBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  async handleLogin() {
    this.isLoading = true
    try {
      const uname = ChaoxingUtils.encryptByAES(this.username)
      const pwd = ChaoxingUtils.encryptByAES(this.password)
      const result = await loginFunction.LoginChaoXing(ChaoxingUtils.getLoginBody(uname, pwd))
      if (result.ok && result.cookies) {
        const cookies = result.cookies
        const info = await loginFunction.getUserInfo(cookies)
        try {
          const dbManager = DatabaseManager.getInstance()
          const userData: UserData = {
            phone: this.username,
            pwd: pwd,
            cookies: cookies,
            uid: info.uid
          };
          let operationResult = await dbManager.insertUser(userData)
          if (operationResult === 1) {
            promptAction.showToast({ message: '登录成功', duration: 2000 })
            this.otherUserList = await dbManager.getAllUsers()
            this.isShow = !this.isShow
          } else if (operationResult === 0) {
            promptAction.showToast({ message: '数据库异常，可能需要重启应用', duration: 10000 })
            let applicationContext = this.getUIContext().getHostContext()?.getApplicationContext();
            applicationContext?.killAllProcesses(false);
          } else {
            promptAction.showToast({ message: '用户已登录', duration: 2000 })
          }
          this.username = ''
          this.password = ''
        } catch (e) {
          this.username = '';
          this.password = '';
          if (e instanceof Error) {
            promptAction.showToast({
              message: '添加失败，请重试' +
                (e.message.includes("手机号已存在，请使用其他手机号") ? ', 该账号已添加' : ''),
              duration: 2000
            })
            this.triggerShakeAnimation()
            return
          }
        }
      } else {
        promptAction.showToast({
          message: result.message,
          duration: 1500,
          bottom: '20%'
        });
        this.username = '';
        this.password = '';
        this.triggerShakeAnimation()
      }
    } finally {
      this.isLoading = false
    }
  }

  build() {
    Column() {

      Text('账号登录')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 20, bottom: 20 })

      Column({ space: 15 }) {
        TextInput({ placeholder: '手机号', text: this.username })
          .type(InputType.PhoneNumber)
          .cancelButton({ style: CancelButtonStyle.INPUT })
          .enterKeyType(EnterKeyType.Next)
          .onChange((value: string) => {
            this.username = value;
            if (this.username && this.password) {
              this.LoginEnable = true
            }
          })
          .placeholderFont({ size: 16 })
          .height(50)
          .width('100%')
          .backgroundColor($r('app.color.text_field_bg'))
          .borderRadius(12)
          .padding({ left: 15, right: 15 })

          Stack({ alignContent: Alignment.End }) {
            TextInput({ placeholder: '密码', text: this.password })
              .type(InputType.Normal)
              .enterKeyType(EnterKeyType.Go)
              .onSubmit(() => {
                if (this.LoginEnable && !this.isLoading) {
                  this.handleLogin()
                }
              })
              .onChange((value: string) => {
                this.password = value;
                if (this.username && this.password) {
                  this.LoginEnable = true
                }
              })
              .fontColor(this.isPasswordVisible ? $r('app.color.primary_text') : Color.Transparent)
              .fontFamily(this.isPasswordVisible ? 'HarmonyOS Sans' : 'monospace')
              .caretColor($r('app.color.primary_text'))
              .placeholderFont({ size: 16 })
              .height(50)
              .width('100%')
              .backgroundColor($r('app.color.text_field_bg'))
              .borderRadius(12)
              .padding({ left: 15, right: 40 })

            if (!this.isPasswordVisible && this.password.length > 0) {
              Text(this.password.replace(/./g, '•'))
                .fontSize(16)
                .fontColor($r('app.color.primary_text'))
                .fontFamily('monospace')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Clip })
                .width('100%')
                .height(50)
                .padding({ left: 15, right: 40 })
                .hitTestBehavior(HitTestMode.None)
            }

          Image(this.isPasswordVisible ? $r('app.media.eye') : $r('app.media.eyeclose'))
            .width(24)
            .height(24)
            .margin({ right: 12 })
            .fillColor($r('app.color.text_placeholder'))
            .onClick(() => {
              this.isPasswordVisible = !this.isPasswordVisible
            })
        }
        .width('100%')
      }
      .padding({ left: 20, right: 20 })
      .margin({ bottom: 30 })

      Button() {
        Row() {
          if (this.isLoading) {
            LoadingProgress().width(20).height(20).color($r('app.color.text_on_primary')).margin({ right: 10 })
            Text('登录中...').fontColor($r('app.color.text_on_primary')).fontSize(18)
              .fontWeight(FontWeight.Medium)
          } else {
            Text('登录').fontColor($r('app.color.text_on_primary')).fontSize(18)
              .fontWeight(FontWeight.Medium)
          }
        }
      }
      .type(ButtonType.Capsule)
      .enabled(this.LoginEnable && !this.isLoading)
      .width('90%')
      .height(50)
      .backgroundColor($r('app.color.selected'))
      .shadow({ radius: 8, color: '#00000020', offsetY: 4 })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.loginBtnLight,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
        })
        .buildEffect())
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
            this.loginBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
          })
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
            this.loginBtnLight = hdsEffect.PointLightSourceType.NONE;
          })
        }
      })
      .onClick(() => {
        this.handleLogin()
      })
      .margin({ bottom: 20 })
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .translate({ y: this.commonTranslateY })
    .scale({ x: this.commonScale, y: this.commonScale })
  }

  // Trigger shake animation for error feedback
  private triggerShakeAnimation() {
    animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
      this.commonTranslateY = 10
      this.commonScale = 0.98
    })
    setTimeout(() => {
      animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
        this.commonTranslateY = -10
      })
      setTimeout(() => {
        animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
          this.commonTranslateY = 0
          this.commonScale = 1
        })
      }, 100)
    }, 100)
  }
}

@Reusable
@Component
export struct loginByURL {
  @Link otherUserList: UserDataAndId[];
  @State LoginURL: string = '';
  @State LoginEnable: boolean = false
  @Link isShow: boolean
  @State urlTranslateY: number = 0
  @State urlScale: number = 1
  @State isLoading: boolean = false
  @State loginBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  async handleLogin() {
    this.isLoading = true
    try {
      const LoginMSG = await loginFunction.LoginByURL(this.LoginURL)
      promptAction.showToast({ message: LoginMSG })
      if (LoginMSG === '添加成功') {
        let dbManager = DatabaseManager.getInstance();
        this.otherUserList = await dbManager.getAllUsers()
        this.isShow = !this.isShow
      } else {
        this.LoginURL = '';
        this.LoginEnable = false
        this.triggerShakeAnimation()
      }
    } finally {
      this.isLoading = false
    }
  }

  build() {
    Column() {

      Text('链接登录')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 20, bottom: 20 })

      Column({ space: 15 }) {
        TextInput({ placeholder: 'URL', text: this.LoginURL })
          .type(InputType.Normal)
          .cancelButton({ style: CancelButtonStyle.INPUT })
          .enterKeyType(EnterKeyType.Go)
          .onSubmit(() => {
            if (this.LoginEnable && !this.isLoading) {
              this.handleLogin()
            }
          })
          .onChange((value: string) => {
            this.LoginURL = value;
            if (this.LoginURL) {
              this.LoginEnable = true
            }
          })
          .placeholderFont({ size: 16 })
          .height(50)
          .width('100%')
          .backgroundColor($r('app.color.text_field_bg'))
          .borderRadius(12)
          .padding({ left: 15, right: 15 })
      }
      .padding({ left: 20, right: 20 })
      .margin({ bottom: 30 })

      Button() {
        Row() {
          if (this.isLoading) {
            LoadingProgress().width(20).height(20).color($r('app.color.text_on_primary')).margin({ right: 10 })
            Text('登录中...').fontColor($r('app.color.text_on_primary')).fontSize(18)
              .fontWeight(FontWeight.Medium)
          } else {
            Text('登录').fontColor($r('app.color.text_on_primary')).fontSize(18)
              .fontWeight(FontWeight.Medium)
          }
        }
      }
      .type(ButtonType.Capsule)
      .enabled(this.LoginEnable && !this.isLoading)
      .width('90%')
      .height(50)
      .backgroundColor($r('app.color.selected'))
      .shadow({ radius: 8, color: '#00000020', offsetY: 4 })
      .onClick(() => {
        this.handleLogin()
      })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.loginBtnLight,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
        })
        .buildEffect())
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
            this.loginBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
          })
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
            this.loginBtnLight = hdsEffect.PointLightSourceType.NONE;
          })
        }
      })
      .margin({ bottom: 20 })
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .translate({ y: this.urlTranslateY })
    .scale({ x: this.urlScale, y: this.urlScale })
  }

  // Trigger shake animation for error feedback
  private triggerShakeAnimation() {
    animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
      this.urlTranslateY = 10
      this.urlScale = 0.98
    })
    setTimeout(() => {
      animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
        this.urlTranslateY = -10
      })
      setTimeout(() => {
        animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
          this.urlTranslateY = 0
          this.urlScale = 1
        })
      }, 100)
    }, 100)
  }
}
