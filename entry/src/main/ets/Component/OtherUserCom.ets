import { DatabaseManager, UserDataAndId } from '../utils/DataBase';
import { image } from '@kit.ImageKit';
import { loginFunction } from '../utils/Login';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ShareUtils from '../utils/shareUtils';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';

const TAG = 'OtherUserItem';
const DOMAIN = 0x0009;

@Reusable
@Component
export struct OtherUserItem {
  @Prop userData: UserDataAndId;
  @Prop index: number;
  @Link otherUserList: UserDataAndId[]
  @State userImage: image.PixelMap | null = null;
  @State userName: string = ''
  @State isLoaded: boolean = false;
  @State shareDialogVisible: boolean = false;
  @State iconPressed: string = '';
  @State shareLoading: boolean = false;
  private dbManger: DatabaseManager = DatabaseManager.getInstance()
  private uiContext: UIContext = this.getUIContext();
  private context: Context = this.uiContext.getHostContext() as Context;

  @Builder QRShareSheetContent() {
    Column() {
      Text('分享用户').fontSize(24).fontWeight(FontWeight.Bold)
        .width('100%').textAlign(TextAlign.Start).padding({ left: 20, bottom: 20 })
      Column() {
        Column() {
          QRCode(this.getShareUrl()).width(200).height(200)
        }
        .padding(20).backgroundColor($r('app.color.card_background'))
        .borderRadius(16).shadow({ radius: 12, color: '#00000010', offsetY: 4 })
        Text(this.userName).fontSize(20).fontWeight(FontWeight.Medium)
          .margin({ top: 20 }).fontColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .width('100%').alignItems(HorizontalAlign.Center).margin({ bottom: 40 })
      Button(this.shareLoading ? '准备中...' : '分享名片').width('90%').height(50)
        .fontColor($r('app.color.text_on_primary'))
        .backgroundColor($r('app.color.class_button')).borderRadius(25)
        .enabled(!this.shareLoading)
        .onClick(async () => {
          this.shareLoading = true
          const shareStr = this.getShareUrl()
          const shareUtils = new ShareUtils(this.context, shareStr)
          const ok = await shareUtils.prepare()
          if (ok) {
            this.doShare(shareUtils.FileUri, shareStr)
          } else {
            promptAction.showToast({ message: '生成分享图片失败' })
          }
          this.shareLoading = false
        })
    }
    .width('100%').height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  private getShareUrl(): string {
    return `http://cdn.aquamarine5.fun/?phone=${this.userData.phone}&pwd=${encodeURIComponent(this.userData.pwd)}&name=${encodeURIComponent(this.userName)}`
  }

  private async doShare(ShareUri: string, ShareStr: string) {
    const ctx = this.uiContext.getHostContext() as common.UIAbilityContext;
    let shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.IMAGE, uri: ShareUri,
      title: '分享二维码', description: '分享二维码', label: '二维码'
    });
    try {
      shareData.addRecord({
        utd: utd.UniformDataType.PLAIN_TEXT, content: ShareStr,
        title: '分享url', description: '可通过分享的url添加账号', label: 'url'
      });
    } catch (e) { console.error(`addRecord: ${e?.message}`); }
    let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
    controller.show(ctx, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    }).catch((error: BusinessError) => { console.error(`Share error: ${error?.message}`); });
  }

  private showDeleteDialog() {
    AlertDialog.show({
      title: '确认删除',
      message: `确认删除用户${this.userName}吗？\n`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.dbManger.deleteUser(this.userData.id).then(result => {
            if (result === 1) {
              this.otherUserList.splice(this.index, 1)
            }
          })
        }
      }
    })
  }

  build() {
    Row() {
      Image(this.userImage)
        .width(44).height(44)
        .borderRadius(10)
        .alt($r('app.media.foreground'))
      Column() {
        Text(this.userName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.userData.phone)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      Column() {
        Image($r('app.media.share'))
          .width(18).height(18)
          .fillColor($r('app.color.icon'))
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .scale({ x: this.iconPressed === 'share' ? 0.85 : 1, y: this.iconPressed === 'share' ? 0.85 : 1 })
      .animation({ duration: 150, curve: Curve.EaseInOut })
      .onTouch((event: TouchEvent) => {
        this.iconPressed = event.type === TouchType.Down ? 'share' : ''
      })
      .onClick(() => { this.shareDialogVisible = true })

      Column() {
        Image($r('app.media.ic_public_delete'))
          .width(18).height(18)
          .fillColor($r('app.color.unsignable'))
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .scale({ x: this.iconPressed === 'delete' ? 0.85 : 1, y: this.iconPressed === 'delete' ? 0.85 : 1 })
      .animation({ duration: 150, curve: Curve.EaseInOut })
      .onTouch((event: TouchEvent) => {
        this.iconPressed = event.type === TouchType.Down ? 'delete' : ''
      })
      .onClick(() => { this.showDeleteDialog() })
    }
    .width('100%').height(68)
    .backgroundColor($r('app.color.card_background'))
    .padding({ left: 16, right: 16 })
    .onAppear(async () => {
      if (!this.isLoaded) {
        let userInfo = await loginFunction.getUserInfo(this.userData.cookies)
        this.userName = userInfo.uname
        this.userImage = await loginFunction.GetPic(userInfo.pic)
        this.isLoaded = true
      }
    })
    .bindSheet($$this.shareDialogVisible, this.QRShareSheetContent, {
      height: 'auto', detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      backgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      onWillDismiss: () => { this.shareDialogVisible = false }
    })
  }
}
