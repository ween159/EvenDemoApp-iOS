import 'package:flutter/foundation.dart';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/bmp_update_manager.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/utils/utils.dart';

class FeaturesServices {
  final bmpUpdateManager = BmpUpdateManager();
  Future<void> sendBmp(String imageUrl) async {
    Uint8List bmpData = await Utils.loadBmpImage(imageUrl);
    int initialSeq = 0;
    bool isSuccess = await Proto.sendHeartBeat();
debugPrint("${DateTime.now()} testBMP -------startSendBeatHeart----isSuccess---$isSuccess------");
    BleManager.instance.startSendBeatHeart();

    final results = await Future.wait([
      bmpUpdateManager.updateBmp("L", bmpData, seq: initialSeq),
      bmpUpdateManager.updateBmp("R", bmpData, seq: initialSeq)
    ]);

    bool successL = results[0];
    bool successR = results[1];

    if (successL) {
debugPrint("${DateTime.now()} left ble success");
    } else {
debugPrint("${DateTime.now()} left ble fail");
    }

    if (successR) {
debugPrint("${DateTime.now()} right ble success");
    } else {
debugPrint("${DateTime.now()} right ble success");
    }
  }

  Future<void> exitBmp() async {
    bool isSuccess = await Proto.exit();
debugPrint("exitBmp----isSuccess---$isSuccess--");
  }
}

