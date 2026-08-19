package lt.turron.sivelo

import android.app.Application
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader

class SignerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        PDFBoxResourceLoader.init(applicationContext)
    }
}
