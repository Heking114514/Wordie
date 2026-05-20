// lib/view/selectBook/selectBook.dart
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
      ),
      body: SafeArea(
        child: Obx(() {
          var customNames = controller.appService.wordService.customBookNames;
          if (customNames.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_books_outlined, size: 64, color: isDark ? const Color(0xFF334155) : Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("暂无自定义词书\n点击右下角按钮开始构建", textAlign: TextAlign.center, style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : Colors.grey, fontSize: 15)),
                ],
              ),
            );
          }
          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
                  child: Row(
                    children: [
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
        label: const Text("构建单词书", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF407BFF),
        elevation: 4,
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
                  controller.appService.promptAndSelectBook(name);
                },
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FittedBox(
                        child: Obx(() {
                          int count = controller.validWordCounts[name] ?? (book?.words?.length ?? 0);
                          return BookImage(
                            title: "自建", subTitle: name, color: Colors.blueGrey, fontColor: Colors.white,
                            wordCount: "词数:$count",
                          );
                        }),
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
        height: Get.height * 0.88,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF6F8FC),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("构建自定义单词书", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close, color: Colors.grey))
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16, offset: const Offset(0, 4))]
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("新词书名称", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1D2129))),
                          const SizedBox(height: 12),
                          TextField(
                            controller: nameController,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              hintText: "给你的词库起个酷名字",
                              hintStyle: const TextStyle(color: Color(0xFFC9CDD4), fontSize: 14),
                              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF9FAFD),
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E6EB))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF407BFF))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16, offset: const Offset(0, 4))]
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("单词列表", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1D2129))),
                              GestureDetector(
                                onTap: () async {
                                  String? txtContent = await controller.pickTxtFile();
                                  if (txtContent != null) wordsController.text = txtContent;
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(color: const Color(0xFF407BFF).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: const Text("导入 TXT 文件", style: TextStyle(fontSize: 13, color: Color(0xFF407BFF), fontWeight: FontWeight.bold)),
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: wordsController,
                            maxLines: 8,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              hintText: "手动输入单词\n（每行一个，或用逗号隔开）\n例如：\napple\nbanana",
                              hintStyle: const TextStyle(color: Color(0xFFC9CDD4), fontSize: 14),
                              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF9FAFD),
                              filled: true,
                              contentPadding: const EdgeInsets.all(14),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E6EB))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF407BFF))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    Container(
                      height: 50,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(colors: [Color(0xFF407BFF), Color(0xFF598BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        boxShadow: [BoxShadow(color: const Color(0xFF407BFF).withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 6))]
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        onPressed: () => controller.createCustomBook(nameController.text, wordsController.text),
                        child: const Text("确认生成并保存", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}
