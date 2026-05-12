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
      sessionPassCount.value = GetStorage().read('review_passed_${appService.bookId}') ?? 0;
      reviewCount.value = GetStorage().read('review_target_${appService.bookId}') ?? 0;
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
    var studyQueueMaxCount = isManualMode.value ? 30 : appService.queueCount;
    playingWords = await studyService.fetchStudyQueueWords(studyQueueMaxCount);
    playingIndex = 0;
  }

  void _loadManualWord() async {
    if (playingIndex >= 0 && playingIndex < playingWords.length) {
      isRevealed.value = false;
      word.value = playingWords[playingIndex];
      var wordId = word.value?.wordId;
      if (wordId != null) wordStatus.value = await wordDao.queryWordStatus(wordId);
    } else {
      word.value = null;
    }
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
      } else {
        var nextW = await studyService.fetchNextWord();
        if (nextW != null) {
          playingWords.add(nextW);
          playingIndex++;
        } else {
          playingIndex++;
        }
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
      } else {
        Get.snackbar("提示", "已经是本次学习的第一个词了");
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
      sessionPassCount.value++;
    }

    if (isManualMode.value) {
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
