// lib/controller/import/import.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../service/app/app.dart';
import '../../util/dictionary.dart';

class ImportController extends GetxController {
  final AppService appService = Get.find();
  var pendingWords = <String>[].obs;
  final TextEditingController textController = TextEditingController();

  void addSingleWord() {
    String word = textController.text.trim().toLowerCase();
    if (word.isNotEmpty) {
      if (!pendingWords.contains(word)) {
        pendingWords.add(word);
        // ==== 修复：加入单词时立即重排序 ====
        pendingWords.sort();
        textController.clear();
      }
    }
  }

  Future<void> pickAndReadTxt() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      List<String> lines = content.split(RegExp(r'[\r\n,]+'));
      
      // ==== 修复：用 Set 强行去重，转换回 List 并执行字典序排列 ====
      var tempSet = pendingWords.toSet();
      for (var line in lines) {
        if (line.trim().isNotEmpty) tempSet.add(line.trim().toLowerCase());
      }
      var sortedList = tempSet.toList()..sort();
      pendingWords.value = sortedList;
    }
  }

  Future<void> confirmImport() async {
    if (pendingWords.isEmpty) {
      Get.snackbar("提示", "列表为空");
      return;
    }

    Get.dialog(const Center(child: CircularProgressIndicator()), barrierDismissible: false);

    var storage = GetStorage();
    Map<String, dynamic> customData = storage.read('custom_books') ?? {};
    List<String> words = List<String>.from(customData["raw words"] ?? []);
    bool changed = false;
    int fetched = 0;

    for (var w in pendingWords) {
      if (!words.contains(w)) {
        words.add(w);
        changed = true;
      }
      if (appService.getWordBySpell(w) == null) {
        final word = await fetchWordDefinition(w);
        if (word != null) {
          appService.wordService.wordMap[word.id!] = word;
          fetched++;
        }
      }
    }

    if (changed) {
      words.sort();
      customData["raw words"] = words;
      await storage.write('custom_books', customData);
      if (storage.read('book_id_raw words') == null) {
        await storage.write('book_id_raw words', "1001");
      }
      await appService.wordService.loadCustomBooks();
      await appService.insertCustomBookToDb("raw words");
    }

    Get.back();
    Get.back();
    Get.snackbar("成功", "已导入 ${pendingWords.length} 个单词" + (fetched > 0 ? "（其中 $fetched 个从网络获取释义）" : ""));
  }
}