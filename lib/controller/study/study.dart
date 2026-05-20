import 'dart:async';
import 'dart:math';

import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/vo/word.dart';
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
import '../../controller/home/home_v2.dart';
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

  var isManualMode = false.obs;
  var isRevealed = false.obs;

  var isDifficultMode = false.obs;
  List<WordVO> _backupPlayingWords = [];
  int _backupPlayingIndex = 0;
  bool _backupIsManualMode = false;

  var reviewDailyCount = 50.obs;

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
    await fetchOptions();

    String modeParam = Get.parameters['mode'] ?? 'new';
    if (modeParam == 'review') {
      isManualMode.value = true;
    } else {
      isManualMode.value = appService.getStudyMode(appService.bookId) == 'manual';
    }

    await fetchWords();

    if (playingWords.isEmpty) {
      if (modeParam == 'review') {
        Get.offAllNamed("/main");
        Get.snackbar("提示", "当前没有任何要复习的单词，快去学一些吧", snackPosition: SnackPosition.BOTTOM);
        return;
      }
    }

    await fetchCount();

    if (isManualMode.value) {
      _loadManualWord();
    } else {
      await startPlay();
    }

    isInitializing.value = false;
  }

  Future<void> fetchOptions() async {
    appService.readOptions();
    thinkWaitTime.value = appService.thinkWaitTime;
    readWaitTime.value = appService.readWaitTime;
    queueCount.value = appService.queueCount;
    autoPass.value = appService.autoPass;

    autoPass.listen((value) { appService.autoPass = value; appService.saveOptions(); });
    thinkWaitTime.listen((value) { appService.thinkWaitTime = value; appService.saveOptions(); });
    readWaitTime.listen((value) { appService.readWaitTime = value; appService.saveOptions(); });
    queueCount.listen((value) { appService.queueCount = value; appService.saveOptions(); });

    reviewDailyCount.value = appService.reviewDailyCount;
    reviewDailyCount.listen((value) { appService.reviewDailyCount = value; appService.saveOptions(); });
  }

  @override
  void onClose() {
    Wakelock.disable();
    timeRecord.recordEnd();
    WidgetsBinding.instance?.removeObserver(this);
    stopPlay();
    super.onClose();
  }

  void reloadStudy() => _init();

  void restartBook(String orderPref) async {
    await wordDao.clearBookProgress(appService.bookId);
    GetStorage().write('book_order_${appService.bookId}', orderPref);
    GetStorage().write('study_cursor_${appService.bookId}', '');
    GetStorage().write('study_cursor_desc_${appService.bookId}', '');
    GetStorage().write('study_cursor_manual_${appService.bookId}', '');
    Get.offAllNamed("/main");
    Get.snackbar("重学已开启", "进度已重置，下次学习将按您的偏好顺序进行！", snackPosition: SnackPosition.BOTTOM);
  }

  void reviewTodayAgain() async {
    GetStorage().remove('review_date_${appService.bookId}');
    GetStorage().remove('review_round_done_${appService.bookId}');
    GetStorage().remove('review_batch_${appService.bookId}');
    GetStorage().remove('review_batch_pos_${appService.bookId}');
    GetStorage().remove('review_batch_selected_${appService.bookId}');
    _init();
  }

  void _saveQueueState() {
    String mode = Get.parameters['mode'] ?? 'new';
    List<String> ids = playingWords.map((e) => e.wordId!).toList();
    GetStorage().write('saved_queue_${appService.bookId}_$mode', ids);
    GetStorage().write('saved_queue_pos_${appService.bookId}_$mode', playingIndex);
  }

  Future<void> fetchCount() async {
    dailyStudyCount.value = (await wordDao.queryDailyPassWordCount()) ?? 0;

    if (isDifficultMode.value) {
      bookTotalCount.value = playingWords.length;
    } else {
      var book = appService.wordService.bookMap[appService.bookName];
      if (book != null && book.words != null) {
        int valid = 0;
        int learned = 0;
        for (var w in book.words!) {
          if (w.id != null) {
            var status = bookWordStatusMap[w.id!];
            if (status == null || status.status != -1) valid++;
            if (status != null && status.status != -1 && (status.status == 1 || (status.studyCycle ?? 0) > 0)) {
              learned++;
            }
          }
        }
        bookTotalCount.value = valid;
        bookLearnedCount.value = learned;
      }
    }

    if (Get.parameters['mode'] == 'review') {
      reviewCount.value = playingWords.length;
    } else {
      int rCount = 0;
      for (var s in bookWordStatusMap.values) {
        if (s != null && s.status == 1) rCount++;
      }
      reviewCount.value = rCount;
    }

    var time = (await wordDao.queryStudyTime()) ?? 0;
    var currentSession = DateTime.now().millisecondsSinceEpoch - (timeRecord.startTime ?? DateTime.now().millisecondsSinceEpoch);
    time += currentSession;
    studyTime.value = (time / 1000 / 60).toStringAsFixed(1) + " 分钟";
  }

  Future<void> fetchWords() async {
    String modeParam = Get.parameters['mode'] ?? 'new';
    if (modeParam == 'review') {
      // try to resume existing batch first
      var savedBatch = GetStorage().read('review_batch_${appService.bookId}');
      var savedPos = GetStorage().read('review_batch_pos_${appService.bookId}') ?? 0;
      if (savedBatch != null && savedBatch is List && savedBatch.isNotEmpty) {
        List<WordVO> batch = [];
        for (var id in savedBatch) {
          var wordData = appService.getWord(id);
          if (wordData != null) {
            var vo = appService.toWordVO(wordData);
            if (vo != null) batch.add(vo);
          }
        }
        if (batch.isNotEmpty && (savedPos as int) < batch.length) {
          playingWords = batch;
          playingIndex = savedPos;
          bookWordStatusMap = await studyService.fetchBookWordStatusMap();
          return;
        }
      }
      // create new batch
      int target = GetStorage().read('review_target_${appService.bookId}') ?? 20;
      int cycles = GetStorage().read('review_cycles_${appService.bookId}') ?? 3;
      playingWords = await studyService.createReviewBatch(target, cycles);
      playingIndex = 0;
      bookWordStatusMap = await studyService.fetchBookWordStatusMap();
    } else if (isManualMode.value) {
      playingWords = await studyService.fetchAllBookWords();
      bookWordStatusMap = await studyService.fetchBookWordStatusMap();
      _restorePosition();
    } else {
      var studyQueueMaxCount = appService.queueCount;
      playingWords = await studyService.fetchStudyQueueWords(studyQueueMaxCount);
      playingIndex = 0;
    }
  }

  void _loadManualWord() async {
    if (playingIndex >= 0 && playingIndex < playingWords.length) {
      word.value = playingWords[playingIndex];
      var wordId = word.value?.wordId;
      String modeParam = Get.parameters['mode'] ?? 'new';
      if (wordId != null) {
        var status = bookWordStatusMap[wordId];
        wordStatus.value = status;
        bool isLearned = (status?.status == 1) || ((status?.studyCycle ?? 0) > 0);

        isRevealed.value = modeParam == 'review' ? false : isLearned;
        if (isRevealed.value && appService.autoPlayVoice) {
          playWordSound(word.value?.word, 1);
        }
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
    if (playingWords.isNotEmpty && playingIndex >= 0 && playingIndex < playingWords.length) {
      String? wordId = playingWords[playingIndex].wordId;
      if (wordId != null) {
        GetStorage().write('study_cursor_manual_${appService.bookId}', wordId);
      }
    }
  }

  void _restorePosition() {
    String? savedWordId = GetStorage().read('study_cursor_manual_${appService.bookId}');
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
    var selectedRaw = GetStorage().read('review_batch_selected_${appService.bookId}');
    List<String> selected = selectedRaw != null
        ? List<String>.from(selectedRaw is List ? selectedRaw : [])
        : [];
    var roundDoneRaw = GetStorage().read('review_round_done_${appService.bookId}');
    List<String> roundDone = roundDoneRaw != null
        ? List<String>.from(roundDoneRaw is List ? roundDoneRaw : [])
        : [];
    for (var w in selected) {
      if (!roundDone.contains(w)) roundDone.add(w);
    }
    GetStorage().write('review_round_done_${appService.bookId}', roundDone);
    GetStorage().remove('review_batch_${appService.bookId}');
    GetStorage().remove('review_batch_pos_${appService.bookId}');
    GetStorage().remove('review_batch_selected_${appService.bookId}');
    int avail = GetStorage().read('review_round_done_${appService.bookId}') != null
        ? await studyService.getAvailableReviewCount()
        : selected.length;
    Get.dialog(
      AlertDialog(
        title: const Text("本批复习完成"),
        content: Text("共复习 ${selected.length} 个词，每词滚动 ${(playingWords.length / (selected.length > 0 ? selected.length : 1)).round()} 次${avail > 0 ? '\n还有 $avail 个词可复习' : '\n本轮全部完成！'}"),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              Get.offAllNamed("/main");
            },
            child: const Text("返回首页"),
          ),
          if (avail > 0)
            TextButton(
              onPressed: () {
                Get.back();
                _sessionPassedIds.clear();
                _init();
              },
              child: const Text("再复习一批"),
            ),
        ],
      ),
      barrierDismissible: false,
    );
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
          appService.wordService.wordMap[fetched.id!] = fetched;
        }
      }
      Get.snackbar("已添加", "《$spell》已加入顽固词汇", duration: const Duration(seconds: 1));
    } else {
      Get.snackbar("提示", "《$spell》已在顽固词汇中", duration: const Duration(seconds: 1));
    }
  }

  void openDifficultBook() async {
    await stopPlay();
    List<String> difficultWords = appService.wordService.getDifficultWords();
    print('[DIFFICULT] openDifficultBook called, words count=${difficultWords.length}');
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
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text("顽固词汇 (${difficultWords.length} 个)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.list_alt, color: Colors.teal),
              title: Text("查看顽固词汇列表", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              subtitle: Text("浏览所有已添加的顽固词汇", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
              onTap: () {
                Get.back();
                _showDifficultWordList();
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book, color: Colors.teal),
              title: Text("学习顽固词汇", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              subtitle: Text("进入学习模式，共 ${difficultWords.length} 个词", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
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
                  Expanded(child: Text("顽固词汇列表 (${vos.length})", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black))),
                  IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: vos.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(vos[i].word ?? "", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text((vos[i].means ?? []).join("；"), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 13)),
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
        if (fetched != null) appService.wordService.wordMap[fetched.id!] = fetched;
        w = fetched ?? Word(id: spell, word: spell, means: '暂无释义');
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
      if (status == null || status.status != 1) {
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

  void manualReveal() {
    if (isRevealed.value) return;
    isRevealed.value = true;
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
            player.wordStatus = await wordDao.queryWordStatus(wordId);
            wordStatus.value = player.wordStatus;
          }
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
          if (wordPlayCount > 3 || (cycle == 1 && wordPlayCount == 2) || cycle > 1) return;
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
          studyService.addWordStudyRecord(startTime, endTime, player.playComplete, status);
        }
        if (appService.autoPass) {
          var key = player.wordStatus?.word ?? "";
          var wordPlayCount = playCount[key] ?? 0;
          var cycle = player.wordStatus?.studyCycle ?? 0;
          if (wordPlayCount > 3 || (cycle == 1 && wordPlayCount == 2) || cycle > 1) {
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
      await studyService.pass(wId);
      if (!_sessionPassedIds.contains(wId)) {
        _sessionPassedIds.add(wId);
        sessionPassCount.value++;
      }
    }

    if (isManualMode.value) {
      if (wId != null) {
        var currentStatus = bookWordStatusMap[wId] ?? WordStatusPO(word: "${appService.bookId}_$wId");
        currentStatus.status = 1;
        currentStatus.studyCycle = (currentStatus.studyCycle ?? 0) + 1;
        bookWordStatusMap[wId] = currentStatus;
      }
      String modeParam = Get.parameters['mode'] ?? 'new';
      if (modeParam == 'review') {
        // advance batch position
        int pos = GetStorage().read('review_batch_pos_${appService.bookId}') ?? 0;
        GetStorage().write('review_batch_pos_${appService.bookId}', pos + 1);
        if (pos + 1 >= playingWords.length) {
          _completeReviewBatch();
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
        List<String> diffs = List<String>.from(storage.read('difficult_words') ?? []);
        diffs.remove(w);
        storage.write('difficult_words', diffs);
        Get.snackbar("彻底掌握", "《$w》已被斩草除根，主线也不再出现！", duration: const Duration(seconds: 1));
      }
      if (wId != null) {
        await studyService.delete(wId);
        int bIdx = _backupPlayingWords.indexWhere((e) => e.wordId == wId);
        if (bIdx != -1) {
          _backupPlayingWords.removeAt(bIdx);
          if (bIdx < _backupPlayingIndex) _backupPlayingIndex--;
          if (_backupPlayingWords.isEmpty) {
            _backupPlayingIndex = 0;
          } else if (_backupPlayingIndex >= _backupPlayingWords.length) {
            _backupPlayingIndex = _backupPlayingWords.length - 1;
          }
        }
      }
      playingWords.removeAt(playingIndex);
      if (playingWords.isEmpty) {
        word.value = null;
      } else {
        if (playingIndex >= playingWords.length) playingIndex = 0;
        _loadManualWord();
      }
      fetchCount();
      controlEnable.value = true;
      return;
    }

    if (wId != null) {
      await studyService.delete(wId);
      if (Get.isRegistered<SelectBookController>()) {
        Get.find<SelectBookController>().refreshBooks();
      }
    }

    if (isManualMode.value) {
      if (wId != null) {
        var currentStatus = bookWordStatusMap[wId] ?? WordStatusPO(word: wId);
        currentStatus.status = -1;
        bookWordStatusMap[wId] = currentStatus;
      }
      playingWords.removeAt(playingIndex);
      print('[DELETE] after removeAt: playingWords.length=${playingWords.length} playingIndex=$playingIndex');
      if (Get.parameters['mode'] == 'review') {
        List<String> newBatch = playingWords.map((e) => e.wordId!).toList();
        GetStorage().write('review_batch_${appService.bookId}', newBatch);
        int pos = GetStorage().read('review_batch_pos_${appService.bookId}') ?? 0;
        if (playingWords.isEmpty || pos >= playingWords.length) {
          _completeReviewBatch();
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
      print('[DELETE] after fetchCount: bookTotalCount=${bookTotalCount.value} bookLearnedCount=${bookLearnedCount.value}');
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

  Future<void> deleteByWord(String? w) async {
    if (isDifficultMode.value && w != null) {
      var storage = GetStorage();
      List<String> diffs = List<String>.from(storage.read('difficult_words') ?? []);
      diffs.remove(w);
      storage.write('difficult_words', diffs);
    }
    if (isDifficultMode.value) {
      int bIdx = _backupPlayingWords.indexWhere((e) => e.word == w);
      if (bIdx != -1) {
        _backupPlayingWords.removeAt(bIdx);
        if (bIdx < _backupPlayingIndex) _backupPlayingIndex--;
        if (_backupPlayingWords.isEmpty) {
          _backupPlayingIndex = 0;
        } else if (_backupPlayingIndex >= _backupPlayingWords.length) {
          _backupPlayingIndex = _backupPlayingWords.length - 1;
        }
      }
    }
    var wordIndex = playingWords.indexWhere((element) => element.word == w);
    if (wordIndex == -1) return;
    if (isManualMode.value) {
      playingWords.removeAt(wordIndex);
      if (wordIndex < playingIndex) playingIndex--;
      if (Get.parameters['mode'] == 'review') {
        List<String> newBatch = playingWords.map((e) => e.wordId!).toList();
        GetStorage().write('review_batch_${appService.bookId}', newBatch);
        int pos = GetStorage().read('review_batch_pos_${appService.bookId}') ?? 0;
        if (playingWords.isEmpty || pos >= playingWords.length) {
          _completeReviewBatch();
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
    } else {
      var nextW = await studyService.fetchNextWord();
      if (nextW != null) {
        playingWords[wordIndex] = nextW;
      } else {
        playingWords.removeAt(wordIndex);
        if (playingWords.isEmpty) word.value = null;
      }
    }
    if (Get.isRegistered<SelectBookController>()) {
      Get.find<SelectBookController>().refreshBooks();
    }
    await fetchCount();
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
      wordStatus.value = await wordDao.queryWordStatus(w.wordId ?? "");
    }
  }
}
