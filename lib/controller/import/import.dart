// lib/controller/import/import.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import '../../dao/word/word.dart';
import '../../service/app/app.dart';
import '../../util/dictionary.dart';

class ImportController extends GetxController {
  final AppService appService = Get.find();
  final WordDao wordDao = Get.find<WordDao>();
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
    FilePickerResult? result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      List<String> lines = content.split(RegExp(r'[\r\n]+'));

      // 用 Set 去重，每次导入从空集合开始（不叠加已有 pendingWords）
      var tempSet = <String>{};
      for (var line in lines) {
        // 只取左边第一列（支持 tab、空格、逗号分隔的多列格式）
        String firstColumn = line.split(RegExp(r'[\t,\s]+'))[0].trim();
        // 过滤：必须包含至少一个英文字母
        if (firstColumn.isNotEmpty &&
            RegExp(r'[a-zA-Z]').hasMatch(firstColumn)) {
          tempSet.add(firstColumn.toLowerCase());
        }
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

    Get.dialog(const Center(child: CircularProgressIndicator()),
        barrierDismissible: false);

    // 替换模式：用导入内容覆盖旧列表，避免累积导致词数膨胀
    List<String> words = List<String>.from(pendingWords);
    int fetched = 0;

    for (var w in pendingWords) {
      if (appService.getWordBySpell(w) == null) {
        final word = await fetchWordDefinition(w);
        if (word != null) {
          // ==== 修复：使用 mergeFetchedWord 同时更新 wordMap 和 spellMap ====
          appService.wordService.mergeFetchedWord(word);
          fetched++;
        }
      }
    }

    words.sort();
    final rawBookId = await appService.replaceCustomBookWords(
      "raw words",
      words,
      preferredBookId: "1001",
    );

    // 重置该词书的学习进度（包括熟词），让重新导入的词可以正常学习
    await wordDao.clearBookProgressAll(rawBookId);
    await appService.clearReviewState(
      rawBookId,
      clearStats: true,
      clearPreferences: true,
    );

    Get.back();
    Get.back();
    Get.snackbar(
        "成功",
        "已导入 ${pendingWords.length} 个单词" +
            (fetched > 0 ? "（其中 $fetched 个从网络获取释义）" : ""));
  }
}
