import { ActivityInfo, SignType } from './ActivityListPage';
import { Sign } from '../utils/sign';
import { JSON } from '@kit.ArkTS';
import { FunctionalButton, functionalButtonComponentManager } from '@kit.ScenarioFusionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager, UserDataAndId } from '../utils/DataBase';
import { image } from '@kit.ImageKit';
import { loginFunction } from '../utils/Login';
import fs from '@ohos.file.fs';
import request from '@ohos.request';
import { ChaoxingUtils } from '../utils/utils';
import { picker } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { GestureSignComponent } from '../Component/GestureSignComponent';
import { PasswordSignComponent } from '../Component/PasswordSignComponent';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import UrlTools from '../utils/urlTools';
import { hdsEffect } from '@kit.UIDesignKit';

const TAG = 'SignerPage';
const DOMAIN = 0x0008;

// 定义用户对象接口
interface userMenu {
  uname: string
  id: number
  SignPermission: number
}

// 定义主用户信息接口
interface HostUserInfo {
  cookies: string;
  uid: number;
  uname: string;
  fid: number;
}

// 定义图片上传需要的 Token 接口
interface CookiesTokenPUID {
  cookies: string
  Token: string
  PUID: string
}

// ---------------------------------------------------------------
// 组件 1: 用户头像图标
// 优化：增加加载占位、适配深色模式边框
// ---------------------------------------------------------------
@Reusable
@Component
struct Icon {
  @Prop UserId: number;
  @State ImageData: image.PixelMap | null = null;
  @State isLoaded: boolean = false;

  build() {
    Stack() {
      if (this.ImageData) {
        Image(this.ImageData)
          .width(48)
          .height(48)
          .borderRadius(24) // 圆形
          .objectFit(ImageFit.Cover)
          .border({ width: 1, color: $r('sys.color.comp_divider') }) // 系统分割线颜色
      } else {
        // 加载占位图
        Circle({ width: 48, height: 48 })
          .fill($r('sys.color.ohos_id_color_component_normal')) // 系统组件默认色
      }
    }
    .margin({ right: 12 })
    .onAppear(async () => {
      try {
        const dbManager = DatabaseManager.getInstance()
        let userData: UserDataAndId | null = null

        if (this.UserId === 0) {
          // ID=0 表示主用户，从 HostUser 表获取
          userData = await dbManager.getUserByPosition(1, true) as UserDataAndId;
        } else {
          // 其他用户从 OtherUser 表获取
          userData = await dbManager.getUserByPosition(this.UserId, false) as UserDataAndId;
        }

        if (userData) {
          const url = (await loginFunction.getUserInfo(userData.cookies)).pic
          this.ImageData = await loginFunction.GetPic(url) as image.PixelMap
          this.isLoaded = true;
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `[Icon] Load failed for user ${this.UserId}:`, e);
      }
    })
  }
}

// ---------------------------------------------------------------
// 组件 2: 用户列表项
// 优化：交互动画优化、使用 Checkbox 指示选中状态、适配深色模式
// ---------------------------------------------------------------
@Reusable
@Component
struct userItem {
  @State bgColor: Resource = $r('sys.color.ohos_id_color_card_bg'); // 默认卡片背景
  @Prop user: userMenu
  @Link @Watch('onSelectionChange') signIdArray: number[]

  onSelectionChange() {
    const isSelected = this.signIdArray.includes(this.user.id);
    // 选中时稍微改变背景色以示强调（可选），这里主要靠 Checkbox
    // this.bgColor = isSelected ? $r('sys.color.ohos_id_color_emphasize', 0.1) : $r('sys.color.ohos_id_color_card_bg');
  }

  build() {
    Row() {
      Icon({ UserId: this.user.id })

      Column() {
        Text(this.user.uname)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))

        Text(this.user.SignPermission === 1 ? '可签到' : this.user.SignPermission === 0 ? '已签到' : '无权限')
          .fontSize(12)
          .fontColor(this.user.SignPermission === 1 ? $r('sys.color.ohos_id_color_text_secondary') :
            $r('sys.color.ohos_id_color_warning'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 使用 Checkbox 代替纯背景色变化，交互更明确
      Checkbox()
        .select(this.signIdArray.includes(this.user.id))
        .selectedColor($r('sys.color.ohos_id_color_connected'))
        .hitTestBehavior(HitTestMode.None) // 让点击事件穿透到 Row
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.bgColor)
    .borderRadius(12)
    .margin({ bottom: 8 })
  }
}

// ---------------------------------------------------------------
// 组件 3: 图片选择器
// 优化：UI 样式微调，逻辑保持不变
// ---------------------------------------------------------------
@Reusable
@Component
struct photoPicker {
  @State displayURI: string = ''
  @Link signIdArray: Array<number>
  @State signerInfoArr: CookiesTokenPUID[] = []
  @Link objectidArray: string[]
  @Link otherUserDialogIsShow: boolean // 添加控制用户选择对话框的链接
  @Prop otherUser: Array<userMenu> // 添加其他用户列表
  @State uploadStatus: string = '' // 上传状态反馈
  @State isUploading: boolean = false // 是否正在上传
  @State uploadCompletedCount: number = 0 // 已完成上传的数量（成功或失败）
  @State uploadTotalCount: number = 0 // 总上传数量
  @State photoBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  build() {
    Column() {
      // 状态指示点
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.signIdArray, (signId: number, index: number) => {
          Circle({ width: 8, height: 8 })
            .fill(this.objectidArray[index] ? $r('sys.color.ohos_id_color_connected') :
              $r('sys.color.ohos_id_color_warning'))
            .margin(4)
        })
      }
      .padding(10)
      .width('100%')

      // 上传状态反馈文本
      if (this.uploadStatus) {
        Text(this.uploadStatus)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 8, bottom: 8 })
      }

      Button() {
        Stack() {
          Text('选择图片 / 拍照').fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
        }
      }
        .type(ButtonType.Capsule)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .width('60%')
        .margin({ top: 12 })
        .enabled(!this.isUploading)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.photoBtnLight,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                this.photoBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
              })
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                this.photoBtnLight = hdsEffect.PointLightSourceType.NONE;
              })
            }
          })
        .onClick(async () => {
          this.showPhotoConfirmDialog()
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .borderRadius(16)
  }

  // 显示图片选择确认对话框
  private showPhotoConfirmDialog() {
    if (this.signIdArray.length === 0) {
      AlertDialog.show({
        title: '提示',
        message: '请先选择至少一个用户',
        confirm: {
          value: '知道了',
          action: () => {
            this.otherUserDialogIsShow = true
          }
        }
      })
      return
    }

    const selectedUsers = this.otherUser.filter(u => this.signIdArray.includes(u.id));
    const userNames = selectedUsers.map(u => u.uname).join('、');

    AlertDialog.show({
      title: '确认上传图片',
      message: `将为以下用户上传图片：\n${userNames}\n\n是否继续？`,
      primaryButton: {
        value: '修改用户',
        action: () => {
          this.otherUserDialogIsShow = true
        }
      },
      secondaryButton: {
        value: '确认上传',
        action: () => {
          this.handlePhotoSelect()
        }
      }
    })
  }

  // 抽离图片处理逻辑，保持 build 干净
  private async handlePhotoSelect() {
    this.objectidArray = []
    this.uploadCompletedCount = 0
    this.uploadStatus = '正在准备上传...'
    this.isUploading = true
    const dbManager = DatabaseManager.getInstance()

    try {
      this.signerInfoArr = await Promise.all(
        this.signIdArray.map(async userId => {
          let info: CookiesTokenPUID = { cookies: '', Token: '', PUID: '' }

          if (userId === 0) {
            // 主用户
            info.cookies = ((await dbManager.getUserByPosition(1, true)) as UserDataAndId).cookies
          } else {
            // 其他用户
            info.cookies = ((await dbManager.getUserByPosition(userId)) as UserDataAndId).cookies
          }

          info.PUID = (await loginFunction.getUserInfo(info.cookies)).puid
          info.Token = await Sign.GetToken(info.cookies)
          return info
        }))

      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = this.signIdArray.length;
      const photoViewPicker = new picker.PhotoViewPicker();
      const context = this.getUIContext().getHostContext() as Context

      const res = await photoViewPicker.select(photoSelectOptions)
      const uriArr = res.photoUris
      const signerNum = this.signerInfoArr.length
      this.uploadTotalCount = signerNum

      this.uploadStatus = `正在上传图片 (0/${signerNum})`
      promptAction.showToast({ message: '开始上传图片', duration: 1500 })

      for (let index = 0; index < signerNum; index++) {
        const uri = uriArr[index % uriArr.length]
        const fileType = 'jpg'
        const fileName = ChaoxingUtils.generatePhotoName() + '.' + fileType
        const copyFilePath = context.cacheDir + '/' + fileName

        try {
          const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
          fs.copyFileSync(file.fd, copyFilePath)

          const uploadConfig: request.UploadConfig = {
            url: `https://pan-yz.chaoxing.com/upload?_from=mobilelearn&_token=${this.signerInfoArr[index].Token}`,
            method: 'POST',
            header: { "Content-Type": "multipart/form-data" },
            files: [{
              filename: fileName,
              type: fileType,
              name: 'file',
              uri: `internal://cache/${fileName}`
            }],
            data: [{ name: 'puid', value: this.signerInfoArr[index].PUID.toString() }]
          }
          // 不使用await，允许并行上传
          this.uploadPhoto(context, uploadConfig, index)
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'File processing failed', JSON.stringify(error))
          promptAction.showToast({ message: `图片 ${index + 1} 处理失败`, duration: 2000 })
          this.uploadCompletedCount++
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Photo selection failed', JSON.stringify(error))
      this.uploadStatus = '图片选择失败'
      this.isUploading = false
      promptAction.showToast({ message: '图片选择失败', duration: 2000 })
    }
  }

  private async uploadPhoto(context: Context, uploadConfig: request.UploadConfig, signIndex: number) {
    try {
      const task = await request.uploadFile(context, uploadConfig)

      task.on("fail", (event) => {
        hilog.error(DOMAIN, TAG, `Upload failed for index ${signIndex}`, JSON.stringify(event))
        promptAction.showToast({ message: `图片 ${signIndex + 1} 上传失败`, duration: 2000 })

        // 更新完成计数
        this.uploadCompletedCount++
        const uploadedCount = this.objectidArray.filter(id => id).length
        this.uploadStatus = `上传失败 (${uploadedCount}/${this.uploadTotalCount})`

        // 检查是否所有上传都已完成
        if (this.uploadCompletedCount >= this.uploadTotalCount) {
          this.isUploading = false
          if (uploadedCount === 0) {
            this.uploadStatus = '所有图片上传失败'
          }
        }
      })

      task.on('complete', () => {
        // 更新完成计数
        this.uploadCompletedCount++
        const uploadedCount = this.objectidArray.filter(id => id).length
        this.uploadStatus = `已上传 ${uploadedCount}/${this.uploadTotalCount}`

        // 检查是否所有上传都已完成
        if (this.uploadCompletedCount >= this.uploadTotalCount) {
          this.isUploading = false
          if (uploadedCount === this.uploadTotalCount) {
            this.uploadStatus = '所有图片上传完成 ✓'
            promptAction.showToast({ message: '所有图片上传成功', duration: 2000 })
          }
        }
      })

      task.on('headerReceive', (value) => {
        if (value && value['body']) {
          try {
            const bodyObj = JSON.parse(value['body']) as object
            this.objectidArray[signIndex] = bodyObj['objectId'] as string

            // 更新上传状态
            const uploadedCount = this.objectidArray.filter(id => id).length
            this.uploadStatus = `已上传 ${uploadedCount}/${this.uploadTotalCount}`

            console.info(`Photo ${signIndex + 1} uploaded successfully`)
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'Failed to parse upload response', e)
          }
        }
      })
    } catch (e) {
      hilog.error(DOMAIN, TAG, "Upload task creation failed", e)
      promptAction.showToast({ message: `图片 ${signIndex + 1} 上传失败`, duration: 2000 })

      // 更新完成计数
      this.uploadCompletedCount++
      const uploadedCount = this.objectidArray.filter(id => id).length
      this.uploadStatus = `上传失败 (${uploadedCount}/${this.uploadTotalCount})`

      // 检查是否所有上传都已完成
      if (this.uploadCompletedCount >= this.uploadTotalCount) {
        this.isUploading = false
      }
    }
  }
}

@Reusable
@Component
struct QRCodeLocation {
  @Prop ActivityId: string;
  @Link queryParams: object
  @State DestinationLocationName: string = '获取中...'
  @State Position: object = JSON.parse('{"result":1,"mockData":"{\\"strategy\\":0,\\"probability\\":-1}"}') as object

  build() {
    Column() {
      Text('要求位置')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Row() {
        Text(this.DestinationLocationName)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
      .borderRadius(12)
      .border({ width: 1, color: $r('sys.color.comp_divider') })
      .onClick(() => {
        if (this.DestinationLocationName !== '获取中...' && this.DestinationLocationName !== '该签到无要求位置') {
          this.copyText(this.DestinationLocationName)
        }
      })

      // 已选坐标展示
      if (this.Position?.['address']) {
        Column() {
          Text(`已选位置: ${this.Position['address']}`)
            .fontSize(14).fontColor($r('sys.color.ohos_id_color_text_primary')).margin({ top: 8 })
          Text(`经度: ${this.Position['longitude']}`)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
          Text(`纬度: ${this.Position['latitude']}`)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        }.alignItems(HorizontalAlign.Start).width('100%').margin({ top: 8 })
      } else {
        Text('请点击下方按钮选择位置')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .margin({ top: 16, bottom: 4 })
          .width('100%')
      }

      // 地图选点按钮 (FunctionalButton)
      Column() {
        FunctionalButton({
          params: {
            openType: functionalButtonComponentManager.OpenType.CHOOSE_LOCATION,
            label: '打开地图选点',
            styleOption: {
              bgColor: functionalButtonComponentManager.ColorType.DEFAULT,
              size: functionalButtonComponentManager.SizeType.DEFAULT,
              plain: false,
              disabled: false,
              loading: false,
              hoverClass: functionalButtonComponentManager.HoverClassType.HOVER_CLASS,
              hoverStartTime: 0,
              hoverStayTime: 0,
              styleConfig: new functionalButtonComponentManager.ButtonConfig().fontSize(16)
            },
          },
          controller: new functionalButtonComponentManager.FunctionalButtonController()
            .onChooseLocation((err, data) => {
              if (err) {
                hilog.error(0x0000, "Sign", "Location Error: %{public}s", err.message);
                return;
              }
              const LoginLocation = ChaoxingUtils.gcj02_to_bd09(data.latitude, data.longitude)
              this.Position['address'] = data.name as string;
              this.Position['longitude'] = LoginLocation.lon as number;
              this.Position['latitude'] = LoginLocation.lat as number;
              this.queryParams['location'] = JSON.stringify(this.Position)
            })
        }).enabled(this.DestinationLocationName !== '获取中...' && this.DestinationLocationName !== '该签到无要求位置')
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(16)
    .width('100%')
  }

  // 1. 逻辑方法：复制文本
  private copyText(text: string) {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    const systemPasteboard = pasteboard.getSystemPasteboard()
    systemPasteboard.setData(pasteboardData)
    promptAction.showToast({ message: '已复制到剪贴板', duration: 1500 })
  }
}

// ---------------------------------------------------------------
// 全局 Builder
// ---------------------------------------------------------------

@Builder
export function initSignInfo(name: string, activityInfo: ActivityInfo) {
  SignPage({ activityInfo: activityInfo })
}

// ---------------------------------------------------------------
// 主页面: SignPage
// 优化：重构布局、使用 Scroll、layoutWeight、抽离逻辑、深色模式适配
// ---------------------------------------------------------------
@Component
export struct SignPage {
  // State Definitions
  @State canSign: boolean = true;
  @State activityInfo: null | ActivityInfo = null
  @State queryParams: object = JSON.parse('{}') as object
  @State otherUser: Array<userMenu> = []
  @State signIdArray: Array<number> = []
  @State ifPhoto: boolean = false
  @State otherUserDialogIsShow: boolean = false
  @State objectidArr: string[] = []
  @State DestinationLocationName: string = '获取中...' // 初始状态
  @State hostUser: HostUserInfo | null = null
  @State shineTranslateSign: string = '-100%'
  @State signBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  pathInfos: NavPathStack = new NavPathStack();

  // 4. UI Builders
  @Builder
  otherUserMenu() {
    List() {
      ForEach(this.otherUser, (user: userMenu) => {
        ListItem() {
          userItem({ user, signIdArray: this.signIdArray })
        }
        .onClick(() => {
          if (user.SignPermission===-1) {
            promptAction.showToast({ message: '该用户不在班级', duration: 1500 })
            return
          }
          if (this.signIdArray.includes(user.id)) {
            this.signIdArray = this.signIdArray.filter(num => num !== user.id)
          } else {
            this.signIdArray.push(user.id)
          }
        })
      })
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  @Builder
  UserSelectionCard() {
    Column() {
      Row() {
        Text('签到用户')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)

        Button('选择用户')
          .fontSize(13)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            this.otherUserDialogIsShow = true
          })
          .bindSheet($$this.otherUserDialogIsShow, this.otherUserMenu, {
            title: { title: $r('app.string.other_user') },
            backgroundColor: $r('sys.color.ohos_id_color_dialog_bg'),
            detents: [SheetSize.MEDIUM, SheetSize.LARGE]
          })
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (this.signIdArray.length === 0) {
        Text('请选择至少一个用户进行签到')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .padding({ top: 8, bottom: 4 })
      } else {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.signIdArray, (userId: number) => {
            ForEach(this.otherUser.filter(u => u.id === userId), (user: userMenu) => {
              Row() {
                Text(user.uname)
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                Image($r('sys.media.ohos_ic_public_close'))
                  .width(14).height(14)
                  .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
                  .margin({ left: 4 })
              }
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor($r('sys.color.ohos_id_color_emphasize', 0.1))
              .borderRadius(14)
              .margin({ right: 8, bottom: 6 })
              .onClick(() => {
                this.signIdArray = this.signIdArray.filter(num => num !== user.id)
              })
            })
          })
        }
      }
    }
    .padding(14)
    .width('100%')
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .borderRadius(14)
    .margin({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  LocationCard() {
    Column() {
      Row() {
        Text('要求位置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
      }
      .width('100%')
      .margin({ bottom: 10 })

      Row() {
        Text(this.DestinationLocationName)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
      .borderRadius(10)
      .border({ width: 1, color: $r('sys.color.comp_divider') })
      .onClick(() => {
        if (this.DestinationLocationName !== '获取中...' && this.DestinationLocationName !== '该签到无要求位置') {
          this.copyText(this.DestinationLocationName)
        }
      })

      if (this.queryParams?.['address']) {
        Column() {
          Text(`已选: ${this.queryParams['address']}`)
            .fontSize(13).fontColor($r('sys.color.ohos_id_color_text_primary')).margin({ top: 10 })
          Row({ space: 12 }) {
            Text(`经度 ${this.queryParams['longitude']?.toString().substring(0, 10)}`)
              .fontSize(11).fontColor($r('sys.color.ohos_id_color_text_tertiary'))
            Text(`纬度 ${this.queryParams['latitude']?.toString().substring(0, 10)}`)
              .fontSize(11).fontColor($r('sys.color.ohos_id_color_text_tertiary'))
          }.margin({ top: 4 })
        }.alignItems(HorizontalAlign.Start).width('100%')
      } else {
        Text('请点击下方按钮选择位置')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .margin({ top: 12, bottom: 6 })
          .width('100%')
      }

      Column() {
        FunctionalButton({
          params: {
            openType: functionalButtonComponentManager.OpenType.CHOOSE_LOCATION,
            label: '打开地图选点',
            styleOption: {
              bgColor: functionalButtonComponentManager.ColorType.DEFAULT,
              size: functionalButtonComponentManager.SizeType.DEFAULT,
              plain: false,
              disabled: false,
              loading: false,
              hoverClass: functionalButtonComponentManager.HoverClassType.HOVER_CLASS,
              hoverStartTime: 0,
              hoverStayTime: 0,
              styleConfig: new functionalButtonComponentManager.ButtonConfig().fontSize(15)
            },
          },
          controller: new functionalButtonComponentManager.FunctionalButtonController()
            .onChooseLocation((err, data) => {
              if (err) {
                hilog.error(0x0000, "Sign", "Location Error: %{public}s", err.message);
                return;
              }
              const LoginLocation = ChaoxingUtils.gcj02_to_bd09(data.latitude, data.longitude)
              this.queryParams['address'] = data.name as string;
              this.queryParams['longitude'] = LoginLocation.lon as number;
              this.queryParams['latitude'] = LoginLocation.lat as number;
            })
        })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(14)
    .width('100%')
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .borderRadius(14)
  }

  @Builder
  QRCodeCard() {
QRCodeLocation({queryParams: this.queryParams,ActivityId: this.activityInfo?.ActivityId.toString() || '',})
  }

  @Builder
  GestureSignCard() {
    Column() {
      if (this.hostUser) {
        GestureSignComponent({
          activityId: this.activityInfo?.ActivityId || '',
          courseId: this.activityInfo?.CourseId || '',
          classId: this.activityInfo?.ClassId || '',
          cookies: this.hostUser.cookies,
          uid: this.hostUser.uid,
          uname: this.hostUser.uname,
          fid: this.hostUser.fid
        })
      } else {
        Text('加载用户信息中...')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin(20)
      }
    }
    .width('100%')
  }

  @Builder
  PasswordSignCard() {
    Column() {
      if (this.hostUser) {
        PasswordSignComponent({
          activityId: this.activityInfo?.ActivityId || '',
          courseId: this.activityInfo?.CourseId || '',
          classId: this.activityInfo?.ClassId || '',
          cookies: this.hostUser.cookies,
          uid: this.hostUser.uid,
          uname: this.hostUser.uname,
          fid: this.hostUser.fid
        })
      } else {
        Text('加载用户信息中...')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin(20)
      }
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      if (this.activityInfo) {
        Column() {
          Column() {
            Text('签到详情')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .width('100%')
              .padding({ left: 16, top: 20, bottom: 16 })

            this.UserSelectionCard()

            if (this.activityInfo?.signType === SignType.NORMAL) {
              if (this.ifPhoto) {
                photoPicker({
                  signIdArray: this.signIdArray,
                  objectidArray: this.objectidArr,
                  otherUserDialogIsShow: this.otherUserDialogIsShow,
                  otherUser: this.otherUser
                })
                  .margin({ left: 16, right: 16 })
              } else {
                Column() {
                  Text('点击下方按钮直接签到')
                    .fontSize(16)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .padding({ top: 12, left: 16 })
              }
            } else if (this.activityInfo?.signType === SignType.LOCATION) {
              Column() { this.LocationCard() }
                .margin({ left: 16, right: 16 })
            } else if (this.activityInfo?.signType === SignType.GESTURE) {
              Column() { this.GestureSignCard() }
                .margin({ left: 16, right: 16 })
            } else if (this.activityInfo.signType === SignType.QRCODE) {
              Column() { this.QRCodeCard() }
                .margin({ left: 16, right: 16 })
            } else if (this.activityInfo.signType === SignType.PASSWORD) {
              Column() { this.PasswordSignCard() }
                .margin({ left: 16, right: 16 })
            } else {
              Text('未支持的签到类型')
                .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
                .padding(32)
            }
          }
          .width('100%')
          .layoutWeight(1)

          if (this.activityInfo?.signType !== SignType.GESTURE &&
            this.activityInfo?.signType !== SignType.PASSWORD) {
            Column() {
              Button('立即签到')
                .width('90%')
                .height(48)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_on_primary'))
                .backgroundColor($r('app.color.class_button'))
                .borderRadius(24)
                .enabled(this.canSign)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.signBtnLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                      this.signBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
                    })
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                      this.signBtnLight = hdsEffect.PointLightSourceType.NONE;
                    })
                  }
                })
                .onClick(() => {
                  this.showSignConfirmDialog()
                })
            }
            .width('100%')
            .padding({ top: 8, bottom: 16 })
            .backgroundColor($r('sys.color.ohos_id_color_background'))
          }
        }
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      } else {
        Column() {
          Text('参数加载失败').fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        }.justifyContent(FlexAlign.Center).height('100%')
      }
    }
    .hideTitleBar(false)
    .title('签到', {
      backgroundColor: $r('sys.color.ohos_id_color_background')
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathInfos = ctx.pathStack;
    })
    .onAppear(() => {
      this.initPageData(); // 统一数据初始化入口
    })
  }

  // 1. 逻辑方法：复制文本
  private copyText(text: string) {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    const systemPasteboard = pasteboard.getSystemPasteboard()
    systemPasteboard.setData(pasteboardData)
    promptAction.showToast({ message: '已复制到剪贴板', duration: 1500 })
  }

  // 2. 逻辑方法：初始化数据（替代原 onAppear 中的杂乱逻辑）
  private async initPageData() {
    const dbManager = DatabaseManager.getInstance()
    // 获取当前用户信息
    const currentUser = await dbManager.getUserByPosition(1, true) as UserDataAndId;

    if (!this.activityInfo || !currentUser) {
      return;
    }

    const cookies = currentUser.cookies;
    this.queryParams['activeId'] = this.activityInfo.ActivityId

    // 初始化主用户信息用于手势和密码签到
    try {
      const loginInfo = await loginFunction.getUserInfo(cookies);
      this.hostUser = {
        cookies: cookies,
        uid: loginInfo.uid,
        uname: loginInfo.uname,
        fid: parseInt(loginInfo.fid)
      };
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Failed to initialize host user: ${e.message}`);
    }

    // 检查是否需要拍照
    this.ifPhoto = await Sign.ifPhoto(cookies, this.activityInfo.ActivityId)

    // 如果是位置签到，获取位置信息
    if (this.activityInfo.signType === SignType.LOCATION) {
      try {
        const locName =
          (await Sign.GetLocationSignInfo(cookies, this.activityInfo.ActivityId))['locationText'] as string
        this.DestinationLocationName = locName ? locName : '该签到无要求位置'
      } catch (e) {
        this.DestinationLocationName = '位置信息获取失败'
      }
    }

    // 加载其他可签到用户
    this.loadOtherUsers(dbManager, this.activityInfo);
  }

  private async loadOtherUsers(dbManager: DatabaseManager, actInfo: ActivityInfo) {
    const newUserList: userMenu[] = []
    const autoSelectIds: number[] = [] // 自动选择未签到的用户

    // Get user count first
    const userCount = await dbManager.getTableCount('OtherUser')

    // Load main user and other users in parallel
    const loadMainUserPromise = this.loadSingleUser(dbManager, actInfo, 0, true);

    // Create promises for all other users
    const otherUserPromises: Promise<userMenu | null>[] = [];
    for (let i = 1; i <= userCount; i++) {
      otherUserPromises.push(this.loadSingleUser(dbManager, actInfo, i, false));
    }

    // Execute all promises in parallel using allSettled for better error handling
    const results = await Promise.allSettled([
      loadMainUserPromise,
      ...otherUserPromises
    ]);

    // Process main user result
    const mainUserSettled = results[0];
    if (mainUserSettled.status === 'fulfilled' && mainUserSettled.value) {
      const mainUserResult = mainUserSettled.value;
      newUserList.push(mainUserResult);
      if (mainUserResult.SignPermission === 1) {
        autoSelectIds.push(mainUserResult.id);
      }
    }

    // Process other user results
    for (let i = 1; i < results.length; i++) {
      const userSettled = results[i];
      if (userSettled.status === 'fulfilled' && userSettled.value) {
        const userResult = userSettled.value;
        newUserList.push(userResult);
        if (userResult.SignPermission === 1) {
          autoSelectIds.push(userResult.id);
        }
      }
    }

    this.otherUser = newUserList;
    // 默认选中所有未签到的用户
    this.signIdArray = autoSelectIds;
  }

  /**
   * Load a single user's information and sign permission
   * @param dbManager Database manager instance
   * @param actInfo Activity information
   * @param position User position (0 for main user)
   * @param isHost Whether this is the main user
   * @returns User menu object or null if loading fails
   */
  private async loadSingleUser(
    dbManager: DatabaseManager,
    actInfo: ActivityInfo,
    position: number,
    isHost: boolean
  ): Promise<userMenu | null> {
    try {
      const userInfo = isHost
        ? await dbManager.getUserByPosition(1, true)
        : await dbManager.getUserByPosition(position, false);

      if (!userInfo) {
        return null;
      }

      const loginInfo = await loginFunction.getUserInfo(userInfo.cookies);
      const permission = await Sign.PreSignIn(
        actInfo.ActivityId,
        actInfo.ClassId,
        actInfo.CourseId,
        loginInfo.uid,
        userInfo.cookies
      );

      return {
        uname: isHost ? loginInfo.uname + ' (主用户)' : loginInfo.uname,
        id: isHost ? 0 : position,
        SignPermission: permission
      };
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Failed to load user at position ${position}`, e);
      return null;
    }
  }

  // 3. 逻辑方法：显示签到确认对话框
  private showSignConfirmDialog() {
    if (this.signIdArray.length === 0) {
      AlertDialog.show({
        title: '提示',
        message: '请先选择至少一个用户',
        confirm: {
          value: '知道了',
          action: () => {
            this.otherUserDialogIsShow = true
          }
        }
      })
      return
    }

    const selectedUsers = this.otherUser.filter(u => this.signIdArray.includes(u.id));
    const userNames = selectedUsers.map(u => u.uname).join('、');

    AlertDialog.show({
      title: '确认签到',
      message: `即将为以下用户签到：\n${userNames}\n\n是否继续？`,
      primaryButton: {
        value: '修改用户',
        action: () => {
          this.otherUserDialogIsShow = true
        }
      },
      secondaryButton: {
        value: '确认签到',
        action: () => {
          this.handleSignAction()
        }
      }
    })
  }

  // 4. 逻辑方法：处理签到动作
  private async handleSignAction() {
    if (this.signIdArray.length !== this.objectidArr.length && this.ifPhoto) {
      promptAction.showToast({ message: '请等待图片上传完成' })
      return
    }

    if (this.signIdArray.length === 0) {
      promptAction.showToast({ message: '请选择至少一个用户' })
      return
    }

    this.canSign = false
    if (this.activityInfo?.signType === SignType.QRCODE) {
      const dbManager = DatabaseManager.getInstance()
      // 获取当前用户信息
      const currentUser = await dbManager.getUserByPosition(1, true) as UserDataAndId;

      if (!this.activityInfo || !currentUser) {
        this.canSign = true;
        return;
      }

      const cookies = currentUser.cookies;
      let loc = await Sign.GetLocationSignInfo(cookies, this.activityInfo.ActivityId)
      this.queryParams['address'] = loc['locationText'] as string;
      this.queryParams['longitude'] = loc['longitude'] as number;
      this.queryParams['latitude'] = loc['latitude'] as number;
      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: true,
        enableAlbum: true
      };
      try {
        // 可调用getHostContext接口获取当前页面关联的Context
        if (canIUse("SystemCapability.Multimedia.Scan.ScanBarcode")) {
          scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options)
            .then(async (result: scanBarcode.ScanResult) => {
              try {
                let url = result.originalValue
                let parse = UrlTools.parseUrlParams(url)

                if (!parse || !parse['enc']) {
                  promptAction.showToast({ message: '二维码格式错误' });
                  this.canSign = true;
                  return;
                }

                this.queryParams['enc'] = parse['enc']

                hilog.info(DOMAIN, TAG,
                  `Scan successful, enc: ${this.queryParams['enc']}`);

                // 扫码成功后，执行签到
                const hashTable = new Map<string, string[]>();

                // 遍历所有选中的用户进行签到
                for (let i = 0; i < this.signIdArray.length; i++) {
                  try {
                    const userId = this.signIdArray[i]
                    let userInfo: UserDataAndId
                    let isMainUser = false

                    if (userId === 0) {
                      // id 为 0 表示主用户
                      userInfo = await dbManager.getUserByPosition(1, true) as UserDataAndId
                      isMainUser = true
                    } else {
                      // 其他用户
                      userInfo = await dbManager.getUserByPosition(userId) as UserDataAndId
                      isMainUser = false
                    }

                    await this.performSingleSign(userInfo, this.objectidArr[i], hashTable, isMainUser)
                  } catch (e) {
                    hilog.error(DOMAIN, TAG, `User ${this.signIdArray[i]} sign error`, e)
                  }
                }

                this.showSignResult(hashTable);
              } catch (error) {
                const errorMsg = error instanceof Error ? error.message : String(error);
                hilog.error(DOMAIN, TAG, `Failed to process scan result: ${errorMsg}`);
                promptAction.showToast({ message: '处理扫码结果失败' });
              } finally {
                this.canSign = true;
              }
            })
            .catch((error: BusinessError) => {
              hilog.error(DOMAIN, TAG,
                `Failed to get ScanResult. Code:${error.code}, message: ${error.message}`);
              promptAction.showToast({ message: '扫码失败或已取消' });
              this.canSign = true;
            });
          // 扫码签到需要等待扫码结果，直接返回
          return;
        } else {
          promptAction.showToast({ message: '不支持扫码功能' });
          this.canSign = true;
          return;
        }
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        hilog.error(DOMAIN, TAG,
          `Failed to start the scanning service: ${errorMsg}`);
        promptAction.showToast({ message: '启动扫码失败' });
        this.canSign = true;
        return;
      }
    }

    // 非扫码签到的正常流程
    const hashTable = new Map<string, string[]>();
    const dbManager = DatabaseManager.getInstance()

    // 遍历所有选中的用户进行签到
    for (let i = 0; i < this.signIdArray.length; i++) {
      try {
        const userId = this.signIdArray[i]
        let userInfo: UserDataAndId
        let isMainUser = false

        if (userId === 0) {
          // id 为 0 表示主用户
          userInfo = await dbManager.getUserByPosition(1, true) as UserDataAndId
          isMainUser = true
        } else {
          // 其他用户
          userInfo = await dbManager.getUserByPosition(userId) as UserDataAndId
          isMainUser = false
        }

        await this.performSingleSign(userInfo, this.objectidArr[i], hashTable, isMainUser)
      } catch (e) {
        hilog.error(DOMAIN, TAG, `User ${this.signIdArray[i]} sign error`, e)
      }
    }

    this.showSignResult(hashTable);
    this.canSign = true
  }

  private async performSingleSign(userInfo: UserDataAndId, photoObjId: string | undefined, map: Map<string, string[]>,
    isMainUser: boolean) {
    const loginInfo = await loginFunction.getUserInfo(userInfo.cookies)

    this.queryParams['uid'] = userInfo.uid
    this.queryParams['name'] = loginInfo.uname
    this.queryParams['fid'] = loginInfo.fid
    if (this.ifPhoto && photoObjId) {
      this.queryParams['objectId'] = photoObjId
    }

    let result = await Sign.DoSignIn(userInfo.cookies, this.queryParams, isMainUser)

    if (typeof result === 'string' && (result.includes('<html') || result.includes('500 Internal Server Error'))) {
      result = '服务端错误 (500)';
    }

    if (map.has(result)) {
      map.get(result)!.push(loginInfo.uname);
    } else {
      map.set(result, [loginInfo.uname]);
    }
  }

  private showSignResult(hashTable: Map<string, string[]>) {
    let message = '';
    let isSuccess = false;

    hashTable.forEach((names, result) => {
      if (result === 'success') {
        isSuccess = true;
        message += `✅ 成功: ${names.join(', ')}\n`
      } else if (result === '您已签到过了') {
        message += `⚠️ 已签: ${names.join(', ')}\n`
      } else {
        message += `❌ ${result}: ${names.join(', ')}\n`
      }
    });

    if (message === '') {
      message = '未进行任何签到操作';
    }

    AlertDialog.show({
      title: '签到结果',
      message: message,
      confirm: {
        value: '确定',
        action: () => {
        }
      }
    })
  }
}
