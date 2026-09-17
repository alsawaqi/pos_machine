import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.SystemClock
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.mithqal.softpos.SoftPosBridgeCore
import org.json.JSONObject

class Reply:MethodChannel.Result {
 var value:Any?=null;var code:String?=null;var count=0
 override fun success(value:Any?){this.value=value;count++}
 override fun error(code:String,message:String?,details:Any?){this.code=code;count++}
 override fun notImplemented(){error("NOT_IMPLEMENTED",null,null)}
 fun json()=JSONObject(value as String)
}
class Harness {
 val activity=Activity();val channel=MethodChannel();val launches=mutableListOf<Pair<Intent,Int>>()
 val core=SoftPosBridgeCore {_,intent,code,_->launches.add(intent to code)}
 val args=mapOf<String,Any?>("packageName" to "com.mosambee.muscat.softpos","userName" to "T","pin" to "PIN","currency" to "0512","amountBaisas" to 4750L)
 init {Handler.timers.clear();SystemClock.now=1000;core.configure(activity,channel)}
 fun call(method:String,extra:Map<String,Any?> = emptyMap()):Reply {val r=Reply();channel.handler(MethodCall(method,args+extra),r);return r}
 fun respond(code:String,session:String?=null,result:Int=Activity.RESULT_OK) {
  val data=Intent().putExtra("responseCode",code).putExtra("sessionId",session).putExtra("receiptResponse","{\"rrn\":\"R\"}")
  core.handleActivityResult(activity,launches.last().second,result,data)
 }
 fun prime(){val r=call("prepareLogin");respond("00","S");check(r.json().getString("sessionId")=="S")}
}
fun main() {
 var passed=0
 fun test(name:String,body:()->Unit){body();passed++;println("PASS "+name)}
 test("failing-code login discards session and never launches a sale") {
  val h=Harness();val r=h.call("loginAndPay");h.respond("51","UNSAFE")
  check(r.json().getString("status")=="declined");check(h.launches.size==1)
  check(h.call("hasPreparedSession").value==false)
 }
 test("BUSY is surfaced with no second activity") {
  val h=Harness();h.call("loginAndPay");val r=h.call("loginAndPay")
  check(r.code=="BUSY");check(h.launches.size==1)
 }
 test("exact integer baisas and currency reach the bank, with no double conversion") {
  val h=Harness();h.prime();val r=h.call("payWithPreparedSession",mapOf("amountBaisas" to 9007199254740993L))
  check(h.launches.last().first.getStringExtra("amount")=="9007199254740993")
  check(h.launches.last().first.getStringExtra("currency")=="0512")
  h.respond("00");check(r.json().getString("status")=="approved")
  check(h.launches.size==2) // No native launch after the definitive answer.
  val next=h.call("prepareLogin");check(h.launches.size==3)
  check(h.launches.last().first.action.endsWith(".login"));h.respond("00","NEXT")
  check(next.json().getString("sessionId")=="NEXT")
 }
 test("session expires after five minutes") {
  val h=Harness();h.prime();SystemClock.now+=300_000
  val r=h.call("payWithPreparedSession");check(r.json().getString("code")=="NO_SESSION");check(h.launches.size==1)
 }
 for(method in listOf("loginAndPay","voidTransaction","refundTransaction")) {
  test("99 retries once and preserves "+method) {
   val h=Harness();val r=h.call(method,mapOf("transactionId" to "ORIGINAL","needsSession" to false))
   if(method=="loginAndPay")h.respond("00","S")
   val bankAction=h.launches.last().first.action
   h.respond("99");check(h.launches.last().first.action.endsWith(".login"));h.respond("00","S2")
   check(h.launches.last().first.action==bankAction);h.respond("99")
   check(r.count==1);check(r.json().getString("status")=="declined")
   check(h.launches.count{it.first.action==bankAction}==2)
  }
 }
 test("watchdog returns uncertain once and rejects late approval") {
  val h=Harness();val r=h.call("refundTransaction");val code=h.launches.last().second
  Handler.fire();check(r.json().getString("status")=="uncertain");check(r.count==1)
  check(h.core.handleActivityResult(h.activity,code,Activity.RESULT_OK,Intent().putExtra("responseCode","00")))
  check(r.count==1);check(h.launches.size==1)
 }
 test("health distinguishes install, visibility and bank refusal") {
  val h=Harness();h.activity.packageManager.installed=false
  check(h.call("healthCheck").json().getString("code")=="SOFTPOS_NOT_INSTALLED")
  h.activity.packageManager.installed=true;h.activity.packageManager.visible=false
  check(h.call("healthCheck").json().getString("code")=="SOFTPOS_ACTIVITY_NOT_VISIBLE")
  h.activity.packageManager.visible=true;val r=h.call("healthCheck");h.respond("51")
  check(r.json().getString("code")=="SOFTPOS_HEALTH_REFUSED")
 }
 test("send_currency=false omits currency and Dhofar reversal needs no session") {
  val h=Harness();h.call("refundTransaction",mapOf("sendCurrency" to false,"packageName" to "com.mosambee.dhofar.softpos"))
  val intent=h.launches.single().first;check(!intent.extras.containsKey("currency"));check(!intent.extras.containsKey("sessionId"))
  check(intent.getStringExtra("amount")=="4750")
 }
 test("explicit stale session cannot bypass TTL or be reused") {
  val h=Harness();h.prime();SystemClock.now+=300_000
  val r=h.call("payWithPreparedSession",mapOf("sessionId" to "S"))
  check(r.json().getString("code")=="NO_SESSION");check(h.launches.size==1)
 }
 test("empty activity return remains uncertain while explicit blank-description cancel is safe") {
  val h=Harness();val r=h.call("refundTransaction")
  h.core.handleActivityResult(h.activity,h.launches.last().second,Activity.RESULT_CANCELED,null)
  check(r.json().getString("status")=="uncertain")
  val h2=Harness();val r2=h2.call("refundTransaction")
  h2.core.handleActivityResult(h2.activity,h2.launches.last().second,Activity.RESULT_CANCELED,Intent().putExtra("status","cancelled"))
  check(r2.json().getString("status")=="cancelled")
 }

 test("initial login failure proves no payment was dispatched") {
  val h=Harness();val r=h.call("loginAndPay");h.respond("51")
  check(r.json().getBoolean("paymentDispatched")==false);check(h.launches.size==1)
 }
 test("payment 99 then login failure retains dispatch provenance") {
  val h=Harness();h.prime();val r=h.call("payWithPreparedSession")
  h.respond("99");h.respond("51")
  check(r.json().getBoolean("paymentDispatched"));check(h.launches.size==3)
 }
 test("initial login watchdog proves no payment but payment watchdog does not") {
  val h=Harness();val r=h.call("loginAndPay");Handler.fire()
  check(!r.json().getBoolean("paymentDispatched"));check(h.launches.size==1)
  val h2=Harness();h2.prime();val r2=h2.call("payWithPreparedSession");Handler.fire()
  check(r2.json().getBoolean("paymentDispatched"));check(h2.launches.size==2)
 }
 println("OK ("+passed+" JVM core contract tests)")
}
