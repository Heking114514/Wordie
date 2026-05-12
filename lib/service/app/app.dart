import 'dart:convert';
import 'dart:typed_data';

import 'package:english/dao/word/word.dart';
import 'package:english/dicts/reader.dart';
import 'package:english/service/word/word.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../entity/word/po/word.dart';
import '../../entity/word/vo/word.dart';
import '../../controller/home/home_v2.dart';
import '../../controller/main/main_controller.dart';

class AppService {
  WordService wordService = Get.find();
  var wordDao = Get.find<WordDao>();
  var queueCount = 4;
  int dailyWantCount = 100;
  bool autoPass = false;
  bool autoPlayVoice = true;
  String? _bookName;

  String get bookName {
    return _bookName ?? wordService.bookNames[0];
  }

  String getBookId(String? bookName) {
    return wordService.bookMap[bookName]?.id ?? "2";
  }

  int get bookId {
    return int.parse(getBookId(_bookName));
  }

  String getStudyMode(int bId) {
    return GetStorage().read('study_mode_$bId') ?? 'manual';
  }

  void setStudyMode(int bId, String mode) {
    GetStorage().write('study_mode_$bId', mode);
  }

  void promptAndSelectBook(String bName) {
    int bId = int.tryParse(getBookId(bName)) ?? 0;
    String? existingMode = GetStorage().read('study_mode_$bId');

    if (existingMode != null) {
      _executeSelectBook(bName, existingMode);
    } else {
      // need context for isDark — obtain from Get
      final context = Get.context;
      if (context != null) {
        showModeSelectionDialog(bName, bId, context);
      } else {
        _executeSelectBook(bName, 'manual');
      }
    }
  }

  void showModeSelectionDialog(String bName, int bId, BuildContext context, {bool isReselect = false}) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text(isReselect ? "重新选择播放模式" : "选择《$bName》的播放模式", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 8),
            Text("后续可长按词书卡片重新配置", style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 25),
            _buildModeCard(
              title: "手动沉浸模式 (推荐)",
              desc: "看英文回想释义，点击屏幕揭晓并自动发音，自主控制进度。",
              icon: Icons.touch_app_rounded,
              color: const Color(0xFF6366F1),
              isDark: isDark,
              onTap: () {
                setStudyMode(bId, 'manual');
                Get.back();
                _executeSelectBook(bName, 'manual', isReselect: isReselect);
              }
            ),
            const SizedBox(height: 15),
            _buildModeCard(
              title: "自动循环模式",
              desc: "传统分组记忆。按设定数量分组，自动轮播发音与释义。",
              icon: Icons.autorenew_rounded,
              color: const Color(0xFF10B981),
              isDark: isDark,
              onTap: () {
                setStudyMode(bId, 'auto');
                Get.back();
                _executeSelectBook(bName, 'auto', isReselect: isReselect);
              }
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({required String title, required String desc, required IconData icon, required Color color, required bool isDark, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54, height: 1.4)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _executeSelectBook(String bName, String mode, {bool isReselect = false}) {
    if (isReselect) Get.back(); // close selectBook page
    selectBook(bName);
    if (Get.isRegistered<HomeControllerV2>()) Get.find<HomeControllerV2>().fetchInfo();
    if (Get.isRegistered<MainController>()) Get.find<MainController>().changePage(0);
    Get.snackbar("配置完成", "当前词书:《$bName》\n播放模式: ${mode == 'manual' ? '手动沉浸' : '自动循环'}");
  }

  int thinkWaitTime = 1;
  int readWaitTime = 7;

  List<int> get reviewTimes {
    int minutes = 60 * 1000;
    int hour = 60 * minutes;
    int day = 24 * 60 * 60 * 1000;
    int month = 30 * day;
    return [
      5 * minutes, 25 * minutes, hour,
      1 * day - hour, 1 * day - hour, 2 * day - hour, 3 * day - hour,
      8 * day - hour, month - 15 * day - hour, 1 * month - hour,
      2 * month - hour, 3 * month - hour, 8 * month - hour,
      15 * month - hour,
    ];
  }

  int get wordCount {
    return wordService.bookMap[bookName]?.words?.length ?? 0;
  }

  Future<void> insertCustomBookToDb(String customBookName) async {
    var book = wordService.bookMap[customBookName];
    if (book != null && book.words != null) {
      int bId = int.tryParse(book.id ?? '0') ?? 0;
      if (bId != 0) {
        await wordDao.deleteBookWords(bId);
      }
      var wordPOs = book.words!.map((e) => WordPO(word: e.id, book: book.id)).toList();
      if (wordPOs.isNotEmpty) await wordDao.addWords(wordPOs);
    }
  }

  Future<void> readWords() async {
    await wordService.loadWords();
  }

  Future<void> insertToDb() async {
    if (bookLoaded()) return;
    wordDao.clearWord();
    for (var book in wordService.bookMap.values) {
      var words = book.words;
      if (words != null) {
        var wordPOs = words.map((e) => WordPO(word: e.id, book: book.id)).toList();
        await wordDao.addWords(wordPOs);
      }
    }
    setBookLoaded();
  }

  bool bookLoaded() {
    return GetStorage().read("book-loaded") == "true";
  }

  void setBookLoaded() {
    GetStorage().write("book-loaded", "true");
  }

  int reviewDailyCount = 50;

  void saveOptions() {
    var storage = GetStorage();
    storage.write("study.dailyWantCount", dailyWantCount);
    storage.write("study.thinkWaitTime", thinkWaitTime);
    storage.write("study.readWaitTime", readWaitTime);
    storage.write("study.queueCount", queueCount);
    storage.write("study.bookName", bookName);
    storage.write("study.autoPass", autoPass ? "true" : "false");
    storage.write("study.reviewDailyCount", reviewDailyCount);
    storage.write('auto_play', autoPlayVoice);
  }

  void readOptions() {
    var storage = GetStorage();
    dailyWantCount = int.parse((storage.read("study.dailyWantCount") ?? "100").toString());
    thinkWaitTime = int.parse((storage.read("study.thinkWaitTime") ?? "1").toString());
    readWaitTime = int.parse((storage.read("study.readWaitTime") ?? "7").toString());
    queueCount = int.parse((storage.read("study.queueCount") ?? "4").toString());
    _bookName = storage.read("study.bookName");
    autoPass = storage.read("autoPass").toString() == "true";
    reviewDailyCount = int.parse((storage.read("study.reviewDailyCount") ?? "50").toString());
    autoPlayVoice = storage.read('auto_play') ?? true;
  }

  Word? getWord(String? id) => wordService.wordMap[id];

  Word? getWordBySpell(String? spell) {
    var find = wordService.wordMap.values.firstWhere((element) => element.word == spell, orElse: () => Word());
    if (find.id == null) return null;
    return find;
  }

  WordVO? getWordVO(String? id) => toWordVO(wordService.wordMap[id]);

  WordVO? toWordVO(Word? word) {
    if (word != null) {
      return WordVO(
        wordId: word.id, word: word.word, usaVoice: word.usVoice, ukVoice: word.ukVoice,
        means: word.means?.split("\n"),
        sentence: () { var len = word.sentences?.length ?? 0; if (len > 0) return word.sentences?[0].sentence; }(),
        sentenceMeans: () { var len = word.sentences?.length ?? 0; if (len > 0) return word.sentences?[0].sentenceCn; }(),
      );
    }
    return null;
  }

  void selectBook(String bookName) {
    _bookName = bookName;
    saveOptions();
  }

  Future<bool?> queryWordDeleteStatus(String? word) async {
    var status = await wordDao.queryWordStatus(word ?? "");
    return status?.status == -1;
  }

  Future<void> deleteWord(String? wordId) async => await wordDao.upsetWordStatusById(wordId, -1);
  Future<void> restoreWord(String? wordId) async => await wordDao.upsetWordStatusById(wordId, 0);
}
