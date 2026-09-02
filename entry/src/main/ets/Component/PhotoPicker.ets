import { userMenu } from './SignerUsers';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager } from '../utils/DataBase';
import { loginFunction } from '../utils/Login';
import { Context } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { JSON } from '@kit.ArkTS';
import { uploadImageForObject } from '../utils/upload';

const TAG = 'PhotoPicker';
const DOMAIN = 0x0013;

/**
 * 拍照签到图片选择器：为每个勾选用户上传一张签到图片
 */
@Reusable
@Component
export struct photoPicker {
  @Link signIdArray: Array<number>
  @Link objectidArray: string[]
  @Link otherUserDialogIsShow: boolean
  @Prop otherUser: Array<userMenu>
  @State uploadStatus: string = '' // 上传状态反馈
  @State isUploading: boolean = false // 是否正在上传

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

  private refreshStatusText(finished: number, total: number) {
    const okCount = this.objectidArray.filter(id => id).length
    if (finished >= total && okCount === total) {
      this.uploadStatus = `所有图片上传完成 ✓ (${okCount}/${total})`
      promptAction.showToast({ message: '所有图片上传成功', duration: 2000 })
    } else {
      this.uploadStatus = `已上传 ${okCount}/${total}`
    }
  }

  // 逐个用户上传签到图片
  private async handlePhotoSelect() {
    this.objectidArray = new Array(this.signIdArray.length).fill('')
    this.uploadStatus = '正在准备上传...'
    this.isUploading = true
    const dbManager = DatabaseManager.getInstance()

    try {
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = this.signIdArray.length;
      const photoViewPicker = new picker.PhotoViewPicker();
      const context = this.getUIContext().getHostContext() as Context

      const res = await photoViewPicker.select(photoSelectOptions)
      const uriArr = res.photoUris
      if (!uriArr || uriArr.length === 0) {
        this.uploadStatus = ''
        this.isUploading = false
        return
      }
      const total = this.signIdArray.length
      this.uploadStatus = `正在上传图片 (0/${total})`
      promptAction.showToast({ message: '开始上传图片', duration: 1500 })

      for (let index = 0; index < total; index++) {
        const uri = uriArr[index % uriArr.length]
        try {
          const userInfo = await dbManager.getUserById(this.signIdArray[index])
          if (!userInfo) {
            throw new Error('用户不存在')
          }
          const puid = (await loginFunction.getUserInfo(userInfo.cookies)).puid
          this.objectidArray[index] = await uploadImageForObject(context, userInfo.cookies, puid, uri)
        } catch (error) {
          hilog.error(DOMAIN, TAG, `Photo upload failed for user ${this.signIdArray[index]}`,
            JSON.stringify(error))
          promptAction.showToast({ message: `图片 ${index + 1} 上传失败`, duration: 2000 })
        }
        this.refreshStatusText(index + 1, total)
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Photo selection failed', JSON.stringify(error))
      this.uploadStatus = '图片选择失败'
      promptAction.showToast({ message: '图片选择失败', duration: 2000 })
    } finally {
      this.isUploading = false
    }
  }
}
