import { hdsEffect } from '@kit.UIDesignKit';

/**
 * 带按压光效的按钮：统一收敛 visualEffect/onTouch 样板
 */
@Component
export struct LightButton {
  @Prop label: string = '';
  @Prop btnEnabled: boolean = true;
  @Prop bgColor: Resource = $r('sys.color.ohos_id_color_button_normal');
  @Prop btnFontSize: number = 14;
  @Prop btnHeight: number = 40;
  onButton: () => void = () => {};
  @State btnLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  build() {
    Button(this.label)
      .width('100%')
      .height(this.btnHeight)
      .fontSize(this.btnFontSize)
      .fontColor($r('app.color.text_on_primary'))
      .backgroundColor(this.bgColor)
      .enabled(this.btnEnabled)
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.btnLight,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
        })
        .buildEffect())
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
            this.btnLight = hdsEffect.PointLightSourceType.BRIGHT;
          })
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
            this.btnLight = hdsEffect.PointLightSourceType.NONE;
          })
        }
      })
      .onClick(() => {
        this.onButton()
      })
  }
}
