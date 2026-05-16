import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CryptoJS } from '@ohos/crypto-js';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';

export default class ShareUtils {
  public ShareURL: string
  public FileUri: string = ''
  public ShareBuffer: ArrayBuffer | null = null
  private context: Context
  private fileName: string
  private readonly QRCODE_OPTIONS: generateBarcode.CreateOptions = {
    scanType: scanCore.ScanType.QR_CODE,
    height: 200,
    width: 200
  }
  private readonly packOpts: image.PackingOption = { format: 'image/jpeg', quality: 100 }

  constructor(context: Context, ShareURL: string) {
    this.context = context
    this.ShareURL = ShareURL
    this.fileName = CryptoJS.MD5(ShareURL).toString().substring(0, 10) + '.jpg'
  }

  async prepare(): Promise<boolean> {
    try {
      const pixelMap: image.PixelMap = await generateBarcode.createBarcode(this.ShareURL, this.QRCODE_OPTIONS)
      const imagePackerApi: image.ImagePacker = image.createImagePacker()
      const result = await imagePackerApi.packToData(pixelMap, this.packOpts)
      if (!result) {
        hilog.error(0x0001, 'ShareUtils', 'packToData returned undefined')
        return false
      }
      this.ShareBuffer = result
      const filePath = `${this.context.cacheDir}/${this.fileName}`
      let fh = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
      try {
        fs.writeSync(fh.fd, this.ShareBuffer)
      } finally {
        fs.closeSync(fh)
      }
      const uriObj = new fileUri.FileUri(filePath)
      this.FileUri = uriObj.toString()
      return true
    } catch (error) {
      const bizError = error as BusinessError
      hilog.error(0x0001, 'ShareUtils', `prepare failed: ${bizError.code}, ${bizError.message}`)
      return false
    }
  }
}
