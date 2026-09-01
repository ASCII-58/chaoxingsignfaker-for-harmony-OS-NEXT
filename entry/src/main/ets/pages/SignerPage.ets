import { ActivityInfo, SignType } from './ActivityListPage';
import { CommonSignParams, parseSignResult, Sign, SignDetailResult, SignOutcome, UserQueryObject } from '../utils/sign';
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
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { GestureSignComponent } from '../Component/GestureSignComponent';
import { PasswordSignComponent } from '../Component/PasswordSignComponent';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import UrlTools from '../utils/urlTools';
import { hdsEffect } from '@kit.UIDesignKit';
import { CaptchaComponent, CaptchaUserParam } from '../Component/Captcha';

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

        Text(this.user.SignPermission === 1 ? '可签到' : this.user.SignPermission === 0 ? '已签到' :
        this.user.SignPermission === 2 ? '已截止' : '无权限')
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
    this.objectidArray = new Array(this.signIdArray.length).fill('')
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
            info.cookies = ((await dbManager.getUserByPosition(userId, false)) as UserDataAndId).cookies
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
          this.onUploadFinished()
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
        this.onUploadFinished()
      })

      task.on('complete', () => {
        this.onUploadFinished()
      })

      task.on('headerReceive', (value) => {
        if (value && value['body']) {
          try {
            const bodyObj = JSON.parse(value['body']) as object
            this.objectidArray[signIndex] = bodyObj['objectId'] as string
            console.info(`Photo ${signIndex + 1} uploaded successfully`)
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'Failed to parse upload response', e)
          }
        }
      })
    } catch (e) {
      hilog.error(DOMAIN, TAG, "Upload task creation failed", e)
      promptAction.showToast({ message: `图片 ${signIndex + 1} 上传失败`, duration: 2000 })
      this.onUploadFinished()
    }
  }

  private onUploadFinished() {
    this.uploadCompletedCount++
    if (this.uploadCompletedCount >= this.uploadTotalCount) {
      this.isUploading = false
      const uploadedCount = this.objectidArray.filter(id => id).length
      if (uploadedCount === this.uploadTotalCount) {
        this.uploadStatus = '所有图片上传完成 ✓'
        promptAction.showToast({ message: '所有图片上传成功', duration: 2000 })
      } else if (uploadedCount === 0) {
        this.uploadStatus = '所有图片上传失败'
      } else {
        this.uploadStatus = `已上传 ${uploadedCount}/${this.uploadTotalCount}`
      }
    } else {
      const uploadedCount = this.objectidArray.filter(id => id).length
      this.uploadStatus = `已上传 ${uploadedCount}/${this.uploadTotalCount}`
    }
  }
}

/** 二维码签到 location 参数结构（对齐上游 ChaoxingLocationSignEntity 序列化） */
export interface QRCodePosition {
  result: number
  latitude: number
  longitude: number
  address: string
}

@Reusable
@Component
struct QRCodeLocation {
  @Prop ActivityId: string;
  onPositionChange?: (position: QRCodePosition) => void
  @State DestinationLocationName: string = '获取中...'
  @State Position: QRCodePosition | null = null

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
          ChaoxingUtils.copyText(this.DestinationLocationName)
        }
      })

      // 已选坐标展示
      if (this.Position) {
        Column() {
          Text(`已选位置: ${this.Position.address}`)
            .fontSize(14).fontColor($r('sys.color.ohos_id_color_text_primary')).margin({ top: 8 })
          Text(`经度: ${this.Position.longitude}`)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
          Text(`纬度: ${this.Position.latitude}`)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        }.alignItems(HorizontalAlign.Start).width('100%').margin({ top: 8 })
      } else {
        Text('该签到可不选位置，选点后将随签到提交')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
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
              const newPosition: QRCodePosition = {
                result: 1,
                latitude: LoginLocation.lat,
                longitude: LoginLocation.lon,
                address: data.name as string
              }
              this.Position = newPosition
              this.onPositionChange?.(newPosition)
            })
        }).enabled(this.DestinationLocationName !== '获取中...' && this.DestinationLocationName !== '该签到无要求位置')
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(16)
    .width('100%')
    .onAppear(async () => {
      try {
        const dbManager = DatabaseManager.getInstance()
        const currentUser = await dbManager.getUserByPosition(1, true) as UserDataAndId
        if (currentUser && this.ActivityId) {
          const locInfo = await Sign.GetLocationSignInfo(currentUser.cookies, this.ActivityId)
          const locName = locInfo['locationText'] as string
          this.DestinationLocationName = locName ? locName : '该签到无要求位置'
        }
      } catch (e) {
        this.DestinationLocationName = '位置信息获取失败'
      }
    })
  }
}

// ---------------------------------------------------------------
// 组件 4: 人脸照片准备器（人脸识别签到，对齐上游人脸流程）
// 支持自动获取账号默认人脸（下载-随机裁剪-重上传）或从相册选择
// ---------------------------------------------------------------
@Component
struct facePicker {
  @Link signIdArray: Array<number>
  @Link faceObjectIdArr: string[]
  @Prop otherUser: Array<userMenu>
  @Link otherUserDialogIsShow: boolean
  @State statusText: string = ''
  @State isPreparing: boolean = false
  @State profileBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State albumBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  private resetFaceIds() {
    this.faceObjectIdArr = new Array(this.signIdArray.length).fill('')
  }

  private refreshStatusText(finished: number, total: number) {
    const okCount = this.faceObjectIdArr.filter(id => id).length
    if (finished >= total && okCount === total) {
      this.statusText = `全部人脸照片准备完成 ✓ (${okCount}/${total})`
    } else {
      this.statusText = `已获取 ${okCount}/${total} 张人脸照片`
    }
  }

  private async loadUserById(userId: number): Promise<UserDataAndId> {
    const dbManager = DatabaseManager.getInstance()
    if (userId === 0) {
      return await dbManager.getUserByPosition(1, true) as UserDataAndId
    }
    return await dbManager.getUserByPosition(userId, false) as UserDataAndId
  }

  /**
   * 随机裁剪人脸图片（对齐上游 randomizeStylizeFaceImage 的随机裁剪，规避风控）
   */
  private async randomizeFaceImage(srcPath: string, dstPath: string): Promise<void> {
    const imageSource = image.createImageSource(srcPath)
    const pixelMap = await imageSource.createPixelMap()
    const imageInfo = await pixelMap.getImageInfo()
    const scale = 0.9 + Math.random() * 0.09
    const cropWidth = Math.floor(imageInfo.size.width * scale)
    const cropHeight = Math.floor(imageInfo.size.height * scale)
    const cropX = Math.floor(Math.random() * (imageInfo.size.width - cropWidth))
    const cropY = Math.floor(Math.random() * (imageInfo.size.height - cropHeight))
    await pixelMap.crop({ x: cropX, y: cropY, size: { width: cropWidth, height: cropHeight } })
    const imagePacker = image.createImagePacker()
    const packedBuffer = await imagePacker.packToString(pixelMap, { format: 'image/jpeg', quality: 90 })
    const file = fs.openSync(dstPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNCATE)
    fs.writeSync(file.fd, packedBuffer)
    fs.closeSync(file)
    pixelMap.release()
    imagePacker.release()
    imageSource.release()
  }

  private async uploadFaceFile(context: Context, cookies: string, puid: string, srcUri: string): Promise<string> {
    const token = await Sign.GetToken(cookies)
    const fileName = ChaoxingUtils.generatePhotoName() + '.jpg'
    const copyFilePath = context.cacheDir + '/' + fileName
    fs.copyFileSync(srcUri, copyFilePath)
    const uploadConfig: request.UploadConfig = {
      url: `https://pan-yz.chaoxing.com/upload?_from=mobilelearn&_token=${token}`,
      method: 'POST',
      header: { "Content-Type": "multipart/form-data" },
      files: [{
        filename: fileName,
        type: 'jpg',
        name: 'file',
        uri: `internal://cache/${fileName}`
      }],
      data: [{ name: 'puid', value: puid }]
    }
    const task = await request.uploadFile(context, uploadConfig)
    return await new Promise<string>((resolve, reject) => {
      let settled = false
      task.on('headerReceive', (value) => {
        if (settled || !(value && value['body'])) {
          return
        }
        try {
          const bodyObj = JSON.parse(value['body']) as object
          const objectId = bodyObj['objectId'] as string
          if (objectId) {
            settled = true
            resolve(objectId)
          }
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'Failed to parse upload response', e)
        }
      })
      task.on('fail', () => {
        if (!settled) {
          settled = true
          reject(new Error('人脸照片上传失败'))
        }
      })
      setTimeout(() => {
        if (!settled) {
          settled = true
          reject(new Error('人脸照片上传超时'))
        }
      }, 30000)
    })
  }

  /** 自动获取每个用户的账号默认人脸（对齐上游 UseProfileImage 流程） */
  private async useProfileFaces() {
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
    this.isPreparing = true
    this.resetFaceIds()
    this.statusText = '正在获取默认人脸...'
    const context = this.getUIContext().getHostContext() as Context
    try {
      for (let index = 0; index < this.signIdArray.length; index++) {
        try {
          const userInfo = await this.loadUserById(this.signIdArray[index])
          const profileObjectId = await Sign.GetProfileFaceObjectId(userInfo.cookies)
          const rawPath = context.cacheDir + '/' + ChaoxingUtils.generatePhotoName() + '_raw.jpg'
          await Sign.DownloadFaceImage(profileObjectId, rawPath)
          const processedPath = context.cacheDir + '/' + ChaoxingUtils.generatePhotoName() + '.jpg'
          await this.randomizeFaceImage(rawPath, processedPath)
          const loginInfo = await loginFunction.getUserInfo(userInfo.cookies)
          const puid = loginInfo.puid ? loginInfo.puid : userInfo.uid.toString()
          this.faceObjectIdArr[index] = await this.uploadFaceFile(context, userInfo.cookies, puid, processedPath)
        } catch (e) {
          hilog.error(DOMAIN, TAG, `Prepare profile face failed: ${(e as Error).message}`)
          promptAction.showToast({ message: `用户 ${index + 1} 默认人脸获取失败`, duration: 2000 })
        }
        this.refreshStatusText(index + 1, this.signIdArray.length)
      }
    } finally {
      this.isPreparing = false
    }
  }

  /** 从相册为人脸签到选择照片 */
  private async pickFaces() {
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
    this.isPreparing = true
    this.resetFaceIds()
    const context = this.getUIContext().getHostContext() as Context
    try {
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = this.signIdArray.length;
      const photoViewPicker = new picker.PhotoViewPicker();
      const res = await photoViewPicker.select(photoSelectOptions)
      const uriArr = res.photoUris
      if (!uriArr || uriArr.length === 0) {
        this.statusText = ''
        return
      }
      this.statusText = `正在上传人脸照片 (0/${this.signIdArray.length})`
      for (let index = 0; index < this.signIdArray.length; index++) {
        try {
          const userInfo = await this.loadUserById(this.signIdArray[index])
          const loginInfo = await loginFunction.getUserInfo(userInfo.cookies)
          const puid = loginInfo.puid ? loginInfo.puid : userInfo.uid.toString()
          const objectId =
            await this.uploadFaceFile(context, userInfo.cookies, puid, uriArr[index % uriArr.length])
          this.faceObjectIdArr[index] = objectId
        } catch (e) {
          hilog.error(DOMAIN, TAG, `Upload face photo failed: ${(e as Error).message}`)
          promptAction.showToast({ message: `用户 ${index + 1} 人脸照片上传失败`, duration: 2000 })
        }
        this.refreshStatusText(index + 1, this.signIdArray.length)
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Face photo selection failed', JSON.stringify(error))
      this.statusText = '人脸照片选择失败'
    } finally {
      this.isPreparing = false
    }
  }

  build() {
    Column() {
      // 状态指示点
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.signIdArray, (signId: number, index: number) => {
          Circle({ width: 8, height: 8 })
            .fill(this.faceObjectIdArr[index] ? $r('sys.color.ohos_id_color_connected') :
              $r('sys.color.ohos_id_color_warning'))
            .margin(4)
        })
      }
      .padding(10)
      .width('100%')

      if (this.statusText) {
        Text(this.statusText)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 8, bottom: 8 })
      }

      Row({ space: 12 }) {
        Button('自动获取默认人脸')
          .layoutWeight(1)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .enabled(!this.isPreparing)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.profileBtnLight,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                this.profileBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
              })
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                this.profileBtnLight = hdsEffect.PointLightSourceType.NONE;
              })
            }
          })
          .onClick(() => {
            this.useProfileFaces()
          })
        Button('从相册选择')
          .layoutWeight(1)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .enabled(!this.isPreparing)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.albumBtnLight,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                this.albumBtnLight = hdsEffect.PointLightSourceType.BRIGHT;
              })
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
                this.albumBtnLight = hdsEffect.PointLightSourceType.NONE;
              })
            }
          })
          .onClick(() => {
            this.pickFaces()
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .borderRadius(16)
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
  @State commonQueryParams: CommonSignParams = {
    activeId: '',
    latitude: '',
    longitude: '',
    address: '',
    enc: ''
  }
  @State otherUser: Array<userMenu> = []
  @State signIdArray: Array<number> = []
  @State ifPhoto: boolean = false
  @State otherUserDialogIsShow: boolean = false
  @State objectidArr: string[] = []
  @State DestinationLocationName: string = '获取中...' // 初始状态
  @State hostUser: HostUserInfo | null = null
  @State signBtnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  // 活动详情（验证码/人脸要求等）
  @State signDetail: SignDetailResult | null = null
  @State faceRequired: boolean = false
  @State faceObjectIdArr: string[] = []
  // 二维码签到用户自选位置
  @State qrPosition: QRCodePosition | null = null
  // 验证码弹窗状态
  @State captchaSheetShow: boolean = false
  @State captchaUser: CaptchaUserParam | null = null
  private captchaResolver: ((validate: string | null) => void) | null = null
  // 手势/签到码组件校验通过后回传的码
  @State pendingSignCode: string = ''

  // 4. UI Builders
  @Builder
  otherUserMenu() {
    List() {
      ForEach(this.otherUser, (user: userMenu) => {
        ListItem() {
          userItem({ user, signIdArray: this.signIdArray })
        }
        .onClick(() => {
          if (user.SignPermission === -1) {
            promptAction.showToast({ message: '该用户不在班级', duration: 1500 })
            return
          }
          if (user.SignPermission === 2) {
            promptAction.showToast({ message: '该签到对此用户已截止', duration: 1500 })
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
          ForEach(this.otherUser.filter(u => this.signIdArray.includes(u.id)), (user: userMenu) => {
            Row() {
              Text(user.uname)
                .fontSize(13)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
              Image($r('sys.media.ohos_ic_public_close'))
                .width(14).height(14)
                .fillColor($r('sys.color.ohos_id_color_text_tertiary'))
                .margin({ left: 4 })
            }
            .padding({
              left: 10,
              right: 10,
              top: 5,
              bottom: 5
            })
            .backgroundColor($r('sys.color.ohos_id_color_emphasize', 0.1))
            .borderRadius(14)
            .margin({ right: 8, bottom: 6 })
            .onClick(() => {
              this.signIdArray = this.signIdArray.filter(num => num !== user.id)
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
          ChaoxingUtils.copyText(this.DestinationLocationName)
        }
      })

      if (this.commonQueryParams.address) {
        Column() {
          Text(`已选: ${this.commonQueryParams.address}`)
            .fontSize(13).fontColor($r('sys.color.ohos_id_color_text_primary')).margin({ top: 10 })
          Row({ space: 12 }) {
            Text(`经度 ${this.commonQueryParams.longitude.substring(0, 10)}`)
              .fontSize(11).fontColor($r('sys.color.ohos_id_color_text_tertiary'))
            Text(`纬度 ${this.commonQueryParams.latitude.substring(0, 10)}`)
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
              this.commonQueryParams.address = data.name as string;
              this.commonQueryParams.longitude = LoginLocation.lon.toString();
              this.commonQueryParams.latitude = LoginLocation.lat.toString();
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
    QRCodeLocation({
      ActivityId: this.activityInfo?.ActivityId.toString() || '',
      onPositionChange: (position: QRCodePosition) => {
        this.qrPosition = position
      }
    })
  }

  @Builder
  GestureSignCard() {
    Column() {
      if (this.hostUser) {
        GestureSignComponent({
          activityId: this.activityInfo?.ActivityId || '',
          hostCookies: this.hostUser.cookies,
          onSignCode: (code: string) => {
            this.pendingSignCode = code
          }
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
          hostCookies: this.hostUser.cookies,
          codeLength: this.signDetail?.numberCount || 0,
          onSignCode: (code: string) => {
            this.pendingSignCode = code
          }
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
  CaptchaSheetBuilder() {
    if (this.captchaUser) {
      CaptchaComponent({
        captchaUser: this.captchaUser,
        onValidated: (validate: string) => {
          this.captchaSheetShow = false
          this.captchaResolver?.(validate)
          this.captchaResolver = null
        },
        onSkip: () => {
          this.captchaSheetShow = false
          this.captchaResolver?.(null)
          this.captchaResolver = null
        }
      })
    }
  }

  build() {
    NavDestination() {
      if (this.activityInfo) {
        Column() {
          Column() {
            Row() {
              Text('签到详情')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                //
                .padding({ left: 16, top: 20, bottom: 16 })
              Blank()
            }.width('100%')

            this.UserSelectionCard()

            if (this.faceRequired && (this.activityInfo?.signType === SignType.NORMAL ||
              this.activityInfo?.signType === SignType.LOCATION ||
              this.activityInfo?.signType === SignType.QRCODE)) {
              Column() {
                facePicker({
                  signIdArray: this.signIdArray,
                  faceObjectIdArr: this.faceObjectIdArr,
                  otherUserDialogIsShow: this.otherUserDialogIsShow,
                  otherUser: this.otherUser
                })
              }
              .margin({ left: 16, right: 16, bottom: 12 })
            }

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
              Column() {
                this.LocationCard()
              }
              .margin({ left: 16, right: 16 })
            } else if (this.activityInfo?.signType === SignType.GESTURE) {
              Column() {
                this.GestureSignCard()
              }
              .margin({ left: 16, right: 16 })
            } else if (this.activityInfo.signType === SignType.QRCODE) {
              Column() {
                this.QRCodeCard()
              }
              .margin({ left: 16, right: 16 })
            } else if (this.activityInfo.signType === SignType.PASSWORD) {
              Column() {
                this.PasswordSignCard()
              }
              .margin({ left: 16, right: 16 })
            } else {
              Text('未支持的签到类型')
                .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
                .padding(32)
            }
          }
          .width('100%')
          .layoutWeight(1)

          Column() {
            if (this.prepareHint() !== '') {
              Text(this.prepareHint())
                .fontSize(13)
                .fontColor($r('app.color.unsignable'))
                .margin({ bottom: 8 })
            }
            Row({ space: 12 }) {
              if (this.signOutAvailable()) {
                Button('签退')
                  .layoutWeight(1)
                  .height(48)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_on_primary'))
                  .backgroundColor($r('app.color.unsignable'))
                  .borderRadius(24)
                  .enabled(this.canSign)
                  .onClick(() => {
                    this.executeSignOutFlow()
                  })
              }
              Button('立即签到')
                .layoutWeight(1)
                .height(48)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_on_primary'))
                .backgroundColor($r('app.color.class_button'))
                .borderRadius(24)
                .enabled(this.canSign && this.prepareHint() === '')
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
            .width('90%')
          }
          .width('100%')
          .padding({ top: 8, bottom: 16 })
          .backgroundColor($r('sys.color.ohos_id_color_background'))
        }
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
        .bindSheet($$this.captchaSheetShow, this.CaptchaSheetBuilder, {
          title: { title: '签到验证码' },
          backgroundColor: $r('sys.color.ohos_id_color_dialog_bg'),
          detents: [SheetSize.MEDIUM, SheetSize.LARGE]
        })
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
    .onAppear(() => {
      this.initPageData(); // 统一数据初始化入口
    })
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
    this.commonQueryParams.activeId = this.activityInfo.ActivityId

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

    // 获取活动完整详情（验证码/人脸/拍照要求）
    try {
      this.signDetail = await Sign.GetActiveDetail(cookies, this.activityInfo.ActivityId)
      this.faceRequired = this.signDetail.openCheckFaceFlag === 1
      this.ifPhoto = this.signDetail.ifphoto
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Failed to load active detail: ${e.message}`);
      this.ifPhoto = false
    }

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
        loginInfo.puid ? parseInt(loginInfo.puid) : loginInfo.uid,
        userInfo.cookies,
        actInfo.ext
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

  private async loadUserById(userId: number): Promise<UserDataAndId> {
    const dbManager = DatabaseManager.getInstance()
    if (userId === 0) {
      return await dbManager.getUserByPosition(1, true) as UserDataAndId
    }
    return await dbManager.getUserByPosition(userId, false) as UserDataAndId
  }

  /**
   * 弹出滑块验证码并等待用户完成校验
   * @returns validate 值；用户跳过返回 null
   */
  private requestCaptcha(userCookies: string, uname: string, uid: string): Promise<string | null> {
    this.captchaUser = {
      cookies: userCookies,
      uname: uname,
      refererParams: {
        courseId: this.activityInfo?.CourseId || '',
        classId: this.activityInfo?.ClassId || '',
        activePrimaryId: this.activityInfo?.ActivityId || '',
        uid: uid
      }
    }
    this.captchaSheetShow = true
    return new Promise<string | null>((resolve) => {
      this.captchaResolver = resolve
    })
  }

  /**
   * 就绪检查：返回就绪提示文案，空串表示可以签到
   */
  private prepareHint(): string {
    if (this.signIdArray.length === 0) {
      return '请先选择签到用户'
    }
    const selected = this.signIdArray.length
    if (this.ifPhoto) {
      const uploaded = this.objectidArr.filter(id => id).length
      if (uploaded < selected) {
        return `等待签到图片上传 (${uploaded}/${selected})`
      }
    }
    if (this.faceRequired) {
      const faces = this.faceObjectIdArr.filter(id => id).length
      if (faces < selected) {
        return `该签到需要人脸识别，请先为所选用户准备人脸照片 (${faces}/${selected})`
      }
    }
    if (this.activityInfo?.signType === SignType.LOCATION && !this.commonQueryParams.latitude) {
      return '请先选择签到位置'
    }
    if (this.activityInfo?.signType === SignType.GESTURE && !this.pendingSignCode) {
      return '请先绘制并校验手势'
    }
    if (this.activityInfo?.signType === SignType.PASSWORD && !this.pendingSignCode) {
      return '请先输入并校验签到码'
    }
    return ''
  }

  private signOutAvailable(): boolean {
    return this.signDetail !== null && this.signDetail.signOutId > 0 &&
      this.signDetail.signOutPublishTimeStamp > 0
  }

  /**
   * 构造本轮签到的基础公共参数（签到过程中不可变）
   */
  private buildBaseParams(signCode: string, enc: string): CommonSignParams {
    return {
      activeId: this.activityInfo?.ActivityId || '',
      latitude: this.commonQueryParams.latitude,
      longitude: this.commonQueryParams.longitude,
      address: this.commonQueryParams.address,
      enc: enc,
      signCode: signCode
    }
  }

  // 4. 逻辑方法：处理签到动作
  private async handleSignAction() {
    const hint = this.prepareHint()
    if (hint) {
      promptAction.showToast({ message: hint })
      return
    }

    this.canSign = false
    if (this.activityInfo?.signType === SignType.QRCODE) {
      // 二维码签到：对齐上游 lat/lng 固定 -1，自选位置以 location JSON 提交
      this.commonQueryParams.latitude = '-1'
      this.commonQueryParams.longitude = '-1'
      this.commonQueryParams.address = ''
      if (this.qrPosition) {
        const position = this.qrPosition
        this.commonQueryParams.location =
          `{"result":1,"latitude":"${position.latitude.toFixed(6)}","longitude":"${position.longitude.toFixed(6)}","address":"${position.address}","mockData":"{\\"strategy\\":0,\\"probability\\":-1}"}`
      } else {
        this.commonQueryParams.location = ''
      }

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

                const enc = parse['enc']
                hilog.info(DOMAIN, TAG, `Scan successful, enc: ${enc}`);

                // 扫码成功后，执行统一签到流程
                await this.executeSignFlow('', enc)
              } catch (error) {
                const errorMsg = error instanceof Error ? error.message : String(error);
                hilog.error(DOMAIN, TAG, `Failed to process scan result: ${errorMsg}`);
                promptAction.showToast({ message: '处理扫码结果失败' });
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

    // 非扫码签到：统一签到流程
    await this.executeSignFlow(this.pendingSignCode, this.commonQueryParams.enc)
  }

  /**
   * 统一签到流程：所有签到类型共用同一条执行路径
   * 逐个用户签到（间隔 200ms，对齐上游），支持验证码与人脸，二维码过期中断剩余用户
   */
  private async executeSignFlow(signCode: string, enc: string): Promise<void> {
    const hashTable = new Map<string, string[]>()
    const baseParams = this.buildBaseParams(signCode, enc)
    // 快照勾选列表，避免签到过程中修改勾选导致错位
    const targetIds = this.signIdArray.slice()

    for (let i = 0; i < targetIds.length; i++) {
      try {
        const userInfo = await this.loadUserById(targetIds[i])
        const outcome =
          await this.signSingleUser(userInfo, this.objectidArr[i] || '', this.faceObjectIdArr[i] || '',
            baseParams, hashTable)
        if (outcome.kind === 'qrcodeExpired') {
          promptAction.showToast({ message: '签到二维码已过期，请重新扫码', duration: 2000 })
          break
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `User ${targetIds[i]} sign error`, e)
      }
      // 对齐上游代签用户间隔
      if (i < targetIds.length - 1) {
        await new Promise<void>((resolve) => setTimeout(resolve, 200))
      }
    }

    this.showSignResult(hashTable);
    await this.refreshUserPermissions()
    this.canSign = true
  }

  /**
   * 为单个用户执行签到（每个用户使用独立的参数对象，避免共享可变状态）
   */
  private async signSingleUser(userInfo: UserDataAndId, photoObjId: string, faceObjId: string,
    baseParams: CommonSignParams, map: Map<string, string[]>): Promise<SignOutcome> {
    const loginInfo = await loginFunction.getUserInfo(userInfo.cookies)
    const uidForSign = loginInfo.puid ? loginInfo.puid : userInfo.uid.toString()

    const params: CommonSignParams = {
      activeId: baseParams.activeId,
      latitude: baseParams.latitude,
      longitude: baseParams.longitude,
      address: baseParams.address,
      enc: baseParams.enc,
      signCode: baseParams.signCode
    }
    if (this.ifPhoto && photoObjId) {
      params.objectId = photoObjId
    }
    // 人脸识别参数（对齐上游 addFaceRecognitionParameter）
    if (faceObjId) {
      params.courseId = this.activityInfo?.CourseId || ''
      params.currentFaceId = faceObjId
      try {
        params.faceEnc = await Sign.CheckFaceResultAndGetEnc(userInfo.cookies,
          this.activityInfo?.ActivityId || '', faceObjId, loginInfo.clientId)
      } catch (e) {
        hilog.error(DOMAIN, TAG, `Get faceEnc failed: ${(e as Error).message}`)
        params.courseId = ''
        params.currentFaceId = ''
        params.faceEnc = ''
      }
    }

    const userQueryParams: UserQueryObject = {
      uid: uidForSign,
      name: loginInfo.uname,
      fid: loginInfo.fid.toString()
    }

    let raw = await Sign.DoSignInV2(userInfo.cookies, params, userQueryParams)
    let outcome = parseSignResult(raw)

    // 需要验证码：弹窗完成后带 validate 重新签到（对齐上游 signWithCaptcha）
    if (outcome.needCaptcha) {
      const validate = await this.requestCaptcha(userInfo.cookies, loginInfo.uname, uidForSign)
      if (validate) {
        raw = await Sign.DoSignInV2(userInfo.cookies, params, userQueryParams, validate)
        outcome = parseSignResult(raw)
      } else {
        outcome = { kind: 'error', message: '验证码校验被跳过', needCaptcha: false }
      }
    }

    this.recordOutcome(map, outcome, loginInfo.uname)
    return outcome
  }

  /**
   * 页面级签退：为所有勾选用户逐个签退
   */
  private async executeSignOutFlow() {
    if (this.signIdArray.length === 0) {
      promptAction.showToast({ message: '请选择至少一个用户' })
      return
    }

    this.canSign = false
    const hashTable = new Map<string, string[]>()
    const targetIds = this.signIdArray.slice()
    for (let i = 0; i < targetIds.length; i++) {
      const label = targetIds[i] === 0 ? '主用户' : `用户${targetIds[i]}`
      try {
        const userInfo = await this.loadUserById(targetIds[i])
        const info = await Sign.GetSignInfo(userInfo.cookies, this.activityInfo?.ActivityId || '')
        if (info.signOutId <= 0) {
          this.recordOutcome(hashTable, { kind: 'none', message: '该用户无可用签退', needCaptcha: false }, label)
        } else {
          await Sign.DoSignOut(userInfo.cookies, info.signInId, info.signOutId)
          this.recordOutcome(hashTable, { kind: 'success', message: '签退成功', needCaptcha: false }, label)
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `User ${targetIds[i]} sign out error`, e)
        this.recordOutcome(hashTable,
          { kind: 'error', message: `签退失败: ${(e as Error).message}`, needCaptcha: false }, label)
      }
      if (i < targetIds.length - 1) {
        await new Promise<void>((resolve) => setTimeout(resolve, 200))
      }
    }

    this.showSignResult(hashTable)
    await this.refreshUserPermissions()
    this.canSign = true
  }

  /**
   * 按用户名聚合同类签到结果（key = kind|message）
   */
  private recordOutcome(map: Map<string, string[]>, outcome: SignOutcome, uname: string) {
    const key = `${outcome.kind}|${outcome.message}`
    if (map.has(key)) {
      map.get(key)!.push(uname)
    } else {
      map.set(key, [uname])
    }
  }

  /**
   * 签到/签退结束后刷新用户权限状态（已签到/可签到/无权限）
   */
  private async refreshUserPermissions() {
    if (!this.activityInfo) {
      return
    }
    try {
      await this.loadOtherUsers(DatabaseManager.getInstance(), this.activityInfo)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Refresh user permissions failed: ${(e as Error).message}`)
    }
  }

  private showSignResult(hashTable: Map<string, string[]>) {
    let message = '';
    hashTable.forEach((names, key) => {
      const separator = key.indexOf('|')
      const kind = separator >= 0 ? key.substring(0, separator) : 'error'
      const result = separator >= 0 ? key.substring(separator + 1) : key
      const displayNames = names.filter(name => name).join(', ')
      if (kind === 'success') {
        message += displayNames ? `✅ ${result}: ${displayNames}\n` : `✅ ${result}\n`
      } else if (kind === 'already') {
        message += displayNames ? `⚠️ ${result}: ${displayNames}\n` : `⚠️ ${result}\n`
      } else {
        message += displayNames ? `❌ ${result}: ${displayNames}\n` : `❌ ${result}\n`
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
