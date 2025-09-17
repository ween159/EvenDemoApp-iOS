import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:demo_ai_even/app.dart';
import 'package:demo_ai_even/services/ble.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/services/realtime_translate_service.dart';
import 'package:flutter/services.dart';

typedef SendResultParse = bool Function(Uint8List value);


class BleManager {
  BleManager._();
  static final BleManager instance = BleManager._();

  Function()? onStatusChanged;
  final Map<String, Completer<BleReceive>> _reqListen = {};
  final Map<String, Timer> _reqTimeout = {};
  Completer<BleReceive>? _nextReceive;

  static const String methodSend = "send";
  static const String _eventBleReceive = "eventBleReceive";
  static const MethodChannel _channel = MethodChannel('method.bluetooth');

  final eventBleReceive = const EventChannel(_eventBleReceive)
      .receiveBroadcastStream(_eventBleReceive)
      .map((ret) => BleReceive.fromMap(ret));

  Timer? beatHeartTimer;
  final List<Map<String, String>> pairedGlasses = [];
  bool isConnected = false;
  String connectionStatus = 'Not connected';
  // int tryTime = 0; // removed duplicate

  void init() {
    // Initialization logic if needed
  }

  void startListening() {
    eventBleReceive.listen((res) {
      _handleReceivedData(res);
    });
  }

  Future<void> startScan() async {
    try {
      await _channel.invokeMethod('startScan');
    } catch (e) {
      debugPrint('Error starting scan: $e');
    }
  }

  Future<void> stopScan() async {
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
  }

  Future<void> connectToGlasses(String deviceName) async {
    try {
      await _channel.invokeMethod('connectToGlasses', {'deviceName': deviceName});
      connectionStatus = 'Connecting...';
    } catch (e) {
debugPrint('Error connecting to device: $e');
    }
  }

  void setMethodCallHandler() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    switch (call.method) {
      case 'glassesConnected':
        _onGlassesConnected(call.arguments);
        break;
      case 'glassesConnecting':
        _onGlassesConnecting();
        break;
      case 'glassesDisconnected':
        _onGlassesDisconnected();
        break;
      case 'foundPairedGlasses':
        _onPairedGlassesFound(Map<String, String>.from(call.arguments));
        break;
      default:
debugPrint('Unknown method: ${call.method}');
    }
  }

  void _onGlassesConnected(dynamic arguments) {
debugPrint("_onGlassesConnected----arguments----$arguments------");
    connectionStatus = 'Connected: \n${arguments['leftDeviceName']} \n${arguments['rightDeviceName']}';
    isConnected = true;

    onStatusChanged?.call();
    startSendBeatHeart();
  }

  int tryTime = 0;
  void startSendBeatHeart() async {
    beatHeartTimer?.cancel();
    beatHeartTimer = null;

    beatHeartTimer = Timer.periodic(const Duration(seconds: 8), (timer) async {
      bool isSuccess = await Proto.sendHeartBeat();
      if (!isSuccess && tryTime < 2) {
        tryTime++;
        await Proto.sendHeartBeat();
      } else {
        tryTime = 0;
      }
    });
  }

  void _onGlassesConnecting() {
    connectionStatus = 'Connecting...';

      onStatusChanged?.call();
  }

  void _onGlassesDisconnected() {
    connectionStatus = 'Not connected';
    isConnected = false;

    onStatusChanged?.call();
  }

  void _onPairedGlassesFound(Map<String, String> deviceInfo) {
    final String channelNumber = deviceInfo['channelNumber']!;
    final isAlreadyPaired = pairedGlasses.any((glasses) => glasses['channelNumber'] == channelNumber);

    if (!isAlreadyPaired) {
      pairedGlasses.add(deviceInfo);
    }

    onStatusChanged?.call();
  }

  void _handleReceivedData(BleReceive res) {
    if (res.type == "VoiceChunk") {
      try {
        // res.data is a byte array containing WAV bytes (we expect WAV from native)
        final wav = res.data;
        // Forward to realtime translate service if running
        RealtimeTranslateService.I.processWavBytes(wav);
      } catch (e) {
debugPrint('Error processing VoiceChunk: $e');
      }
      return;
    }

    String cmd = "${res.lr}${res.getCmd().toRadixString(16).padLeft(2, '0')}";
    if (res.getCmd() != 0xf1) {
debugPrint(
        "${DateTime.now()} BleManager receive cmd: $cmd, len: ${res.data.length}, data = ${res.data.hexString}",
      );
    }

    if (res.data[0].toInt() == 0xF5) {
      final notifyIndex = res.data[1].toInt();
      
      switch (notifyIndex) {
        case 0:
          App.get.exitAll();
          break;
        case 1: 
          if (res.lr == 'L') {
            EvenAI.get.lastPageByTouchpad();
          } else {
            EvenAI.get.nextPageByTouchpad();
          }
          break;
        case 23: //BleEvent.evenaiStart:
          EvenAI.get.toStartEvenAIByOS();
          break;
        case 24: //BleEvent.evenaiRecordOver:
          EvenAI.get.recordOverByOS();
          break;
        default:
debugPrint("Unknown Ble Event: $notifyIndex");
      }
      return;
    }
      _reqListen.remove(cmd)?.complete(res);
      _reqTimeout.remove(cmd)?.cancel();
      if (_nextReceive != null) {
        _nextReceive?.complete(res);
        _nextReceive = null;
      }

  }

  String getConnectionStatus() {
    return connectionStatus;
  }

  List<Map<String, String>> getPairedGlasses() {
    return pairedGlasses;
  }



  void _checkTimeout(String cmd, int timeoutMs, Uint8List data, String lr) {
    _reqTimeout.remove(cmd);
    var cb = _reqListen.remove(cmd);
    debugPrint('${DateTime.now()} _checkTimeout-----timeoutMs----$timeoutMs-----cb----$cb-----');
    if (cb != null) {
      var res = BleReceive();
      res.isTimeout = true;
      debugPrint("send Timeout $cmd of $timeoutMs");
      cb.complete(res);
    }
    _reqTimeout[cmd]?.cancel();
    _reqTimeout.remove(cmd);
  }

  Future<T?> invokeMethod<T>(String method, [dynamic params]) {
    return _channel.invokeMethod(method, params);
  }

  Future<BleReceive> requestRetry(
    Uint8List data, {
    String? lr,
    Map<String, dynamic>? other,
    int timeoutMs = 200,
    bool useNext = false,
    int retry = 3,
  }) async {
    BleReceive ret;
    for (var i = 0; i <= retry; i++) {
      ret = await request(data,
          lr: lr, other: other, timeoutMs: timeoutMs, useNext: useNext);
      if (!ret.isTimeout) {
        return ret;
      }
      if (!isBothConnected()) {
        break;
      }
    }
    ret = BleReceive();
    ret.isTimeout = true;
    debugPrint("requestRetry $lr timeout of $timeoutMs");
    return ret;
  }

  Future<bool> sendBoth(
    data, {
    int timeoutMs = 250,
    SendResultParse? isSuccess,
    int? retry,
  }) async {
    var ret = await requestRetry(data,
        lr: "L", timeoutMs: timeoutMs, retry: retry ?? 0);
    if (ret.isTimeout) {
      debugPrint("sendBoth L timeout");
      return false;
    } else if (isSuccess != null) {
      final success = isSuccess.call(ret.data);
      if (!success) return false;
      var retR = await requestRetry(data,
          lr: "R", timeoutMs: timeoutMs, retry: retry ?? 0);
      if (retR.isTimeout) return false;
      return isSuccess.call(retR.data);
    } else if (ret.data[1].toInt() == 0xc9) {
      var ret = await requestRetry(data,
          lr: "R", timeoutMs: timeoutMs, retry: retry ?? 0);
      if (ret.isTimeout) return false;
    }
    return true;
  }

  Future sendData(Uint8List data,
      {String? lr, Map<String, dynamic>? other, int secondDelay = 100}) async {
    var params = <String, dynamic>{
      'data': data,
    };
    if (other != null) {
      params.addAll(other);
    }
    dynamic ret;
    if (lr != null) {
      params["lr"] = lr;
      ret = await invokeMethod(methodSend, params);
      return ret;
    } else {
      params["lr"] = "L";
      var ret = await _channel.invokeMethod(methodSend, params);
      if (ret == true) {
        params["lr"] = "R";
        ret = await invokeMethod(methodSend, params);
        return ret;
      }
      if (secondDelay > 0) {
        await Future.delayed(Duration(milliseconds: secondDelay));
      }
      params["lr"] = "R";
      ret = await invokeMethod(methodSend, params);
      return ret;
    }
  }

  Future<BleReceive> request(Uint8List data,
      {String? lr,
      Map<String, dynamic>? other,
      int timeoutMs = 1000,
      bool useNext = false}) async {
    var lr0 = lr ?? Proto.lR();
    var completer = Completer<BleReceive>();
    String cmd = "$lr0${data[0].toRadixString(16).padLeft(2, '0')}";
    if (useNext) {
      _nextReceive = completer;
    } else {
      if (_reqListen.containsKey(cmd)) {
        var res = BleReceive();
        res.isTimeout = true;
        _reqListen[cmd]?.complete(res);
        debugPrint("already exist key: $cmd");
        _reqTimeout[cmd]?.cancel();
      }
      _reqListen[cmd] = completer;
    }
    debugPrint("request key: $cmd, ");
    if (timeoutMs > 0) {
      _reqTimeout[cmd] = Timer(Duration(milliseconds: timeoutMs), () {
        _checkTimeout(cmd, timeoutMs, data, lr0);
      });
    }
    completer.future.then((result) {
      _reqTimeout.remove(cmd)?.cancel();
    });
    await sendData(data, lr: lr, other: other).timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _reqTimeout.remove(cmd)?.cancel();
        var ret = BleReceive();
        ret.isTimeout = true;
        _reqListen.remove(cmd)?.complete(ret);
      },
    );
    return completer.future;
  }

  bool isBothConnected() {
    return isConnected;
  }

  Future<bool> requestList(
    List<Uint8List> sendList, {
    String? lr,
    int? timeoutMs,
  }) async {
    debugPrint("requestList---sendList---${sendList.first}----lr---$lr----timeoutMs----$timeoutMs-");
    if (lr != null) {
      return await _requestList(sendList, lr, timeoutMs: timeoutMs);
    } else {
      var rets = await Future.wait([
        _requestList(sendList, "L", keepLast: true, timeoutMs: timeoutMs),
        _requestList(sendList, "R", keepLast: true, timeoutMs: timeoutMs),
      ]);
      if (rets.length == 2 && rets[0] && rets[1]) {
        var lastPack = sendList[sendList.length - 1];
        return await sendBoth(lastPack, timeoutMs: timeoutMs ?? 250);
      } else {
        debugPrint("error request lr leg");
      }
    }
    return false;
  }

  Future<bool> _requestList(List sendList, String lr,
      {bool keepLast = false, int? timeoutMs}) async {
    int len = sendList.length;
    if (keepLast) len = sendList.length - 1;
    for (var i = 0; i < len; i++) {
      var pack = sendList[i];
      var resp = await request(pack, lr: lr, timeoutMs: timeoutMs ?? 350);
      if (resp.isTimeout) {
        return false;
      } else if (resp.data[1].toInt() != 0xc9 && resp.data[1].toInt() != 0xcB) {
        return false;
      }
    }
    return true;
  }

}

extension Uint8ListEx on Uint8List {
  String get hexString {
    return map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}


