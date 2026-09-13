package android.os
object SystemClock {var now=1000L;fun elapsedRealtime()=now}
class Looper {companion object {fun getMainLooper()=Looper()}}
class Handler(looper:Looper) {
 companion object {val timers=mutableListOf<Runnable>();fun fire(){val copy=timers.toList();timers.clear();copy.forEach{it.run()}}}
 fun postDelayed(timer:Runnable,delay:Long) {check(delay==90_000L);timers.add(timer)}
 fun removeCallbacks(timer:Runnable) {timers.remove(timer)}
}
