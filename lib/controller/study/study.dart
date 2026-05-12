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
import '../../util/audio.dart';

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
    _init();
  }

  Future<void> fetchCount() async {
    dailyStudyCount.value = (await wordDao.queryDailyPassWordCount()) ?? 0;

    bookLearnedCount.value = await wordDao.queryProgressWordCount(appService.bookId) ?? 0;
    bookTotalCount.value = await wordDao.queryWordCount(appService.bookId) ?? 0;

    if (Get.parameters['mode'] == 'review') {
      reviewCount.value = playingWords.length;
    } else {
      var rCount = await wordDao.queryAdapter.query(
        'select count(distinct word.word) as count from word_status status left join word word on word.word = status.word where status.status=1 and word.book=?1',
        mapper: (Map<String, Object?> row) => (row['count'] as int?) ?? 0,
        arguments:[appService.bookId]
      );
      reviewCount.value = rCount ?? 0;
    }

    var time = (await wordDao.queryStudyTime()) ?? 0;
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
      }
      _loadManualWord();
    } else {
      playingIndex++;
      if (playingIndex >= playingWords.length) playingIndex = 0;
      await startPlay();
    }

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
      }
    } else {
      playingIndex--;
      if (playingIndex < 0) playingIndex = max(playingWords.length - 1, 0);
      await startPlay();
    }

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
        var currentStatus = bookWordStatusMap[wId] ?? WordStatusPO(word: wId);
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
    if (wId != null) await studyService.delete(wId);

    if (isManualMode.value) {
      if (wId != null) {
        var currentStatus = bookWordStatusMap[wId] ?? WordStatusPO(word: wId);
        currentStatus.status = -1;
        bookWordStatusMap[wId] = currentStatus;
      }
      playingWords.removeAt(playingIndex);
      if (playingIndex >= playingWords.length) {
        playingIndex = (playingWords.length - 1).clamp(0, playingWords.length - 1);
      }
      controlEnable.value = true;
      _loadManualWord();
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

  Future<void> deleteByWord(String? w) async {
    var wordIndex = playingWords.indexWhere((element) => element.word == w);
    if (wordIndex == -1) return;
    if (isManualMode.value) {
      playingWords.removeAt(wordIndex);
      if (playingIndex >= playingWords.length) {
        playingIndex = max(playingWords.length - 1, 0);
      }
      _loadManualWord();
    } else {
      var nextW = await studyService.fetchNextWord();
      if (nextW != null) {
        playingWords[wordIndex] = nextW;
      } else {
        playingWords.removeAt(wordIndex);
        if (playingWords.isEmpty) word.value = null;
      }
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
