import { CaptchaPhotosParam, CaptchaPhotosResult } from '../utils/sign'
import {DatabaseManager} from '../utils/DataBase'
@Component
export struct CaptchaComponent {
  returnFunction?: (value: string[]) => void
  @Prop signIdArray: Array<number>
  @State CaptchaIndex:number=0
  @State xTranslate:number = 0
  @State info: CaptchaPhotosResult = {
    token: '',
    imageVerificationVo: {
      shadeImage: '',
      cutoutImage: ''
    }
  }
  private captchaPhotosParam: CaptchaPhotosParam | undefined
  private result:string[]=[]

  build() {
    Column() {
      Stack() {
        Image($r('app.media.testb')).width('100%').height('100%')
        Image($r('app.media.testp')).position({x:`${this.xTranslate/280*100}%` as Length}).height('100%').aspectRatio(0.35)
      }
      .width('100%')
      .aspectRatio(2)
      .onAppear(()=>{
        // if (this.signIdArray.length>0) {
        //   const DBM = DatabaseManager.getInstance()
        //
        //   this.signIdArray[this.CaptchaIndex]
        // }
      })
      Slider({value:$$this.xTranslate,max:280})
    }
    .width('100%')
    .padding({ left: 32, right: 32 })
  }
}
