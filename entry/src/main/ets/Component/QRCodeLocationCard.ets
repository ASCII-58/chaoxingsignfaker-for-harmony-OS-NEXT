import { FunctionalButton, functionalButtonComponentManager } from '@kit.ScenarioFusionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager } from '../utils/DataBase';
import { Sign } from '../utils/sign';
import { ChaoxingUtils } from '../utils/utils';

/** 二维码签到 location 参数结构（对齐上游 ChaoxingLocationSignEntity 序列化） */
export interface QRCodePosition {
  result: number
  latitude: number
  longitude: number
  address: string
}

/** 二维码签到的要求位置展示与地图选点卡片 */
@Reusable
@Component
export struct QRCodeLocation {
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
        const currentUser = await dbManager.getUserByPosition(1, true)
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
