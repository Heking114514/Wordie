import 'dart:math';
import 'package:english/dao/word/word.dart';
import 'package:english/dicts/reader.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../util/quotes.dart';

class HomeControllerV2 extends GetxController {
  var studyTime = 0.0.obs;
  var reviewCount = 0.obs;
  var dailyWordCount = 0.obs;
  var progress = "0 / 0".obs;
  var progressPercent = 0.0.obs;
  var wordBook = "加载中...".obs;
  var username = "".obs;
  var isBookValid = true.obs;

  var currentQuote = "坚持就是胜利！".obs;
  var streakDays = 0.obs;
  var dailyWord = Rx<WordVO?>(null);

  AppService appService = Get.find();
  var wordDao = Get.find<WordDao>();

  var tempReviewCount = 20.obs;
  var tempReviewCycles = 3.obs;
  var tempReviewBook = ''.obs;

  String get greeting {
    var hour = DateTime.now().hour;
    if (hour < 5) return "夜深了";
    if (hour < 11) return "早上好";
    if (hour < 14) return "中午好";
    if (hour < 19) return "下午好";
    return "晚上好";
  }

  @override
  void onInit() {
    super.onInit();
    _loadDailyWordFromStorage();
    currentQuote.value = getRandomQuote();
    fetchInfo();
    fetchDailyWord();
  }

  void _loadDailyWordFromStorage() {
    final storage = GetStorage();
    final today = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    final savedDate = storage.read('daily_word_date') ?? '';
    if (savedDate == today) {
      final word = storage.read('daily_word_word') ?? '';
      if (word.isNotEmpty) {
        dailyWord.value = WordVO(
          wordId: storage.read('daily_word_id') ?? '',
          word: word,
          ukVoice: storage.read('daily_word_uk') ?? '',
          usaVoice: storage.read('daily_word_us') ?? '',
          means: (storage.read('daily_word_means') as String? ?? '').split('\n'),
          sentence: storage.read('daily_word_sentence'),
          sentenceMeans: storage.read('daily_word_sentence_means'),
        );
        _lastDailyWordDate = today;
      }
    }
  }

  void toStudyNew() async {
    if (!isBookValid.value) {
      Get.snackbar("提示", "当前词书已失效，请重新选择一本词书");
      return;
    }
    await Get.toNamed("/study?mode=new");
    await const Duration(milliseconds: 500).delay();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
    fetchInfo();
  }

  void startReview() {
    // check for active batch on current book
    int bId = appService.bookId;
    var savedBatch = GetStorage().read('review_batch_$bId');
    var savedPos = GetStorage().read('review_batch_pos_$bId') ?? 0;
    if (savedBatch != null && savedBatch is List && savedBatch.isNotEmpty && (savedPos as int) < savedBatch.length) {
      // active batch exists, go straight to review
      toReview();
      return;
    }
    // no active batch, show settings
    showReviewSettingsDialog();
  }

  void toReview() async {
    if (!isBookValid.value) {
      Get.snackbar("提示", "当前词书已失效，请重新选择一本词书");
      return;
    }
    await Get.toNamed("/study?mode=review");
    await const Duration(milliseconds: 500).delay();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
    fetchInfo();
  }

  void showReviewSettingsDialog() async {
    tempReviewCount.value = appService.reviewDailyCount;
    int cycles = GetStorage().read('review_cycles_${appService.bookId}') ?? 3;
    tempReviewCycles.value = cycles;
    bool isDark = Get.isDarkMode;

    // only show books with review progress
    var allBooks = <String>[];
    for (var name in appService.wordService.systemBookNames) {
      int c = await _getReviewCountForBook(name);
      if (c > 0) allBooks.add(name);
    }
    for (var name in appService.wordService.customBookNames) {
      int c = await _getReviewCountForBook(name);
      if (c > 0) allBooks.add(name);
    }
    if (allBooks.isEmpty) {
      Get.snackbar("提示", "暂无有复习进度的词书，先去学习吧");
      return;
    }
    tempReviewBook.value = allBooks.contains(appService.bookName) ? appService.bookName : allBooks.first;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Text("复习设置", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 15),
            Text("复习模式已固定为：手动沉浸模式", style: TextStyle(fontSize: 13, color: const Color(0xFF6366F1), fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Text("选择要复习的词书", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Obx(() => DropdownButton<String>(
                value: allBooks.contains(tempReviewBook.value) ? tempReviewBook.value : allBooks.first,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15),
                items: allBooks.map((b) => DropdownMenuItem(
                  value: b,
                  child: Text(b, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                )).toList(),
                onChanged: (v) {
                  if (v != null) tempReviewBook.value = v;
                },
              )),
            ),
            Obx(() {
              final book = appService.wordService.bookMap[tempReviewBook.value];
              if (book == null) return const SizedBox.shrink();
              return FutureBuilder<int>(
                key: ValueKey(tempReviewBook.value),
                future: _getReviewCountForBook(tempReviewBook.value),
                builder: (ctx, snap) {
                  final count = snap.data ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 5),
                    child: Text("该词书有 $count 个待复习词汇", style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                  );
                },
              );
            }),
            Obx(() => _buildSettingRow("每批复习数量", tempReviewCount.value,[10, 20, 30, 50], (v) {
              tempReviewCount.value = v;
            }, isDark)),
            Obx(() => _buildSettingRow("滚动次数", tempReviewCycles.value,[1, 2, 3], (v) {
              tempReviewCycles.value = v;
            }, isDark)),
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  appService.reviewDailyCount = tempReviewCount.value;
                  GetStorage().write('review_target_${appService.getBookId(tempReviewBook.value)}', tempReviewCount.value);
                  GetStorage().write('review_cycles_${appService.getBookId(tempReviewBook.value)}', tempReviewCycles.value);
                  if (tempReviewBook.value != appService.bookName) {
                    appService.selectBook(tempReviewBook.value);
                    fetchInfo();
                  }
                  Get.back();
                  toReview();
                },
                child: const Text("开始复习", style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            )
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<int> _getReviewCountForBook(String bookName) async {
    var book = appService.wordService.bookMap[bookName];
    if (book == null) return 0;
    int bId = int.tryParse(book.id ?? '0') ?? 0;
    if (bId == 0) return 0;
    var statuses = await wordDao.queryWordStatusByBook(bId);
    int count = 0;
    for (var s in statuses) {
      if (s.status == 1) count++;
    }
    return count;
  }

  Widget _buildSettingRow(String title, int currentValue, List<int> options, Function(int) onChanged, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children:[
          Text(title, style: TextStyle(fontSize: 16, color: isDark ? Colors.white70 : Colors.black87)),
          DropdownButton<int>(
            value: options.contains(currentValue) ? currentValue : options.first,
            items: options.map((e) => DropdownMenuItem(value: e, child: Text("$e", style: TextStyle(color: isDark ? Colors.white : Colors.black)))).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            underline: const SizedBox(),
            icon: Icon(Icons.arrow_drop_down, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
            dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          ),
        ],
      ),
    );
  }

  void fetchInfo() async {
    username.value = GetStorage().read('profile_name') ?? "学习者 001";
    wordBook.value = appService.bookName;
    await appService.readWords();

    isBookValid.value = appService.wordService.bookMap.containsKey(appService.bookName);
    if (!isBookValid.value) {
      progress.value = "0 / 0";
      progressPercent.value = 0.0;
      dailyWordCount.value = 0;
      reviewCount.value = 0;
      studyTime.value = 0.0;
      return;
    }

    var book = appService.wordService.bookMap[appService.bookName];
    var statuses = await wordDao.queryWordStatusByBook(appService.bookId);

    int deleted = 0;
    int learned = 0;
    int reviewing = 0;
    for (var s in statuses) {
      if (s.status == -1) deleted++;
      if (s.status != -1 && (s.status == 1 || (s.studyCycle ?? 0) > 0)) learned++;
      if (s.status == 1) reviewing++;
    }

    int allCount = (book?.words?.length ?? 0) - deleted;
    int progressCount = learned;

    progress.value = "$progressCount / $allCount";
    progressPercent.value = allCount > 0 ? progressCount / allCount : 0.0;
    if(progressPercent.value > 1.0) progressPercent.value = 1.0;

    dailyWordCount.value = await wordDao.queryDailyPassWordCount() ?? 0;
    reviewCount.value = reviewing;
    studyTime.value = ((await wordDao.queryStudyTime()) ?? 0) / 1000 / 60;

    calculateStreakDays();
  }

  void calculateStreakDays() async {
    var records = await wordDao.queryAllStudyTimeRecords();
    if (records.isEmpty) {
      streakDays.value = 0;
      return;
    }

    Map<String, int> dailyTime = {};
    for (var r in records) {
      if (r.startTime != null && r.endTime != null) {
        var date = DateTime.fromMillisecondsSinceEpoch(r.startTime!);
        String dateKey = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
        dailyTime[dateKey] = (dailyTime[dateKey] ?? 0) + (r.endTime! - r.startTime!);
      }
    }

    int streak = 0;
    DateTime checkDate = DateTime.now();
    String todayKey = "${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}";
    if ((dailyTime[todayKey] ?? 0) >= 600000) streak++;

    checkDate = checkDate.subtract(const Duration(days: 1));
    while (true) {
      String key = "${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}";
      if ((dailyTime[key] ?? 0) >= 600000) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    streakDays.value = streak;
  }

  String _lastDailyWordDate = '';

  void fetchDailyWord() async {
    final today = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    if (_lastDailyWordDate == today && dailyWord.value != null) return;

    await appService.readWords();

    var book = appService.wordService.bookMap["MBA词汇"];
    if (book == null || book.words == null || book.words!.isEmpty) {
      try {
        book = appService.wordService.bookMap.values.firstWhere(
          (b) => b.words != null && b.words!.isNotEmpty,
        );
      } catch (e) {
        book = null;
      }
    }

    if (book != null && book.words != null && book.words!.isNotEmpty) {
      var words = book.words!;
      var difficultWords = words.where((w) => (w.word?.length ?? 0) > 5).toList();

      WordVO? picked;
      if (difficultWords.isNotEmpty) {
        var randomIndex = Random().nextInt(difficultWords.length);
        picked = appService.toWordVO(difficultWords[randomIndex]);
      } else {
        var randomIndex = Random().nextInt(words.length);
        picked = appService.toWordVO(words[randomIndex]);
      }

      if (picked != null) {
        dailyWord.value = picked;
        _lastDailyWordDate = today;

        final storage = GetStorage();
        storage.write('daily_word_date', today);
        storage.write('daily_word_id', picked.wordId ?? '');
        storage.write('daily_word_word', picked.word ?? '');
        storage.write('daily_word_uk', picked.ukVoice ?? '');
        storage.write('daily_word_us', picked.usaVoice ?? '');
        storage.write('daily_word_means', (picked.means ?? []).join('\n'));
        storage.write('daily_word_sentence', picked.sentence ?? '');
        storage.write('daily_word_sentence_means', picked.sentenceMeans ?? '');
      }
    }
  }

  void refreshDailyWord() {
    _lastDailyWordDate = '';
    fetchDailyWord();
  }
}