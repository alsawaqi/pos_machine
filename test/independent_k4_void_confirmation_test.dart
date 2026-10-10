import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
class Adapter implements HttpClientAdapter{
 String outcome='offline';final requests=<List<Map<String,dynamic>>>[];Completer<void>? entered,release;
 @override Future<ResponseBody> fetch(RequestOptions options,Stream<Uint8List>? stream,Future<void>? cancel)async{
 final data=options.data is String?jsonDecode(options.data as String):options.data;final events=(data['events'] as List).map((e)=>(e as Map).cast<String,dynamic>()).toList();requests.add(events);if(entered?.isCompleted==false)entered!.complete();await release?.future;
 if(outcome=='offline')throw DioException(requestOptions:options,type:DioExceptionType.connectionError,error:'lost ACK');
  final good=[for(final e in events){'client_event_id':e['client_event_id'],'status':'processed'}];final results=switch(outcome){'wrong'=>[{'client_event_id':'another-event','status':'processed'}],'missing'=>[],'duplicate'=>[...good,...good],'extra'=>[...good,{'client_event_id':'extra','status':'processed'}],'failed'=>[for(final e in events){'client_event_id':e['client_event_id'],'status':'failed','result':{'error':'denied'}}],_=>good};
 return ResponseBody.fromString(jsonEncode({'data':{'results':results}}),200,headers:{Headers.contentTypeHeader:['application/json']});}
 @override void close({bool force=false}){}
}
void main(){TestWidgetsFlutterBinding.ensureInitialized();late AppDatabase db;late OrderSyncRepository repo;late Dio dio;late Adapter adapter;final owner=BusinessIdentity(1,2,'synthetic-device');
 setUp(()async{BusinessBoundary.resetForTest();SharedPreferences.setMockInitialValues({BusinessBoundary.identityKey:owner.encoded});await BusinessBoundary.initialize(await SharedPreferences.getInstance());db=AppDatabase.forTesting(NativeDatabase.memory());adapter=Adapter();dio=Dio(BaseOptions(baseUrl:'https://synthetic.test'))..httpClientAdapter=adapter;repo=OrderSyncRepository(PosApiService(tokenGetter:()=>'synthetic-device',dio:dio),db)..managedKitchen=()=>true;});
 tearDown(()async{await repo.dispose();dio.close(force:true);await db.close();BusinessBoundary.resetForTest();});
 test('managed offline void stays pending; retries original event after ACK loss',()async{await expectLater(repo.enqueueVoid('review-order',reason:'original'),throwsStateError);final row=(await repo.allRows()).single;expect(row.syncedAt,isNull);final old=row.eventsJson;adapter.outcome='ok';await repo.enqueueVoid('review-order',reason:'changed');expect((await repo.allRows()).single.eventsJson,old);expect((await repo.allRows()).single.syncedAt,isNotNull);expect(adapter.requests.last.single['payload']['reason'],'original');});
 test('managed void cannot return before its ACK',()async{adapter.outcome='ok';adapter.entered=Completer<void>();adapter.release=Completer<void>();var returned=false;final f=repo.enqueueVoid('review-order').then((_)=>returned=true);await adapter.entered!.future;expect(returned,isFalse);adapter.release!.complete();await f;expect(returned,isTrue);});
 test('wrong event processed ACK cannot confirm cancellation',()async{adapter.outcome='wrong';await expectLater(repo.enqueueVoid('review-order'),throwsStateError);expect((await repo.allRows()).single.syncedAt,isNull);});
 test('legacy offline void keeps prior queued behavior',()async{repo.managedKitchen=()=>false;await repo.enqueueVoid('review-order');expect((await repo.allRows()).single.syncedAt,isNull);});
 for(final outcome in ['missing','duplicate','extra','failed']){test('managed void refuses $outcome acknowledgement',()async{adapter.outcome=outcome;await expectLater(repo.enqueueVoid('review-order'),throwsStateError);expect((await repo.allRows()).single.syncedAt,isNull);});}
 test('managed cancellation joins active flush without early success',()async{adapter.outcome='ok';adapter.entered=Completer<void>();adapter.release=Completer<void>();final first=repo.enqueueEvent('earlier',{'client_event_id':'earlier','event_type':'order.hold','payload':{}});await adapter.entered!.future;var returned=false;final pending=repo.enqueueVoid('review-order').then((_)=>returned=true);await Future<void>.delayed(Duration.zero);expect(returned,isFalse);adapter.release!.complete();await first;await pending;expect((await repo.allRows()).where((r)=>r.orderUuid=='review-order:void').single.syncedAt,isNotNull);});}

