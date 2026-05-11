// 文件路径：lib/view/selectBook/selectBook.dart
import 'package:english/controller/selectBook/selectBook.dart';
import 'package:english/widget/book_icon.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/home/home_v2.dart'; 

class SelectBookPage extends GetView<SelectBookController> {
  const SelectBookPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.arrow_back_ios, size: 20)),
        title: Text("我的自定义词库", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions:[
          IconButton(
            onPressed: () => Get.toNamed('/import'),
            icon: Icon(Icons.file_upload_outlined, color: isDark ? Colors.white : Colors.black),
          )
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          var customNames = controller.appService.wordService.customBookNames;
          if (customNames.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children:[
                  Icon(Icons.library_books_outlined, size: 64, color: isDark ? const Color(0xFF334155) : Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("暂无自定义词书\n点击右下角或右上角导入", textAlign: TextAlign.center, style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : Colors.grey, fontSize: 15)),
                ],
              ),
            );
          }
          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers:[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
                  child: Row(
                    children:[
                      Icon(Icons.person_pin_rounded, size: 20, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Text("我创建的词书", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B))),
                    ],
                  ),
                ),
              ),
              _buildBookSliverGrid(customNames),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddBookDialog(context, isDark),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("构建单词书", style: TextStyle(color: Colors.white)),
        backgroundColor: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
      ),
    );
  }

  Widget _buildBookSliverGrid(List<String> names) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            bool isDark = Theme.of(context).brightness == Brightness.dark;
            var name = names[index];
            var book = controller.bookMap[name];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onLongPress: () {
                  controller.showBookOptions(context, name, isDark);
                },
                onTap: () {
                  Get.back(); 
                  controller.appService.selectBook(name); 
                  if (Get.isRegistered<HomeControllerV2>()) Get.find<HomeControllerV2>().fetchInfo();
                  Get.snackbar("切换成功", "已切换至自定义词书《$name》");
                },
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children:[
                    Expanded(
                      child: FittedBox(
                        child: BookImage(
                          title: "自建", subTitle: name, color: Colors.blueGrey, fontColor: Colors.white,
                          wordCount: "词数:${book?.words?.length ?? 0}",
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(name, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            );
          },
          childCount: names.length,
        ),
      ),
    );
  }

  void showAddBookDialog(BuildContext context, bool isDark) {
    TextEditingController nameController = TextEditingController();
    TextEditingController wordsController = TextEditingController();

    Get.bottomSheet(
      Container(
        height: Get.height * 0.8,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                Text("构建自定义单词书", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                IconButton(onPressed: () => Get.back(), icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black))
              ],
            ),
            const SizedBox(height: 15),
            TextField(
              controller: nameController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: "词书名称",
                labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                filled: true, fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 15),
            Text(" 单词列表", style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF94A3B8) : Colors.grey)),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: wordsController,
                maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: "手动输入单词（一行一个，或用逗号隔开）\n或者点击下方按钮导入 TXT 文件",
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                  filled: true, fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children:[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      String? txtContent = await controller.pickTxtFile();
                      if (txtContent != null) wordsController.text = txtContent;
                    },
                    icon: Icon(Icons.file_upload, color: isDark ? Colors.white : Colors.black),
                    label: Text("导入 TXT", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: isDark ? Colors.white54 : Colors.black54)
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => controller.createCustomBook(nameController.text, wordsController.text),
                    child: const Text("确认生成", style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}