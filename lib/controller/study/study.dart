import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/ai/openai_responses.dart';
import 'package:english/service/app/app.dart';
import 'package:english/service/study/study.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock/wakelock.dart';
import 'package:get_storage/get_storage.dart';

import '../../entity/word/po/word.dart';
import '../../dicts/reader.dart';
import '../../util/audio.dart';
import '../../util/dictionary.dart';
import '../../controller/selectBook/selectBook.dart';

typedef Future<void> PlayCallback(Player player);

class Player {
  bool _start = false;
  bool _playing = false;

  int showTime;
  int thinkTime;
  int startTime = DateTime.now().millisecondsSinceEpoch;
  int? stopTime;
  WordStatusPO? wordStatus;
  PlayCallback thinkStart;
  PlayCallback thinkEnd;
  PlayCallback showStart;
  PlayCallback showEnd;
  PlayCallback onEnd;
  bool playComplete = true;

  Player.create({
    required this.thinkStart,
    required this.thinkEnd,
    required this.showStart,
    required this.showEnd,
    required this.onEnd,
    this.showTime = 7,
    this.thinkTime = 3,
  }) {
    start();
  }

  void start() async {
    if (!_start) {
      for (;;) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_playing == false) break;
      }
      _start = true;
      _playing = true;
      _loop();
    }
  }

  void stop() async {
    if (_start == false) return;
    stopTime = DateTime.now().millisecondsSinceEpoch;
    _start = false;
    for (;;) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_playing == false) break;
    }
  }

  void _loop() async {
    for (; _start;) {
      startTime = DateTime.now().millisecondsSinceEpoch;
      playComplete = true;
      if (_start) await thinkStart(this);
      if (_start) await Future.delayed(Duration(seconds: thinkTime));
      if (_start) await thinkEnd(this);
      if (_start) await showStart(this);
      if (_start) await Future.delayed(Duration(seconds: showTime));
      if (_start) await showEnd(this);
      if (!_start) playComplete = false;
      await onEnd(this);
    }
    _playing = false;
    _start = false;
  }
}

class _StudyTimeRecorder {
  int? startTime;
  int? endTime;
  StudyService service;

  void recordStart() {
    startTime = DateTime.now().millisecondsSinceEpoch;
  }

  void recordEnd() {
    if (startTime == null) return;
    endTime = DateTime.now().millisecondsSinceEpoch;
    service.addStudyRecord(startTime!, endTime!);
    startTime = DateTime.now().millisecondsSinceEpoch;
  }

  _StudyTimeRecorder({this.startTime, this.endTime, required this.service});
}

class StudyController extends GetxController with WidgetsBindingObserver {
  var word = Rx<WordVO?>(null);
  var dailyStudyCount = 0.obs;
  var reviewCount = 0.obs;
  var thinking = false.obs;
  var playing = false.obs;
  var controlEnable = true.obs;
  var playButtonEnable = true.obs;

  var playingIndex = 0;
  var playingWords = <WordVO>[];
  var bookWordStatusMap = <String, WordStatusPO?>{};
  final _sessionPassedIds = <String>{};

  var timeRecord = _StudyTimeRecorder(service: Get.find());
  var sessionPassCount = 0.obs;
  var bookLearnedCount = 0.obs;
  var bookTotalCount = 0.obs;
  var isInitializing = true.obs;

  // 新增：AI 文章相关的状态
  var aiArticle = "".obs;
  var isGeneratingArticle = false.obs;
  String _cachedArticleBatchKey = ""; // 标识当前缓存对应的复习批次
  CancelToken? _articleCancelToken;

  String get _articleStorageKey => 'ai_article_cache_${appService.bookId}';
  String get _manualStudyCursorKey =>
      'study_cursor_manual_${appService.bookId}_new';
  String get _manualStudyCursorMigrationKey =>
      'study_cursor_manual_${appService.bookId}_new_initialized';

  String _wordStatusKey(String wordId) => '${appService.bookId}_$wordId';

  bool _isLearnedStatus(WordStatusPO? status) {
    if (status == null || (status.status ?? 0) < 0) return false;
    return status.status == 1 || (status.studyCycle ?? 0) > 0;
  }

  String _currentReviewBatchKey() {
    var storage = GetStorage();
    String key = storage.read('review_batch_key_${appService.bookId}') ?? '';
    if (key.isEmpty && playingWords.isNotEmpty) {
      key =
          '${appService.bookId}:${playingWords.map((e) => e.wordId ?? '').join(',')}';
      storage.write('review_batch_key_${appService.bookId}', key);
    }
    return key;
  }

  List<String> _articleWords() {
    var seen = <String>{};
    return playingWords
        .map((e) => (e.word ?? '').trim())
        .where((word) => word.isNotEmpty && seen.add(word.toLowerCase()))
        .toList();
  }

  String _boldTargetWords(String text, List<String> words) {
    if (text.isEmpty || words.isEmpty) return text;

    var alternatives = words.map(RegExp.escape).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var targetPattern = RegExp(
      r"(^|[^A-Za-z'])(" + alternatives.join('|') + r")(?=$|[^A-Za-z'])",
      caseSensitive: false,
    );

    // Odd segments are already inside **...** and must not be wrapped again.
    var markdownSegments = text.split('**');
    for (int i = 0; i < markdownSegments.length; i += 2) {
      markdownSegments[i] = markdownSegments[i].replaceAllMapped(
        targetPattern,
        (match) => '${match.group(1)}**${match.group(2)}**',
      );
    }
    return markdownSegments.join('**');
  }

  var isManualMode = false.obs;
  var isRevealed = false.obs;

  var isDifficultMode = false.obs;
  List<WordVO> _backupPlayingWords = [];
  int _backupPlayingIndex = 0;
  bool _backupIsManualMode = false;

  var reviewDailyCount = 50.obs;

  // 复习轮次过渡
  int _lastReviewRound = 1;
  var reviewRoundInfo = "".obs; // 非空时显示过渡提示

  AppService appService = Get.find();
  StudyService studyService = StudyService();
  WordDao wordDao = Get.find();
  Player? player;
  var wordStatus = Rx<WordStatusPO?>(null);

  var studyTime = "0分钟".obs;
  var dailyWantCount = 0.obs;
  var thinkWaitTime = 1.obs;
  var readWaitTime = 7.obs;
  var queueCount = 4.obs;
  var autoPass = false.obs;
  var playCount = <String, int>{};

  get autoRotating => false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      timeRecord.recordStart();
    } else if (state == AppLifecycleState.paused) {
      stopPlay();
      timeRecord.recordEnd();
    }
  }

  @override
  void onInit() {
    super.onInit();
    _init();
    WidgetsBinding.instance?.addObserver(this);
    timeRecord.recordStart();
    Wakelock.enable();
  }

  void _init() async {
    isInitializing.value = true;
    _articleCancelToken?.cancel('review batch changed');
    _articleCancelToken = null;
    isGeneratingArticle.value = false;

    String modeParam = Get.parameters['mode'] ?? 'new';

    await fetchOptions();

    if (modeParam == 'review') {
      isManualMode.value = true;
    } else {
      isManualMode.value =
          appService.getStudyMode(appService.bookId) == 'manual';
    }

    await fetchWords();

    // 文章缓存：从 GetStorage 恢复，仅在批次变化时清空
    if (modeParam != 'review') {
      aiArticle.value = "";
      _cachedArticleBatchKey = "";
    } else {
      String currentBatchKey = _currentReviewBatchKey();
      var cached = GetStorage().read(_articleStorageKey);
      String savedBatchKey = cached is Map ? '${cached['batchKey'] ?? ''}' : '';
      if (currentBatchKey == savedBatchKey && savedBatchKey.isNotEmpty) {
        // 同一批次，恢复缓存的文章
        aiArticle.value = _boldTargetWords(
          '${cached['article'] ?? ''}',
          _articleWords(),
        );
        _cachedArticleBatchKey = currentBatchKey;
      } else {
        // 新批次，清空
        aiArticle.value = "";
        _cachedArticleBatchKey = currentBatchKey;
        GetStorage().remove(_articleStorageKey);
      }
    }

    // ==== 修复：新词模式下 playingWords 为空时，尝试重新同步数据 ====
    if (playingWords.isEmpty && modeParam != 'review') {
      // 尝试重新将当前词书写入数据库并重新获取
      try {
        await appService.insertCustomBookToDb(appService.bookName);
        if (isManualMode.value) {
          playingWords = await studyService.fetchAllBookWords();
        } else {
          playingWords =
              await studyService.fetchStudyQueueWords(appService.queueCount);
          playingIndex = 0;
        }
        if (playingWords.isNotEmpty) {
          bookWordStatusMap = await studyService.fetchBookWordStatusMap();
          if (isManualMode.value) _restorePosition();
        }
      } catch (_) {}
    }

    if (playingWords.isEmpty) {
      if (modeParam == 'review') {
        isInitializing.value = false;
        Get.offAllNamed("/main");
        Get.snackbar("今日无需复习", "今天还没有学习新词，先去学一些吧",
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      // 新词模式：词书确实为空，直接回到首页并提示
      isInitializing.value = false;
      Get.offAllNamed("/main");
      Get.snackbar("提示", "当前词书没有可学习的单词，请检查词书是否已导入或已学完",
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    await fetchCount();

    if (isManualMode.value) {
      _loadManualWord();
    } else {
      await startPlay();
    }

    isInitializing.value = false;

    if (modeParam == 'review' && aiArticle.value.isEmpty) {
      generateArticle();
    }
  }

  Future<void> fetchOptions() async {
    appService.readOptions();
    thinkWaitTime.value = appService.thinkWaitTime;
    readWaitTime.value = appService.readWaitTime;
    queueCount.value = appService.queueCount;
    autoPass.value = appService.autoPass;

    autoPass.listen((value) {
      appService.autoPass = value;
      appService.saveOptions();
    });
    thinkWaitTime.listen((value) {
      appService.thinkWaitTime = value;
      appService.saveOptions();
    });
    readWaitTime.listen((value) {
      appService.readWaitTime = value;
      appService.saveOptions();
    });
    queueCount.listen((value) {
      appService.queueCount = value;
      appService.saveOptions();
    });

    reviewDailyCount.value = appService.reviewDailyCount;
    reviewDailyCount.listen((value) {
      appService.reviewDailyCount = value;
      appService.saveOptions();
    });
  }

  @override
  void onClose() {
    _articleCancelToken?.cancel('controller closed');
    _articleCancelToken = null;
    Wakelock.disable();
    timeRecord.recordEnd();
    WidgetsBinding.instance?.removeObserver(this);
    stopPlay();
    super.onClose();
  }

  void reloadStudy() => _init();

  void restartBook(String orderPref) async {
    await wordDao.clearBookProgressAll(appService.bookId); // 彻底重置，包括熟词
    GetStorage().write('book_order_${appService.bookId}', orderPref);
    GetStorage().write('study_cursor_${appService.bookId}', '');
    GetStorage().write('study_cursor_desc_${appService.bookId}', '');
    GetStorage().remove('study_cursor_manual_${appService.bookId}');
    GetStorage().remove(_manualStudyCursorKey);
    GetStorage().write(_manualStudyCursorMigrationKey, true);
    GetStorage().remove('saved_queue_${appService.bookId}_new');
    GetStorage().remove('saved_queue_pos_${appService.bookId}_new');
    await appService.clearReviewState(
      appService.bookId,
      clearStats: true,
      clearPreferences: true,
    );
    Get.offAllNamed("/main");
    Get.snackbar("重学已开启", "进度已重置，下次学习将按您的偏好顺序进行！",
        snackPosition: SnackPosition.BOTTOM);
  }

  void reviewTodayAgain() async {
    await appService.clearReviewState(appService.bookId);
    await studyService.ensureTodayReviewState();
    _init();
  }

  // 今日所学的下一批（保留当天 roundDone）
  void startNewReviewBatch() async {
    final statuses = await studyService.fetchTodayReviewStatuses();
    final roundDone = await studyService.normalizeReviewIds(
      'review_round_done_${appService.bookId}',
    );
    final learnedIds = statuses
        .map((status) {
          final key = status.word ?? '';
          final prefix = '${appService.bookId}_';
          return key.startsWith(prefix) ? key.substring(prefix.length) : key;
        })
        .where((id) => id.isNotEmpty)
        .toSet();

    if (learnedIds.isEmpty) {
      Get.snackbar("今日无需复习", "今天还没有学习新词，先去学一些吧");
      Get.offAllNamed("/main");
      return;
    }
    if (roundDone.toSet().containsAll(learnedIds)) {
      _showReviewAllDoneDialog();
      return;
    }

    GetStorage().remove('review_batch_${appService.bookId}');
    GetStorage().remove('review_batch_key_${appService.bookId}');
    GetStorage().remove('review_batch_pos_${appService.bookId}');
    GetStorage().remove('review_batch_selected_${appService.bookId}');
    _init();
  }

  void _showReviewAllDoneDialog() {
    bool isDark = Get.isDarkMode;
    Get.defaultDialog(
      title: "今日复习完成",
      titleStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      content: Text("今天学过的单词都已经复习完毕，明天再继续。",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black54,
              height: 1.5)),
      textConfirm: "再复习一遍",
      textCancel: "回首页",
      confirmTextColor: Colors.white,
      buttonColor: const Color(0xFF6366F1),
      cancelTextColor: const Color(0xFF64748B),
      onCancel: () => Get.offAllNamed("/main"),
      onConfirm: () {
        Get.back();
        reviewTodayAgain();
      },
    );
  }

  void _saveQueueState() {
    if (isDifficultMode.value) return;

    String mode = Get.parameters['mode'] ?? 'new';
    List<String> ids = playingWords.map((e) => e.wordId!).toList();
    GetStorage().write('saved_queue_${appService.bookId}_$mode', ids);
    GetStorage()
        .write('saved_queue_pos_${appService.bookId}_$mode', playingIndex);
  }

  Future<void> fetchCount() async {
    dailyStudyCount.value = (await wordDao.queryDailyPassWordCount()) ?? 0;

    if (isDifficultMode.value) {
      bookTotalCount.value = playingWords.length;
    } else {
      // SQLite is the source of truth. Recomputing from the in-memory Book
      // object can keep deleted custom-book words visible after navigation.
      bookTotalCount.value =
          await wordDao.queryWordCount(appService.bookId) ?? 0;
      bookLearnedCount.value =
          await wordDao.queryProgressWordCount(appService.bookId) ?? 0;
    }

    if (Get.parameters['mode'] == 'review') {
      reviewCount.value =
          playingWords.map((word) => word.wordId).toSet().length;
    } else {
      reviewCount.value =
          await wordDao.queryTodayReviewCount(appService.bookId) ?? 0;
    }

    var time = (await wordDao.queryStudyTime()) ?? 0;
    var currentSession = DateTime.now().millisecondsSinceEpoch -
        (timeRecord.startTime ?? DateTime.now().millisecondsSinceEpoch);
    time += currentSession;
    studyTime.value = (time / 1000 / 60).toStringAsFixed(1) + " 分钟";
  }

  Future<void> fetchWords() async {
    String modeParam = Get.parameters['mode'] ?? 'new';
    if (modeParam == 'review') {
      await studyService.ensureTodayReviewState();
      // try to resume today's existing batch first
      final rawSavedBatch = await studyService.normalizeReviewIds(
        'review_batch_${appService.bookId}',
        deduplicate: false,
      );
      bookWordStatusMap = await studyService.fetchBookWordStatusMap();
      final savedBatch = rawSavedBatch
          .where((wordId) => bookWordStatusMap[wordId]?.status == 1)
          .toList();
      if (savedBatch.length != rawSavedBatch.length) {
        await GetStorage().write(
          'review_batch_${appService.bookId}',
          savedBatch,
        );
      }
      final savedPos = int.tryParse(
            '${GetStorage().read('review_batch_pos_${appService.bookId}') ?? 0}',
          ) ??
          0;
      if (savedBatch.isNotEmpty) {
        List<WordVO> batch = [];
        for (var id in savedBatch) {
          var wordData = appService.getWord(id);
          if (wordData != null) {
            var vo = appService.toWordVO(wordData);
            if (vo != null) batch.add(vo);
          }
        }
        if (batch.isNotEmpty) {
          playingWords = batch;
          if (savedPos < batch.length) {
            // 未完成，恢复进度
            playingIndex = savedPos;
          } else {
            // 已完成（pos >= length），直接显示结算界面
            playingIndex = batch.length;
            word.value = null;
          }
          return;
        }
      }
      // create new batch
      int target =
          GetStorage().read('review_target_${appService.bookId}') ?? 20;
      int cycles = GetStorage().read('review_cycles_${appService.bookId}') ?? 3;
      playingWords = await studyService.createReviewBatch(target, cycles);
      _lastReviewRound = 1;
      playingIndex = 0;
      bookWordStatusMap = await studyService.fetchBookWordStatusMap();
    } else if (isManualMode.value) {
      playingWords = await studyService.fetchAllBookWords();
      bookWordStatusMap = await studyService.fetchBookWordStatusMap();
      _restorePosition();
    } else {
      var studyQueueMaxCount = appService.queueCount;
      playingWords =
          await studyService.fetchStudyQueueWords(studyQueueMaxCount);
      playingIndex = 0;
    }
  }

  void _loadManualWord() async {
    if (playingIndex >= 0 && playingIndex < playingWords.length) {
      // 复习模式：检测轮次过渡
      String modeParam = Get.parameters['mode'] ?? 'new';
      if (modeParam == 'review' && playingWords.isNotEmpty) {
        int uniqueCount = playingWords.map((e) => e.wordId).toSet().length;
        if (uniqueCount > 0) {
          int currentRound = (playingIndex ~/ uniqueCount) + 1;
          int totalRounds = (playingWords.length / uniqueCount).ceil();
          if (currentRound != _lastReviewRound) {
            _lastReviewRound = currentRound;
            reviewRoundInfo.value = "第 $currentRound 轮 / 共 $totalRounds 轮";
            Future.delayed(const Duration(milliseconds: 500), () {
              reviewRoundInfo.value = "";
            });
          }
        }
      }

      word.value = playingWords[playingIndex];
      var wordId = word.value?.wordId;
      print(
          '[LOAD] wordId=$wordId word="${word.value?.word}" means=${word.value?.means}');
      if (wordId != null) {
        var status = bookWordStatusMap[wordId];
        wordStatus.value = status;
        bool isLearned = _isLearnedStatus(status);

        isRevealed.value = modeParam == 'review' ? false : isLearned;
        // 进入卡片时先播一次发音
        if (appService.autoPlayVoice) {
          playWordSound(word.value?.word, 1);
        }
        // 已学会的词（直接显示释义）不再重复播
        if (isRevealed.value && appService.autoPlayVoice) {
          // 已在上面播过，不重复
        }

        // 自动补全空释义单词
        _tryFillEmptyMeans(word.value);
      } else {
        wordStatus.value = null;
        isRevealed.value = false;
      }
      _savePosition();
    } else {
      word.value = null;
    }
  }

  void _savePosition() {
    if ((Get.parameters['mode'] ?? 'new') == 'review' || isDifficultMode.value)
      return;

    if (playingWords.isNotEmpty &&
        playingIndex >= 0 &&
        playingIndex < playingWords.length) {
      String? wordId = playingWords[playingIndex].wordId;
      if (wordId != null) {
        GetStorage().write(_manualStudyCursorKey, wordId);
        GetStorage().write(_manualStudyCursorMigrationKey, true);
      }
    }
  }

  void _restorePosition() {
    var storage = GetStorage();
    String? savedWordId = storage.read(_manualStudyCursorKey);

    if (savedWordId == null &&
        storage.read(_manualStudyCursorMigrationKey) != true) {
      var savedQueue = storage.read('saved_queue_${appService.bookId}_new');
      int savedQueuePos =
          storage.read('saved_queue_pos_${appService.bookId}_new') ?? -1;
      if (savedQueue is List &&
          savedQueuePos >= 0 &&
          savedQueuePos < savedQueue.length) {
        savedWordId = '${savedQueue[savedQueuePos]}';
      }

      // The legacy cursor is safe to migrate only if no review batch exists.
      if (savedWordId == null &&
          storage.read('review_batch_${appService.bookId}') == null) {
        savedWordId = storage.read('study_cursor_manual_${appService.bookId}');
      }

      if (savedWordId != null) {
        storage.write(_manualStudyCursorKey, savedWordId);
      }
      storage.write(_manualStudyCursorMigrationKey, true);
    }

    if (savedWordId != null) {
      int idx = playingWords.indexWhere((w) => w.wordId == savedWordId);
      if (idx >= 0) {
        playingIndex = idx;
        return;
      }
    }
    playingIndex = 0;
  }

  Future<void> _completeReviewBatch() async {
    final selected = await studyService.normalizeReviewIds(
      'review_batch_selected_${appService.bookId}',
    );
    final roundDone = await studyService.normalizeReviewIds(
      'review_round_done_${appService.bookId}',
    );
    for (var w in selected) {
      if (!roundDone.contains(w)) roundDone.add(w);
    }
    GetStorage().write('review_round_done_${appService.bookId}', roundDone);
    // 保留 review_batch / review_batch_selected / review_batch_pos，
    // 让用户退出重进时能恢复同一批次和 AI 文章
    // review_batch_pos 设为 length 标识"已完毕"
    GetStorage()
        .write('review_batch_pos_${appService.bookId}', playingWords.length);

    // 不再弹对话框，而是设 word=null 触发 buildEndView 展示 AI 文章结算面板
    word.value = null;
  }

  void addToDifficult() async {
    var spell = word.value?.word;
    if (spell == null) return;
    bool added = await appService.wordService.addWordToDifficultBook(spell);
    if (added) {
      // also ensure the word definition is loaded if not already
      if (appService.getWordBySpell(spell) == null) {
        final fetched = await fetchWordDefinition(spell);
        if (fetched != null) {
          appService.wordService.mergeFetchedWord(fetched);
        }
      }
      Get.snackbar("已添加", "《$spell》已加入顽固词汇",
          duration: const Duration(seconds: 1));
    } else {
      Get.snackbar("提示", "《$spell》已在顽固词汇中",
          duration: const Duration(seconds: 1));
    }
  }

  void openDifficultBook() async {
    await stopPlay();
    List<String> difficultWords = appService.wordService.getDifficultWords();
    print(
        '[DIFFICULT] openDifficultBook called, words count=${difficultWords.length}');
    if (difficultWords.isEmpty) {
      Get.snackbar("提示", "顽固词汇为空，点击 + 添加吧");
      return;
    }

    final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text("顽固词汇 (${difficultWords.length} 个)",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.list_alt, color: Colors.teal),
              title: Text("查看顽固词汇列表",
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black)),
              subtitle: Text("浏览所有已添加的顽固词汇",
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54)),
              onTap: () {
                Get.back();
                _showDifficultWordList();
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book, color: Colors.teal),
              title: Text("学习顽固词汇",
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black)),
              subtitle: Text("进入学习模式，共 ${difficultWords.length} 个词",
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54)),
              onTap: () {
                Get.back();
                _startDifficultStudy();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showDifficultWordList() {
    List<String> difficultWords = appService.wordService.getDifficultWords();
    List<WordVO> vos = [];
    for (var spell in difficultWords) {
      var w = appService.getWordBySpell(spell);
      if (w != null) {
        vos.add(appService.toWordVO(w)!);
      }
    }
    final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Expanded(
                      child: Text("顽固词汇列表 (${vos.length})",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black))),
                  IconButton(
                      onPressed: () => Get.back(),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: vos.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(vos[i].word ?? "",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text((vos[i].means ?? []).join("；"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startDifficultStudy() async {
    List<String> difficultWords = appService.wordService.getDifficultWords();
    if (difficultWords.isEmpty) return;

    await stopPlay();

    // 1. Snapshot current study state
    _backupPlayingWords = List.from(playingWords);
    _backupPlayingIndex = playingIndex;
    _backupIsManualMode = isManualMode.value;

    // 2. Build difficult words queue
    List<WordVO> diffVos = [];
    for (var spell in difficultWords) {
      var w = appService.getWordBySpell(spell);
      if (w == null) {
        final fetched = await fetchWordDefinition(spell);
        if (fetched != null) appService.wordService.mergeFetchedWord(fetched);
        w = appService.wordService.spellMap[spell] ??
            fetched ??
            Word(id: spell, word: spell, means: '暂无释义');
      }
      var vo = appService.toWordVO(w);
      if (vo != null) diffVos.add(vo);
    }

    // 3. Swap to difficult mode
    playingWords = diffVos;
    playingIndex = 0;
    isDifficultMode.value = true;
    isManualMode.value = true;
    _loadManualWord();
  }

  void exitDifficultMode() {
    playingWords = _backupPlayingWords;
    playingIndex = _backupPlayingIndex;
    isManualMode.value = _backupIsManualMode;
    isDifficultMode.value = false;

    if (isManualMode.value) {
      _loadManualWord();
    } else {
      startPlay();
    }
  }

  void jumpToLearningPosition() {
    if (!isManualMode.value || playingWords.isEmpty) return;
    int targetIndex = -1;
    for (int i = 0; i < playingWords.length; i++) {
      var wordId = playingWords[i].wordId;
      if (wordId == null) continue;
      var status = bookWordStatusMap[wordId];
      if ((status?.status ?? 0) < 0) continue;
      if (!_isLearnedStatus(status)) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex == -1) {
      Get.snackbar("提示", "本书所有单词都已学习完毕");
      return;
    }
    playingIndex = targetIndex;
    _loadManualWord();
  }

  Future<bool> jumpToWordAt(int index) async {
    if (index < 0 || index >= playingWords.length) return false;
    playingIndex = index;
    if (isManualMode.value) {
      _loadManualWord();
    } else {
      word.value = playingWords[index];
    }
    if ((Get.parameters['mode'] ?? 'new') == 'review') {
      await GetStorage().write(
        'review_batch_pos_${appService.bookId}',
        playingIndex,
      );
    } else {
      _saveQueueState();
    }
    return true;
  }

  Future<bool> jumpToWordId(String? wordId) async {
    if (wordId == null || wordId.isEmpty) return false;
    final index = playingWords.indexWhere((word) => word.wordId == wordId);
    if (index < 0) {
      Get.snackbar(
        "提示",
        "该单词不在当前学习列表中",
        duration: const Duration(seconds: 1),
      );
      return false;
    }
    return await jumpToWordAt(index);
  }

  void manualReveal() {
    if (isRevealed.value) return;
    isRevealed.value = true;
    // 点击显示意思后再播一遍发音
    if (appService.autoPlayVoice) {
      playWordSound(word.value?.word, 1);
    }
  }

  Future<void> startPlay() async {
    if (isManualMode.value) return;
    if (!playButtonEnable.value) return;
    playButtonEnable.value = false;
    player?.stop();
    playing.value = true;

    player = Player.create(
      thinkTime: thinkWaitTime.value,
      showTime: readWaitTime.value,
      thinkStart: (Player player) async {
        thinking.value = true;
        wordStatus.value = null;
        var index = playingIndex;
        var arr = playingWords;

        if (index >= arr.length) playingIndex = index = 0;

        if (index < arr.length) {
          word.value = arr[index];
          var wordId = arr[index].wordId;
          if (wordId != null) {
            player.wordStatus =
                await wordDao.queryWordStatus(_wordStatusKey(wordId));
            wordStatus.value = player.wordStatus;
          }
          _tryFillEmptyMeans(word.value);
          if (appService.autoPlayVoice) {
            await playWordSound(word.value?.word, 1);
          }
        } else {
          word.value = null;
          wordStatus.value = null;
          stopPlay();
        }

        player.showTime = readWaitTime.value;
        var cycle = player.wordStatus?.studyCycle;
        if (cycle != null && readWaitTime.value > 0) {
          if (cycle >= 1) {
            player.showTime = (readWaitTime.value * (1 - cycle / 8)).toInt();
            if (player.showTime < 1) player.showTime = 1;
          }
        }
      },
      thinkEnd: (Player player) async {
        thinking.value = false;
      },
      showStart: (Player player) async {},
      showEnd: (Player player) async {
        if (appService.autoPass) {
          var key = player.wordStatus?.word ?? "";
          var wordPlayCount = playCount[key] ?? 0;
          wordPlayCount++;
          playCount[key] = wordPlayCount;
          var cycle = player.wordStatus?.studyCycle ?? 0;
          if (wordPlayCount > 3 ||
              (cycle == 1 && wordPlayCount == 2) ||
              cycle > 1) return;
        }
        playingIndex++;
        if (playingIndex >= playingWords.length) playingIndex = 0;
        fetchCount();
      },
      onEnd: (Player player) async {
        var startTime = player.startTime;
        var endTime = player.stopTime ?? DateTime.now().millisecondsSinceEpoch;
        var status = player.wordStatus;
        if (status != null) {
          studyService.addWordStudyRecord(
              startTime, endTime, player.playComplete, status);
        }
        if (appService.autoPass) {
          var key = player.wordStatus?.word ?? "";
          var wordPlayCount = playCount[key] ?? 0;
          var cycle = player.wordStatus?.studyCycle ?? 0;
          if (wordPlayCount > 3 ||
              (cycle == 1 && wordPlayCount == 2) ||
              cycle > 1) {
            playCount[key] = 0;
            pass();
          }
        }
      },
    );

    playButtonEnable.value = true;
  }

  Future<void> stopPlay() async {
    if (!playButtonEnable.value) return;
    thinking.value = false;
    playButtonEnable.value = false;
    player?.stop();
    playing.value = false;
    playButtonEnable.value = true;
  }

  void next() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();

    if (isManualMode.value) {
      if (playingIndex < playingWords.length - 1) {
        playingIndex++;
        _loadManualWord();
      } else {
        Get.snackbar("提示", "这已经是最后一个单词了", duration: const Duration(seconds: 1));
      }
    } else {
      playingIndex++;
      if (playingIndex >= playingWords.length) playingIndex = 0;
      await startPlay();
    }

    _saveQueueState();
    await fetchCount();
    controlEnable.value = true;
  }

  void previous() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();

    if (isManualMode.value) {
      if (playingIndex > 0) {
        playingIndex--;
        _loadManualWord();
      } else {
        Get.snackbar("提示", "这已经是第一个单词了", duration: const Duration(seconds: 1));
      }
    } else {
      playingIndex--;
      if (playingIndex < 0) playingIndex = max(playingWords.length - 1, 0);
      await startPlay();
    }

    _saveQueueState();
    await fetchCount();
    controlEnable.value = true;
  }

  void pass() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();
    var wId = word.value?.wordId;
    if (wId != null) {
      if ((Get.parameters['mode'] ?? 'new') == 'review') {
        await studyService.passReview(wId);
      } else {
        await studyService.pass(wId);
      }
      if (!_sessionPassedIds.contains(wId)) {
        _sessionPassedIds.add(wId);
        sessionPassCount.value++;
      }
    }

    if (isManualMode.value) {
      String modeParam = Get.parameters['mode'] ?? 'new';
      if (wId != null && modeParam != 'review') {
        var currentStatus = bookWordStatusMap[wId] ??
            WordStatusPO(word: "${appService.bookId}_$wId");
        currentStatus.status = 1;
        currentStatus.studyCycle = (currentStatus.studyCycle ?? 0) + 1;
        currentStatus.updateTime = DateTime.now().millisecondsSinceEpoch;
        bookWordStatusMap[wId] = currentStatus;
      }
      if (modeParam == 'review') {
        // advance batch position
        int pos =
            GetStorage().read('review_batch_pos_${appService.bookId}') ?? 0;
        GetStorage().write('review_batch_pos_${appService.bookId}', pos + 1);
        if (pos + 1 >= playingWords.length) {
          await _completeReviewBatch();
          await fetchCount();
          controlEnable.value = true;
          return;
        }
      }
      controlEnable.value = true;
      next();
    } else {
      var nextW = await studyService.fetchNextWord();
      if (nextW != null) {
        playingWords[playingIndex] = nextW;
        playingIndex++;
        if (playingIndex >= playingWords.length) playingIndex = 0;
      } else {
        playingWords.removeAt(playingIndex);
        if (playingWords.isEmpty) word.value = null;
      }
      await startPlay();
      await fetchCount();
      controlEnable.value = true;
    }
  }

  void delete() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();
    var wId = word.value?.wordId;

    if (isDifficultMode.value) {
      var w = word.value?.word;
      if (w != null) {
        var storage = GetStorage();
        List<String> diffs =
            List<String>.from(storage.read('difficult_words') ?? []);
        diffs.remove(w);
        storage.write('difficult_words', diffs);
        Get.snackbar("彻底掌握", "《$w》已被斩草除根，主线也不再出现！",
            duration: const Duration(seconds: 1));
      }
      if (wId != null) {
        await studyService.markFamiliar(wId);
        final status =
            bookWordStatusMap[wId] ?? WordStatusPO(word: _wordStatusKey(wId));
        status.status = -1;
        bookWordStatusMap[wId] = status;
        final removedBeforeBackup = _backupPlayingWords
            .take(_backupPlayingIndex)
            .where((item) => item.wordId == wId)
            .length;
        _backupPlayingWords.removeWhere((item) => item.wordId == wId);
        _backupPlayingIndex -= removedBeforeBackup;
        if (_backupPlayingWords.isEmpty) {
          _backupPlayingIndex = 0;
        } else {
          _backupPlayingIndex = max(
            0,
            min(_backupPlayingIndex, _backupPlayingWords.length - 1),
          );
        }
        if (Get.isRegistered<SelectBookController>()) {
          Get.find<SelectBookController>().refreshBooks();
        }
      }
      playingWords.removeAt(playingIndex);
      if (playingWords.isEmpty) {
        word.value = null;
      } else {
        if (playingIndex >= playingWords.length) playingIndex = 0;
        _loadManualWord();
      }
      await fetchCount();
      controlEnable.value = true;
      return;
    }

    if (wId != null) {
      await studyService.markFamiliar(wId);

      final spelling = word.value?.word;
      if (spelling != null) {
        var storage = GetStorage();
        List<String> diffs =
            List<String>.from(storage.read('difficult_words') ?? []);
        if (diffs.remove(spelling)) {
          await storage.write('difficult_words', diffs);
        }
      }

      if (Get.isRegistered<SelectBookController>()) {
        Get.find<SelectBookController>().refreshBooks();
      }
    }

    if (isManualMode.value) {
      if (wId != null) {
        var currentStatus =
            bookWordStatusMap[wId] ?? WordStatusPO(word: _wordStatusKey(wId));
        currentStatus.status = -1;
        currentStatus.updateTime = DateTime.now().millisecondsSinceEpoch;
        bookWordStatusMap[wId] = currentStatus;
      }
      // 复习模式：删除该词在所有轮次中的全部出现
      if (Get.parameters['mode'] == 'review') {
        int removedBeforeIdx = 0;
        for (int i = 0; i < playingIndex; i++) {
          if (playingWords[i].wordId == wId) {
            removedBeforeIdx++;
          }
        }
        playingWords.removeWhere((item) => item.wordId == wId);
        playingIndex = playingIndex - removedBeforeIdx;
        if (playingWords.isNotEmpty && playingIndex >= playingWords.length) {
          playingIndex = playingWords.length - 1;
        }
      } else {
        playingWords.removeAt(playingIndex);
      }
      if (Get.parameters['mode'] == 'review') {
        List<String> newBatch = playingWords.map((e) => e.wordId!).toList();
        await GetStorage().write('review_batch_${appService.bookId}', newBatch);
        await _invalidateArticleForChangedReviewBatch();
        int pos =
            GetStorage().read('review_batch_pos_${appService.bookId}') ?? 0;
        if (playingWords.isEmpty || pos >= playingWords.length) {
          await _completeReviewBatch();
          await fetchCount();
          controlEnable.value = true;
          return;
        }
      }
      if (playingWords.isEmpty) {
        word.value = null;
      } else {
        if (playingIndex >= playingWords.length) {
          playingIndex = playingWords.length - 1;
        }
        _loadManualWord();
      }
      _saveQueueState();
      await fetchCount();
      controlEnable.value = true;
    } else {
      var nextW = await studyService.fetchNextWord();
      if (nextW != null) {
        playingWords[playingIndex] = nextW;
        playingIndex++;
        if (playingIndex >= playingWords.length) playingIndex = 0;
      } else {
        playingWords.removeAt(playingIndex);
        if (playingWords.isEmpty) word.value = null;
      }
      await startPlay();
      _saveQueueState();
      await fetchCount();
      controlEnable.value = true;
    }
  }

  // ==== 大模型文章生成逻辑 ====
  Future<void> generateArticle() async {
    if (aiArticle.value.isNotEmpty || isGeneratingArticle.value) return;

    final settings = AiSettings.fromStorage();
    if (!settings.isConfigured) {
      aiArticle.value = '文章生成失败：请先在「我的」中配置 API 站点、模型和 Key';
      return;
    }

    final words = _articleWords();
    if (words.isEmpty) {
      aiArticle.value = '文章生成失败：当前批次没有可用的英文单词';
      return;
    }

    final requestBatchKey = _currentReviewBatchKey();
    if (requestBatchKey.isEmpty) {
      aiArticle.value = '文章生成失败：复习批次已失效，请重新进入复习';
      return;
    }

    final cancelToken = CancelToken();
    _articleCancelToken?.cancel('new article request');
    _articleCancelToken = cancelToken;
    _cachedArticleBatchKey = requestBatchKey;
    isGeneratingArticle.value = true;
    aiArticle.value = '';
    final streamedArticle = StringBuffer();

    bool isCurrentRequest() {
      return !cancelToken.isCancelled &&
          identical(_articleCancelToken, cancelToken) &&
          _cachedArticleBatchKey == requestBatchKey &&
          requestBatchKey == _currentReviewBatchKey();
    }

    try {
      final rawArticle = await OpenAiResponsesClient().streamText(
        settings: settings,
        cancelToken: cancelToken,
        instructions: '你是一名严谨、自然的英语写作老师。只输出用户要求的文章和翻译。',
        input: '请用以下单词写一篇自然流畅的英文文章（题材不限），然后在下方附上整篇对应的中文翻译。'
            '每个目标单词都要在英文正文中至少出现一次，并用 **目标单词** 格式加粗。'
            '英文正文中不要出现任何中文。在中文翻译中，将目标单词对应的中文释义也用 **中文释义** 格式加粗。'
            '只返回英文文章和中文翻译两部分，不要任何说明。文章务必精简，'
            '英文总词数不得超过${words.length * 6}词。单词列表：${words.join(', ')}',
        maxOutputTokens: max(600, words.length * 45),
        onDelta: (delta) {
          if (!isCurrentRequest()) return;
          streamedArticle.write(delta);
          aiArticle.value = _boldTargetWords(streamedArticle.toString(), words);
        },
      );

      if (!isCurrentRequest()) return;
      final formattedArticle = _boldTargetWords(rawArticle, words);
      aiArticle.value = formattedArticle;
      await GetStorage().write(_articleStorageKey, <String, dynamic>{
        'batchKey': requestBatchKey,
        'article': formattedArticle,
      });
    } on DioError catch (error) {
      if (error.type == DioErrorType.cancel || !isCurrentRequest()) return;
      aiArticle.value = '文章生成失败：${_dioErrorMessage(error)}';
    } on TimeoutException {
      if (!isCurrentRequest()) return;
      aiArticle.value = '文章生成失败：AI 响应超时，请检查站点、模型或网络';
    } on AiRequestException catch (error) {
      if (!isCurrentRequest()) return;
      aiArticle.value = '文章生成失败：${error.message}';
    } catch (error) {
      if (!isCurrentRequest()) return;
      aiArticle.value = '文章生成失败：$error';
    } finally {
      if (identical(_articleCancelToken, cancelToken)) {
        _articleCancelToken = null;
        isGeneratingArticle.value = false;
      }
    }
  }

  String _dioErrorMessage(DioError error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 400) return '请求格式错误 (400)，请检查站点地址和模型名';
    if (statusCode == 401) return 'API Key 无效 (401)';
    if (statusCode == 403) return '当前 Key 无权访问该模型 (403)';
    if (statusCode == 404) return '接口地址或模型不存在 (404)，请检查站点 URL';
    if (statusCode == 429) return '请求过快或额度不足 (429)';
    if (statusCode != null && statusCode >= 500) {
      return 'AI 服务暂时不可用 ($statusCode)';
    }
    if (error.type == DioErrorType.connectTimeout ||
        error.type == DioErrorType.sendTimeout) {
      return '连接 AI 站点超时';
    }
    if (error.type == DioErrorType.receiveTimeout) {
      return 'AI 长时间没有返回数据';
    }
    return '网络请求失败，请检查站点地址和网络';
  }

  void cancelArticleGeneration() {
    _articleCancelToken?.cancel('cancelled by user');
    _articleCancelToken = null;
    isGeneratingArticle.value = false;
  }

  Future<void> regenerateArticle() async {
    cancelArticleGeneration();
    aiArticle.value = "";
    await GetStorage().remove(_articleStorageKey);
    await generateArticle();
  }

  Future<void> _invalidateArticleForChangedReviewBatch() async {
    cancelArticleGeneration();
    var storage = GetStorage();
    String newBatchKey =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
    await storage.write('review_batch_key_${appService.bookId}', newBatchKey);
    await storage.remove(_articleStorageKey);
    _cachedArticleBatchKey = newBatchKey;
    aiArticle.value = "";
    generateArticle();
  }

  Future<void> markFamiliarFromWordList(WordVO target) async {
    final wordId = target.wordId;
    if (wordId == null || wordId.isEmpty) return;

    await studyService.markFamiliar(wordId);
    final status =
        bookWordStatusMap[wordId] ?? WordStatusPO(word: _wordStatusKey(wordId));
    status.status = -1;
    bookWordStatusMap[wordId] = status;

    final spelling = target.word;
    if (spelling != null) {
      final storage = GetStorage();
      final difficultWords =
          List<String>.from(storage.read('difficult_words') ?? []);
      if (difficultWords.remove(spelling)) {
        await storage.write('difficult_words', difficultWords);
      }
    }

    final removedBeforeBackup = _backupPlayingWords
        .take(_backupPlayingIndex)
        .where((item) => item.wordId == wordId)
        .length;
    _backupPlayingWords.removeWhere((item) => item.wordId == wordId);
    _backupPlayingIndex -= removedBeforeBackup;
    if (_backupPlayingWords.isEmpty) {
      _backupPlayingIndex = 0;
    } else {
      _backupPlayingIndex =
          max(0, min(_backupPlayingIndex, _backupPlayingWords.length - 1));
    }

    final safeIndex = min(playingIndex, playingWords.length);
    final removedBefore = playingWords
        .take(safeIndex)
        .where((item) => item.wordId == wordId)
        .length;
    final oldLength = playingWords.length;
    playingWords.removeWhere((item) => item.wordId == wordId);
    playingIndex = max(0, playingIndex - removedBefore);
    if (playingWords.isNotEmpty) {
      playingIndex = min(playingIndex, playingWords.length - 1);
    }
    final removedFromQueue = oldLength != playingWords.length;

    if (Get.parameters['mode'] == 'review' && removedFromQueue) {
      await GetStorage().write(
        'review_batch_${appService.bookId}',
        playingWords.map((item) => item.wordId).toList(),
      );
      if (playingWords.isNotEmpty) {
        await _invalidateArticleForChangedReviewBatch();
      }
    }

    if (playingWords.isEmpty) {
      word.value = null;
      await GetStorage().remove(_manualStudyCursorKey);
    } else if (isManualMode.value) {
      _loadManualWord();
    } else if (word.value?.wordId == wordId) {
      word.value = playingWords[playingIndex];
    }

    _saveQueueState();
    await fetchCount();
    if (Get.isRegistered<SelectBookController>()) {
      Get.find<SelectBookController>().refreshBooks();
    }
  }

  Future<void> restoreWordFromWordList(WordVO target) async {
    final wordId = target.wordId;
    if (wordId == null || wordId.isEmpty) return;

    await wordDao.restoreWordForStudy(wordId, appService.bookId);
    await studyService.removeReviewWordState(appService.bookId, wordId);
    final currentWordId = word.value?.wordId;
    bookWordStatusMap = await studyService.fetchBookWordStatusMap();

    final mode = Get.parameters['mode'] ?? 'new';
    if (isManualMode.value && mode != 'review' && !isDifficultMode.value) {
      playingWords = await studyService.fetchAllBookWords();
      var index = currentWordId == null
          ? -1
          : playingWords.indexWhere((item) => item.wordId == currentWordId);
      if (index < 0) {
        index = playingWords.indexWhere((item) => item.wordId == wordId);
      }
      playingIndex = index < 0 ? 0 : index;
      if (playingWords.isNotEmpty) _loadManualWord();
    }

    _saveQueueState();
    await fetchCount();
    if (Get.isRegistered<SelectBookController>()) {
      Get.find<SelectBookController>().refreshBooks();
    }
  }

  void togglePlay() async {
    if (isManualMode.value) return;
    if (playing.value) {
      await stopPlay();
    } else {
      await startPlay();
    }
  }

  void fetchWordStatus() async {
    var w = word.value;
    if (w != null) {
      final wordId = w.wordId;
      wordStatus.value = wordId == null
          ? null
          : await wordDao.queryWordStatus(_wordStatusKey(wordId));
    }
  }

  void _tryFillEmptyMeans(WordVO? vo) async {
    if (vo == null || vo.word == null) return;
    var currentMeans = vo.means;
    bool isEmpty = currentMeans == null ||
        currentMeans.isEmpty ||
        currentMeans.every((e) => e.trim().isEmpty);
    // 上次获取失败的占位文本也视为空，允许重试
    bool isFetchFailedPlaceholder = !isEmpty &&
        currentMeans!.length == 1 &&
        currentMeans[0].contains("释义获取失败");
    if (!isEmpty && !isFetchFailedPlaceholder) return;

    // ==== Bug fix: 先尝试原始拼写，再尝试常见变体拼写 ====
    final spell = vo.word!;
    final fetched =
        await fetchWordDefinition(spell) ?? await _tryVariantSpellFetch(spell);

    if (fetched != null &&
        fetched.means != null &&
        fetched.means!.trim().isNotEmpty) {
      appService.wordService.mergeFetchedWord(fetched);

      // 重建 WordVO，保留原始 wordId 以免后续状态追踪断裂
      var merged = appService.wordService.spellMap[vo.word!] ?? fetched;
      // 如果原始拼写在 spellMap 中没有更新（变体拼写更新了不同 key），也要手动更新
      if (appService.wordService.spellMap[vo.word!] == null ||
          (appService.wordService.spellMap[vo.word!]?.means ?? '')
              .trim()
              .isEmpty) {
        // 用 fetched 的 means 直接写一个副本到原始拼写的 key
        var origEntry = appService.wordService.spellMap[vo.word!];
        if (origEntry != null) {
          origEntry.means = fetched.means;
          if (fetched.usVoice != null && fetched.usVoice!.isNotEmpty)
            origEntry.usVoice = fetched.usVoice;
          if (fetched.ukVoice != null && fetched.ukVoice!.isNotEmpty)
            origEntry.ukVoice = fetched.ukVoice;
          if (fetched.sentences != null && fetched.sentences!.isNotEmpty)
            origEntry.sentences = fetched.sentences;
        } else {
          // 为原始拼写创建一个带释义的副本
          var copy = Word(
              id: spell,
              word: spell,
              means: fetched.means,
              usVoice: fetched.usVoice,
              ukVoice: fetched.ukVoice,
              sentences: fetched.sentences);
          appService.wordService.wordMap[spell] = copy;
          appService.wordService.spellMap[spell] = copy;
        }
        merged = appService.wordService.spellMap[vo.word!] ?? fetched;
      }

      var updatedVo = appService.toWordVO(merged);
      if (updatedVo != null) {
        updatedVo.wordId = vo.wordId ?? spell;
        // 放宽条件：只要 word 匹配就更新（不再依赖 wordId 对比）
        if (word.value?.word == vo.word) {
          word.value = updatedVo;
        }
        int idx = playingWords
            .indexWhere((e) => e.wordId == vo.wordId || e.word == vo.word);
        if (idx >= 0) {
          playingWords[idx] = updatedVo;
        }
      }
    } else {
      // 所有在线源都获取失败，设置兜底提示（下次进入时仍会重试）
      // ==== Bug fix: 放宽条件，只要 word 匹配就设兜底 ====
      if (word.value?.word == vo.word) {
        vo.means = ["释义获取失败，请检查网络"];
        word.value = vo;
      }
    }
  }

  /// 尝试常见变体拼写（英式→美式、美式→英式等）
  Future<Word?> _tryVariantSpellFetch(String spell) async {
    // 常见拼写变体映射
    final variants = <String>[];
    // -or → -our (美式→英式)
    if (spell.endsWith('or') && spell.length > 3)
      variants.add(spell.substring(0, spell.length - 2) + 'our');
    // -our → -or (英式→美式)
    if (spell.endsWith('our') && spell.length > 4)
      variants.add(spell.substring(0, spell.length - 3) + 'or');
    // -er → -re (美式→英式)
    if (spell.endsWith('er') && spell.length > 3)
      variants.add(spell.substring(0, spell.length - 2) + 're');
    // -re → -er (英式→美式)
    if (spell.endsWith('re') && spell.length > 3)
      variants.add(spell.substring(0, spell.length - 2) + 'er');
    // -ize → -ise (美式→英式)
    if (spell.endsWith('ize') && spell.length > 4)
      variants.add(spell.substring(0, spell.length - 3) + 'ise');
    // -ise → -ize (英式→美式)
    if (spell.endsWith('ise') && spell.length > 4)
      variants.add(spell.substring(0, spell.length - 3) + 'ize');
    // -yse → -yze
    if (spell.endsWith('yse') && spell.length > 4)
      variants.add(spell.substring(0, spell.length - 3) + 'yze');
    // -yze → -yse
    if (spell.endsWith('yze') && spell.length > 4)
      variants.add(spell.substring(0, spell.length - 3) + 'yse');
    // -ense → -ence (美式→英式)
    if (spell.endsWith('ense') && spell.length > 5)
      variants.add(spell.substring(0, spell.length - 4) + 'ence');
    // -ence → -ense (英式→美式)
    if (spell.endsWith('ence') && spell.length > 5)
      variants.add(spell.substring(0, spell.length - 4) + 'ense');

    for (var v in variants) {
      var result = await fetchWordDefinition(v);
      if (result != null &&
          result.means != null &&
          result.means!.trim().isNotEmpty) {
        // 将变体拼写的释义复制一份到原始拼写
        var copy = Word(
            id: spell,
            word: spell,
            means: result.means,
            usVoice: result.usVoice,
            ukVoice: result.ukVoice,
            sentences: result.sentences);
        return copy;
      }
    }
    return null;
  }
}
