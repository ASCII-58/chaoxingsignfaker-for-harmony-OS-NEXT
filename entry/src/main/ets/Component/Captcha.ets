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
        Image(this.info.imageVerificationVo.shadeImage??$r('app.media.testb'))
        Image(this.info.imageVerificationVo.cutoutImage??$r('app.media.testp')).translate({x:this.xTranslate})
      }.onAppear(()=>{
        // if (this.signIdArray.length>0) {
        //   const DBM = DatabaseManager.getInstance()
        //
        //   this.signIdArray[this.CaptchaIndex]
        // }
      })
      Slider({value:this.xTranslate,max:280})
    }
  }
}
