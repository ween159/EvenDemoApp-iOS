import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class EvenAIListPage extends StatefulWidget {
  const EvenAIListPage({super.key});

  @override
  _EvenAIListPageState createState() => _EvenAIListPageState();
}

class _EvenAIListPageState extends State<EvenAIListPage> {
  late EvenaiModelController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.find<EvenaiModelController>();
debugPrint("controller.items--------${controller.items.length}");
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        title: const Text('History',
            style: TextStyle(fontSize: 20)),
    ),
    body: Obx(() {
      if (controller.items.isEmpty && !EvenAI.isEvenAISyncing.value) {
        return const Center(
          child: Text(
            "Press and hold left TouchBar to engage Even AI.",
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        );
      } else {

          return Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: controller.items.length,
                      itemBuilder: (context, index) {
                      return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (controller.selectedIndex.value ==
                                    index) {
                                  controller.deselectItem();
                                } else {
                                  controller.selectItem(index);
                                }
                              });
                            },
                            child: controller.selectedIndex.value == index
                                    ? buildItemDetail(index)
                                    : buildItem(index),
                          );
                      },
                    ),
                  ),
                ],
              ),
            );
      }
    }),
  );


  Widget buildItem(int index) {
    final item = controller.items[index];
    return  Expanded(
              child: Container(
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF991).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(5),
                ),
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    item.title,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            );
  }

  Widget buildItemDetail(int index) {
    final item = controller.items[index];

    return  Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF991).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(5),
                ),
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                child: Column(
                  children: [
                    Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.all(16),
                      child: Text(item.title,
                               style: const TextStyle(fontSize: 20),
                          ),
                    ),
                    Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        item.content,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 16)
                  ],
                ),
              ),
            );
  }
}



