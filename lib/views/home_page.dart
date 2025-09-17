// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/views/even_list_page.dart';
import 'package:demo_ai_even/views/settings_page.dart';
import 'package:demo_ai_even/views/features/live_translate_page.dart';
import 'package:demo_ai_even/views/features_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? scanTimer;
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    BleManager.instance.setMethodCallHandler();
    BleManager.instance.startListening();
    BleManager.instance.onStatusChanged = _refreshPage;
  }

  void _refreshPage() => setState(() {});

  Future<void> _startScan() async {
    await BleManager.instance.startScan();
    _refreshPage();
  }

  // Removed unused _stopScan method

  Widget blePairedList() => Expanded(
        child: ListView.separated(
          separatorBuilder: (context, index) => const SizedBox(height: 5),
          itemCount: BleManager.instance.getPairedGlasses().length,
          itemBuilder: (context, index) {
            final glasses = BleManager.instance.getPairedGlasses()[index];
            return GestureDetector(
              onTap: () async {
                String channelNumber = glasses['channelNumber']!;
                await BleManager.instance.connectToGlasses("Pair_$channelNumber");
                _refreshPage();
              },
              child: Container(
                height: 72,
                padding: const EdgeInsets.only(left: 16, right: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pair: ${glasses['channelNumber']}'),
                        Text(
                            'Left: ${glasses['leftDeviceName']} \nRight: ${glasses['rightDeviceName']}'),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(icon: const Icon(Icons.settings), onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
            }),
          ],
          title: const Text('Even AI Demo'),
          /* DUPLICATE REMOVED BY PATCH >> /* DUPLICATE REMOVED BY PATCH >> actions: [
            InkWell(
              onTap: () {
debugPrint("To Features Page...");
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FeaturesPage()),
                );
              },
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: const Padding(
                padding:
                    EdgeInsets.only(left: 16, top: 12, bottom: 14, right: 16),
                child: Icon(Icons.menu),
              ),
            ),
          ], << */ << */
        ),
        body: Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () async {
                  if (BleManager.instance.getConnectionStatus() ==
                      'Not connected') {
                    _startScan();
                  }
                },
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: Text(BleManager.instance.getConnectionStatus(),
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              // Quick access buttons for testing
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveTranslatePage()));
                      },
                      child: const Text('Live Translate'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const FeaturesPage()));
                      },
                      child: const Text('Features'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (BleManager.instance.getConnectionStatus() == 'Not connected')
                blePairedList(),
              if (BleManager.instance.isConnected)
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      // todo
debugPrint("To AI History List...");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EvenAIListPage(),
                        ),
                      );
                    },
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.topCenter,
                      child: SingleChildScrollView(
                        child: StreamBuilder<String>(
                          stream: EvenAI.textStream,
                          initialData:
                              "Press and hold left TouchBar to engage Even AI.",
                          builder: (context, snapshot) => Obx(
                            () => EvenAI.isEvenAISyncing.value
                                ? const SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: CircularProgressIndicator(),
                                  ) // Color(0xFFFEF991)
                                : Text(
                                    snapshot.data ?? "Loading...",
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: BleManager.instance.isConnected
                                            ? Colors.black
                                            : Colors.grey.withValues(alpha: 0.5)),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    scanTimer?.cancel();
    isScanning = false;
    BleManager.instance.onStatusChanged = null;
    super.dispose();
  }
}






