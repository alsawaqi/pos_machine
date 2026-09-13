package io.flutter.plugin.common
class MethodCall(val method:String,val arguments:Any?)
class MethodChannel {
 interface Result {fun success(value:Any?);fun error(code:String,message:String?,details:Any?);fun notImplemented()}
 lateinit var handler:(MethodCall,Result)->Unit
 fun setMethodCallHandler(callback:(MethodCall,Result)->Unit) {handler=callback}
}
