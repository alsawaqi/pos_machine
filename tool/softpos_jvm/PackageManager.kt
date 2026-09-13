package android.content.pm
class PackageManager {
 var installed=true;var visible=true
 class NameNotFoundException:RuntimeException()
 fun getPackageInfo(name:String,flags:Int):Any {if(!installed) throw NameNotFoundException();return Any()}
}
