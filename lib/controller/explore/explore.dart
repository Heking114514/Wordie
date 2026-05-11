// lib/controller/explore/explore.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../entity/word/vo/word.dart';
import '../../service/app/app.dart';
import '../home/home_v2.dart';
import '../main/main_controller.dart';

class ExploreController extends GetxController {
  final AppService appService = Get.find();
  var searchResult = <WordVO>[].obs;
  final TextEditingController searchInput = TextEditingController();

  void search(String q) {
    if (q.isEmpty) {
      searchResult.clear();
      return;
    }
    var results = appService.wordService.wordMap.values
        .where((w) => w.word!.toLowerCase().contains(q.toLowerCase()))
        .take(20)
        .map((e) => appService.toWordVO(e)!)
        .toList();
    searchResult.value = results;
  }

  void addToCustomLibrary(WordVO word) async {
    if (word.word == null) return;
    HapticFeedback.heavyImpact();

    List<String> customBooks = appService.wordService.customBookNames;

    if (customBooks.isEmpty) {
      await _addWordToSpecificLibrary(word.word!, "我的生词本");
      return;
    }

    bool isDark = Get.isDarkMode;

    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text("选择要加入的生词本", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: customBooks.map((bookName) => ListTile(
                      leading: Icon(Icons.library_books, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
                      title: Text(bookName, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      onTap: () async {
                        Get.back();
                        await _addWordToSpecificLibrary(word.word!, bookName);
                      },
                    )).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _addWordToSpecificLibrary(String spell, String bookName) async {
    var storage = GetStorage();
    Map<String, dynamic> customData = storage.read('custom_books') ?? {};

    List<String> words = List<String>.from(customData[bookName] ?? []);
    if (!words.contains(spell)) {
      words.add(spell);
      words.sort();
      customData[bookName] = words;
      await storage.write('custom_books', customData);

      if (storage.read('book_id_$bookName') == null) {
        await storage.write('book_id_$bookName', "c_${bookName.hashCode}");
      }

      await appService.wordService.loadCustomBooks();
      await appService.insertCustomBookToDb(bookName);

      Get.snackbar("收藏成功", "已加入《$bookName》");
    } else {
      Get.snackbar("提示", "《$bookName》中已存在该词");
    }
  }

  // 新增：专门处理系统词书的切换，并同步刷新首页
  void selectSystemBook(String bookName) {
    appService.selectBook(bookName);
    
    // 强制刷新主页数据
    if (Get.isRegistered<HomeControllerV2>()) {
      Get.find<HomeControllerV2>().fetchInfo();
    }
    
    // 通知框架切换回 首页(索引 0)
    if (Get.isRegistered<MainController>()) {
      Get.find<MainController>().changePage(0);
    }
    
    Get.snackbar("切换成功", "已切换至系统词书《$bookName》");
  }
}