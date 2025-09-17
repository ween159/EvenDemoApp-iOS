import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/services/api_services_deepseek.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class EvenAI {
  static EvenAI? _instance;
  static EvenAI get get => _instance ??= EvenAI._();

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  bool isReceivingAudio = false;
  List<int> audioDataBuffer = [];
  Uint8List? audioData;

  File? lc3File;
  File? pcmFile;
  int durationS = 0;

  static int maxRetry = 10;
  static int _currentLine = 0;
  static Timer? _timer; // Text sending timer
  static List<String> list = [];
  static List<String> sendReplys = [];

  Timer? _recordingTimer;
  final int maxRecordingDuration = 30; // todo

  static bool _isManual = false; 

  static set isRunning(bool value) {
    _isRunning = value;
    isEvenAIOpen.value = value;

    isEvenAISyncing.value = value;
  }

  static RxBool isEvenAIOpen = false.obs;

  static RxBool isEvenAISyncing = false.obs;

  int _lastStartTime = 0; // Avoid repeated startup commands of Android Bluetooth in a short period of time
  int _lastStopTime = 0; // Avoid repeated termination commands of Android Bluetooth within a short period of time
  final int startTimeGap = 500; // Filter repeated Bluetooth intervals
  final int stopTimeGap = 500;

  static const _eventSpeechRecognize = "eventSpeechRecognize"; 
  final _eventSpeechRecognizeChannel =
      const EventChannel(_eventSpeechRecognize).receiveBroadcastStream(_eventSpeechRecognize);

  String combinedText = '';

  static final StreamController<String> _textStreamController = StreamController<String>.broadcast();
  static Stream<String> get textStream => _textStreamController.stream;

  static void updateDynamicText(String newText) {
    _textStreamController.add(newText);
  }

  EvenAI._(); 

  void startListening() {
    combinedText = '';
    _eventSpeechRecognizeChannel.listen((event) {
      var txt = event["script"] as String;
      combinedText = txt;
    }, onError: (error) {
debugPrint("Error in event: $error");
    });
  }

  // receiving starting Even AI request from ble
  void toStartEvenAIByOS() async {
    // Only start if glasses are connected and not already receiving audio
    if (!BleManager.instance.isBothConnected()) {
      debugPrint('toStartEvenAIByOS: glasses not connected, ignoring start request from OS');
      return;
    }
    if (isReceivingAudio) {
      debugPrint('toStartEvenAIByOS: already receiving audio, ignoring duplicate start');
      return;
    }

    // restart to avoid ble data conflict
    BleManager.instance.startSendBeatHeart();

    startListening();

    // avoid duplicate ble command in short time, especially android
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastStartTime < startTimeGap) {
      return;
    }

    _lastStartTime = currentTime;

    clear();
    isReceivingAudio = true;

    isRunning = true;
    _currentLine = 0;

    await BleManager.instance.invokeMethod("startEvenAI");

    await openEvenAIMic();

    startRecordingTimer();
  }

  // Monitor the recording time to prevent the recording from ending when the OS exits unexpectedly
  void startRecordingTimer() {
    _recordingTimer = Timer(Duration(seconds: maxRecordingDuration), () {
      if (isReceivingAudio) {
debugPrint("${DateTime.now()} Even AI startRecordingTimer-----exit-----");
        clear();
        //Proto.exit();
      } else {
        _recordingTimer?.cancel();
        _recordingTimer = null;
      }
    });
  }

  // 收到眼镜端Even AI录音结束指令
  Future<void> recordOverByOS() async {
debugPrint('${DateTime.now()} EvenAI -------recordOverByOS-------');

    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastStopTime < stopTimeGap) {
      return;
    }
    _lastStopTime = currentTime;

    isReceivingAudio = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    await BleManager.instance.invokeMethod("stopEvenAI");
    await Future.delayed(const Duration(seconds: 2)); // todo
debugPrint("recordOverByOS----startSendReply---pre------combinedText-------*$combinedText*---");

    if (combinedText.isEmpty) {
      
      updateDynamicText("No Speech Recognized");
      isEvenAISyncing.value = false;
      startSendReply("No Speech Recognized");
      return;
    }

    final apiService = ApiDeepSeekService();
    String answer = await apiService.sendChatRequest(combinedText);
debugPrint("recordOverByOS----startSendReply---combinedText-------*$combinedText*-----answer----$answer----");

    updateDynamicText("$combinedText\n\n$answer");
    isEvenAISyncing.value = false;
    saveQuestionItem(combinedText, answer);
    startSendReply(answer);
  }

  void saveQuestionItem(String title, String content) {
debugPrint("saveQuestionItem----title----$title----content---$content-");
    final controller = Get.find<EvenaiModelController>();
    controller.addItem(title, content);
  }

  int getTotalPages() {
    if (list.isEmpty) {
      return 0;
    }
    if (list.length < 6) {
      return 1;
    }
    int pages = 0;
    int div = list.length ~/ 5;
    int rest = list.length % 5;
    pages = div;
    if (rest != 0) {
      pages++;
    }
    return pages;
  }

  int getCurrentPage() {
    if (_currentLine == 0) {
      return 1;
    }
    int currentPage = 1;
    int div = _currentLine ~/ 5;
    int rest = _currentLine % 5;
    currentPage = 1 + div;
    if (rest != 0) {
      currentPage++;
    }
    return currentPage;
  }

  Future sendNetworkErrorReply(String text) async {
    _currentLine = 0;
    list = EvenAIDataMethod.measureStringList(text);

    String ryplyWords =
        list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
    String headString = '\n\n';
    ryplyWords = headString + ryplyWords;

    // After sending the network error prompt glasses, exit automatically
    await sendEvenAIReply(ryplyWords, 0x01, 0x60, 0);
    clear();
  }

  Future startSendReply(String text) async {
    _currentLine = 0;
    list = EvenAIDataMethod.measureStringList(text);
   
    if (list.length < 4) {
      String startScreenWords =
          list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
      String headString = '\n\n';
      startScreenWords = headString + startScreenWords;

      // The glasses need to have 0x30 before they can process 0x40
  await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);
      
      // Send 0x40 after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      // If already switched to manual mode, no need to send 0x40.
      if (_isManual) {
        return;
      }
      await sendEvenAIReply(startScreenWords, 0x01, 0x40, 0);
      return;
    }
    if (list.length == 4) {
      String startScreenWords =
          list.sublist(0, 4).map((str) => '$str\n').join();
      String headString = '\n';
      startScreenWords = headString + startScreenWords;

      // // The glasses need to have 0x30 before they can process 0x40
  await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);
      await Future.delayed(const Duration(seconds: 3));
      if (_isManual) {
        return;
      }
      await sendEvenAIReply(startScreenWords, 0x01, 0x40, 0);
      return;
    }

    if (list.length == 5) {
      String startScreenWords =
          list.sublist(0, 5).map((str) => '$str\n').join();
      // // The glasses need to have 0x30 before they can process 0x40
  await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);
      await Future.delayed(const Duration(seconds: 3));
      if (_isManual) {
        return;
      }
      await sendEvenAIReply(startScreenWords, 0x01, 0x40, 0);
      return;
    }

    String startScreenWords = list.sublist(0, 5).map((str) => '$str\n').join();
  await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);
    
  // best-effort: sendEvenAIReply will retry internally; proceed to periodic updates
  _currentLine = 0;
  await updateReplyToOSByTimer();
  }

  Future updateReplyToOSByTimer() async {

    int interval = 5; // The paging interval can be customized
   
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: interval), (timer) async {
      // Switched to manual mode, abolished timer update
      if (_isManual) {
        _timer?.cancel();
        _timer = null;
        return;
      }

      _currentLine = min(_currentLine + 5, list.length - 1);
      sendReplys = list.sublist(_currentLine);

      if (_currentLine > list.length - 1) {
        _timer?.cancel();
        _timer = null;
      } else {
        if (sendReplys.length < 4) {
          var mergedStr = sendReplys
              .sublist(0, sendReplys.length)
              .map((str) => '$str\n')
              .join();

          if (_currentLine >= list.length - 5) {
            await sendEvenAIReply(mergedStr, 0x01, 0x40, 0);
            _timer?.cancel();
            _timer = null;
          } else {
            await sendEvenAIReply(mergedStr, 0x01, 0x30, 0);
          }
        } else {
          var mergedStr = sendReplys
              .sublist(0, min(5, sendReplys.length))
              .map((str) => '$str\n')
              .join();

          if (_currentLine >= list.length - 5) {
            await sendEvenAIReply(mergedStr, 0x01, 0x40, 0);
            _timer?.cancel();
            _timer = null;
          } else {
            await sendEvenAIReply(mergedStr, 0x01, 0x30, 0);
          }
        }
      }
    });
  }

  // Click the TouchBar on the right to turn the page down
  void nextPageByTouchpad() {
    if (!isRunning) return;
    _isManual = true;
    _timer?.cancel();
    _timer = null;

    if (getTotalPages() < 2) {
      manualForJustOnePage();
      return;
    }

    if (_currentLine + 5 > list.length - 1) {
      return;
    } else {
      _currentLine += 5;
    }
    updateReplyToOSByManual();
  }

  // Click the TouchBar on the right to turn the page down
  void lastPageByTouchpad() {
    if (!isRunning) return;
    _isManual = true;
    _timer?.cancel();
    _timer = null;

    if (getTotalPages() < 2) {
      manualForJustOnePage();
      return;
    }

    if (_currentLine - 5 < 0) {
      _currentLine == 0;
    } else {
      _currentLine -= 5;
    }
    updateReplyToOSByManual();
  }

  Future updateReplyToOSByManual() async {
    if (_currentLine < 0 || _currentLine > list.length - 1) {
      return;
    }

    sendReplys = list.sublist(_currentLine);
    if (sendReplys.length < 4) {
      var mergedStr = sendReplys
          .sublist(0, sendReplys.length)
          .map((str) => '$str\n')
          .join();
      await sendEvenAIReply(mergedStr, 0x01, 0x50, 0);
    } else {
      var mergedStr = sendReplys
          .sublist(0, min(5, sendReplys.length))
          .map((str) => '$str\n')
          .join();
      await sendEvenAIReply(mergedStr, 0x01, 0x50, 0);
    }
  }

  // When there is only one page of text, click the page turn TouchBar
  Future manualForJustOnePage() async {
    if (list.length < 4) {
      String screenWords =
          list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
      String headString = '\n\n';
      screenWords = headString + screenWords;

      await sendEvenAIReply(screenWords, 0x01, 0x50, 0);
      return;
    }

    if (list.length == 4) {
      String screenWords = list.sublist(0, 4).map((str) => '$str\n').join();
      String headString = '\n';
      screenWords = headString + screenWords;

      await sendEvenAIReply(screenWords, 0x01, 0x50, 0);
      return;
    }

    if (list.length == 5) {
      String screenWords = list.sublist(0, 5).map((str) => '$str\n').join();

      await sendEvenAIReply(screenWords, 0x01, 0x50, 0);
      return;
    }
  }

  Future stopEvenAIByOS() async {
    isRunning = false;
    clear();

    await BleManager.instance.invokeMethod("stopEvenAI");
  }

  void clear() {
    isReceivingAudio = false;
    isRunning = false;
    _isManual = false;
    _currentLine = 0;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _timer?.cancel();
    _timer = null;
    audioDataBuffer.clear();
    audioDataBuffer = [];
    audioData = null;
    list = [];
    sendReplys = [];
    durationS = 0;
    retryCount = 0;
  }

  Future openEvenAIMic() async {
    final (micStartMs, isStartSucc) = await Proto.micOn(lr: "R"); 
debugPrint(
        '${DateTime.now()} openEvenAIMic---isStartSucc----$isStartSucc----micStartMs---$micStartMs---');
    
    if (!isStartSucc && isReceivingAudio && isRunning) {
      await Future.delayed(const Duration(seconds: 1));
      await openEvenAIMic();
    }
  }

  // Send text data to the glasses，including status information
  int retryCount = 0;
  Future<bool> sendEvenAIReply(
      String text, int type, int status, int pos) async {
    // todo
debugPrint('${DateTime.now()} sendEvenAIReply---text----$text-----type---$type---status---$status----pos---$pos-');
    if (!isRunning) {
      return false;
    }

    bool isSuccess = await Proto.sendEvenAIData(text,
        newScreen: EvenAIDataMethod.transferToNewScreen(type, status),
        pos: pos,
        current_page_num: getCurrentPage(),
        max_page_num: getTotalPages()); // todo pos
    if (!isSuccess) {
      if (retryCount < maxRetry) {
        retryCount++;
        await sendEvenAIReply(text, type, status, pos);
      } else {
        retryCount = 0;
        // todo
        return false;
      }
    }
    retryCount = 0;
    return true;
  }

  static void dispose() {
    _textStreamController.close();
  }
}

extension EvenAIDataMethod on EvenAI {
  static int transferToNewScreen(int type, int status) {
    int newScreen = status | type;
    return newScreen;
  }

  static List<String> measureStringList(String text, [double? maxW]) {
    final double maxWidth = maxW ?? 488; 
    const double fontSize = 21; // could be customized

    List<String> paragraphs = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    List<String> ret = [];

    TextStyle ts = const TextStyle(fontSize: fontSize);

    for (String paragraph in paragraphs) {
      final textSpan = TextSpan(text: paragraph, style: ts);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: null,
      );

      textPainter.layout(maxWidth: maxWidth);

      final lineCount = textPainter.computeLineMetrics().length;

      var start = 0;
      for (var i = 0; i < lineCount; i++) {
        final line = textPainter.getLineBoundary(TextPosition(offset: start));
        ret.add(paragraph.substring(line.start, line.end).trim());
        start = line.end;
      }
    }
    return ret;
  }
}


