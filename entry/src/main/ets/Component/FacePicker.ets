import { userMenu } from './SignerUsers';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import { ChaoxingUtils } from '../utils/utils';
import { Context } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { JSON } from '@kit.ArkTS';
import { FaceApi } from '../utils/faceApi';
import { uploadImageForObject } from '../utils/upload';

const TAG = 'FacePicker';
const DOMAIN = 0x0014;

/**
 * 人脸照片准备器（人脸识别签到，对齐上游人脸流程）
 * 支持自动获取账号默认人脸（下载-随机裁剪-重上传）或从相册选择
 */
@Component
export struct facePicker {
  @Link signIdArray: Array<number>
  @Link faceObjectIdArr: string[]
  @Prop otherUser: Array<userMenu>
  @Link otherUserDialogIsShow: boolean
  @State statusText: string = ''
  @State isPreparing: boolean = false

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

  private requireUsersSelected(): boolean {
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
      return false
    }
    return true
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
    const packedBuffer = await imagePacker.packToData(pixelMap, { format: 'image/jpeg', quality: 90 })
    const file = fs.openSync(dstPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    fs.writeSync(file.fd, packedBuffer)
    fs.closeSync(file)
    pixelMap.release()
    imagePacker.release()
    imageSource.release()
  }

  /** 自动获取每个用户的账号默认人脸（对齐上游 UseProfileImage 流程） */
  private async useProfileFaces() {
    if (!this.requireUsersSelected()) {
      return
    }
    this.isPreparing = true
    this.resetFaceIds()
    this.statusText = '正在获取默认人脸...'
    const context = this.getUIContext().getHostContext() as Context
    const dbManager = DatabaseManager.getInstance()
    try {
      for (let index = 0; index < this.signIdArray.length; index++) {
        try {
          const userInfo = await dbManager.getUserById(this.signIdArray[index])
          if (!userInfo) {
            throw new Error('用户不存在')
          }
          const profileObjectId = await FaceApi.GetProfileFaceObjectId(userInfo.cookies)
          const rawPath = context.cacheDir + '/' + ChaoxingUtils.generatePhotoName() + '_raw.jpg'
          await FaceApi.DownloadFaceImage(profileObjectId, rawPath)
          const processedPath = context.cacheDir + '/' + ChaoxingUtils.generatePhotoName() + '.jpg'
          await this.randomizeFaceImage(rawPath, processedPath)
          const puid = (await loginFunction.getUserInfo(userInfo.cookies)).puid
          this.faceObjectIdArr[index] = await uploadImageForObject(context, userInfo.cookies, puid, processedPath)
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
    if (!this.requireUsersSelected()) {
      return
    }
    this.isPreparing = true
    this.resetFaceIds()
    const context = this.getUIContext().getHostContext() as Context
    const dbManager = DatabaseManager.getInstance()
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
      const total = this.signIdArray.length
      this.statusText = `正在上传人脸照片 (0/${total})`
      for (let index = 0; index < total; index++) {
        try {
          const userInfo = await dbManager.getUserById(this.signIdArray[index])
          if (!userInfo) {
            throw new Error('用户不存在')
          }
          const puid = (await loginFunction.getUserInfo(userInfo.cookies)).puid
          const objectId = await uploadImageForObject(context, userInfo.cookies, puid,
            uriArr[index % uriArr.length])
          this.faceObjectIdArr[index] = objectId
        } catch (e) {
          hilog.error(DOMAIN, TAG, `Upload face photo failed: ${(e as Error).message}`)
          promptAction.showToast({ message: `用户 ${index + 1} 人脸照片上传失败`, duration: 2000 })
        }
        this.refreshStatusText(index + 1, total)
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
          .onClick(() => {
            this.useProfileFaces()
          })
        Button('从相册选择')
          .layoutWeight(1)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .enabled(!this.isPreparing)
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
