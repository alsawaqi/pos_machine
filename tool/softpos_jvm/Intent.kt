package android.content
import android.content.pm.PackageManager
class ActivityNotFoundException:RuntimeException()
class Intent(val action:String="") {
 var target=""
 val extras=mutableMapOf<String,Any?>()
 fun setPackage(value:String):Intent {target=value;return this}
 fun putExtra(key:String,value:Any?):Intent {extras[key]=value;return this}
 fun getStringExtra(key:String):String?=extras[key] as? String
 fun resolveActivity(pm:PackageManager):Any?=if(pm.visible) Any() else null
}
