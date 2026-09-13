package android.app
import android.content.Intent
import android.content.pm.PackageManager
open class Activity {
 val packageManager=PackageManager()
 open fun startActivityForResult(intent:Intent,code:Int) {}
 open fun finishActivity(code:Int) {}
 companion object { const val RESULT_OK=-1; const val RESULT_CANCELED=0 }
}
