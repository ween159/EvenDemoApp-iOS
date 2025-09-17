﻿import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';


class Utils {
  Utils._();

  static int getTimestampMs() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  static Uint8List addPrefixToUint8List(List<int> prefix, Uint8List data) {
    var newData = Uint8List(data.length + prefix.length);
    for (var i = 0; i < prefix.length; i++) {
      newData[i] = prefix[i];
    }
    for (var i = prefix.length, j = 0;
        i < prefix.length + data.length;
        i++, j++) {
      newData[i] = data[j];
    }
    return newData;
  }

  /// Convert binary array to hexadecimal string
  static String bytesToHexStr(Uint8List data, [String join = '']) {
    List<String> hexList =
        data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).toList();
    String hexResult = hexList.join(join);
    return hexResult;
  }

  static Future<Uint8List> loadBmpImage(String imageUrl) async {
    try {
      final ByteData data = await rootBundle.load(imageUrl);
      return data.buffer.asUint8List();
    } catch (e) {
debugPrint("Error loading BMP file: $e");
      return Uint8List(0);
    }
  }
}

