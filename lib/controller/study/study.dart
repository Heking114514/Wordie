import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/app/app.dart';
import 'package:english/service/study/study.dart';
import 'package:english/service/word/word.dart';
import 'package:english/view/review/list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        await const Duration(milliseconds: 100).delay();
        if (_playing == false) {
          break;
        }
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
      await const Duration(milliseconds: 100).delay();
      if (_playing == false) {
        break;
      }
    }
  }

  void _loop() async {
    for (; _start;) {
      startTime = DateTime.now().millisecondsSinceEpoch;
      playComplete = true;
      if (_start) await thinkStart(this);
      if (_start) await Duration(seconds: thinkTime).delay();
      if (_start) await thinkEnd(this);
      if (_start) await showStart(this);
      if (_start) await Duration(seconds: showTime).delay();
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

  _StudyTimeRecorder({
    this.startTime,
    this.endTime,
    required this.service,
  });
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
    switch (state) {
      case AppLifecycleState.resumed:
        timeRecord.recordStart();
        break;
      case AppLifecycleState.paused:
        stopPlay();
        timeRecord.recordEnd();
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.detached:
        break;
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
    await fetchWords();

    if (playingWords.isEmpty) {
      if (Get.parameters['mode'] == 'review') {
        Get.offAllNamed("/main");
        Get.snackbar("提示", "当前没有任何要复习的单词，快去学一些吧", snackPosition: SnackPosition.BOTTOM);
        return;
      }
    }

    await fetchCount();
    await startPlay();
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
    super.onClose();
    stopPlay();
  }

//   void onStudyComplete() async {
//     String mode = Get.parameters['mode'] ?? 'new';

//     // === 判断新词学习是否已经耗尽整本书 ===
//     if (mode == 'new') {
//       var unstudied = await wordDao.queryAllNotStudyWords(appService.bookId);
//       if (unstudied.isEmpty) {
//         Get.dialog(
//           AlertDialog(
//             title: const Text("本书已经学完", style: TextStyle(fontWeight: FontWeight.bold)),
//             content: const Text("恭喜你！这本词书的所有单词都已经学习完毕。\n您可以选择一种顺序重新学习本词书："),
//             actions:[
//               TextButton(onPressed: () { Get.back(); _restartBook('ASC'); }, child: const Text("正序重学(A-Z)")),
//               TextButton(onPressed: () { Get.back(); _restartBook('DESC'); }, child: const Text("倒序重学(Z-A)")),
//               TextButton(onPressed: () { Get.back(); _restartBook('RANDOM'); }, child: const Text("乱序重学")),
//               TextButton(onPressed: () => Get.offAllNamed("/main"), child: const Text("返回首页", style: TextStyle(color: Colors.grey))),
//             ],
//           ),
//           barrierDismissible: false,
//         );
//         return;
//       }
//     }

//     Get.dialog(
//       AlertDialog(
//         title: Text(mode == 'review' ? "复习完成" : "学习完成"),
//         content: Text(mode == 'review' ? "当前复习计划已完成，建议休息一下或继续下一组。" : "恭喜！新词学习任务已完成。"),
//         actions:[
//           if (mode == 'review') ...[
//             TextButton(onPressed: () { Get.back(); reviewTodayAgain(); }, child: const Text("再复习今天")),
//             TextButton(onPressed: () { Get.back(); _init(); }, child: const Text("复习下一天")),
//           ] else ...[
//             TextButton(onPressed: () { Get.back(); _init(); }, child: const Text("继续学习")),
//           ],
//           TextButton(onPressed: () => Get.offAllNamed("/main"), child: const Text("返回首页")),
//         ],
//       ),
//       barrierDismissible: false,
//     );
//   }
void reloadStudy() {
    _init();
  }

  // 3. 将私有方法 _restartBook 改为公开方法 restartBook
  void restartBook(String orderPref) async {
    // 清空当前词书进度
    await wordDao.clearBookProgress(appService.bookId);
    // 写入重学顺序偏好（服务层底层会按偏好对所有书都进行字典序编排）
    GetStorage().write('book_order_${appService.bookId}', orderPref);
    GetStorage().write('study_cursor_${appService.bookId}', '');
    GetStorage().write('study_cursor_desc_${appService.bookId}', '');
    // 返回首页，主页会自动刷新进度
    Get.offAllNamed("/main");
    Get.snackbar("重学已开启", "进度已重置，下次学习将按您的偏好顺序进行！", snackPosition: SnackPosition.BOTTOM);
  }

//   void _restartBook(String orderPref) async {
//     // 1. 清空当前词书进度
//     await wordDao.clearBookProgress(appService.bookId);
//     // 2. 写入重学顺序偏好（服务层底层会按偏好对所有书都进行 strictly compareTo 字典序编排）
//     GetStorage().write('book_order_${appService.bookId}', orderPref);
//     // 3. 返回首页，主页会自动刷新进度
//     Get.offAllNamed("/main");
//     Get.snackbar("重学已开启", "进度已重置，下次学习将按您的偏好顺序进行！", snackPosition: SnackPosition.BOTTOM);
//   }

  void reviewTodayAgain() async {
    var studyQueueMaxCount = appService.queueCount;
    playingWords = studyService.resetReviewBatch(studyQueueMaxCount);
    playingIndex = 0;
    if (playingWords.isEmpty) {
      Get.offAllNamed("/main");
      return;
    }
    await startPlay();
  }

  Future<void> fetchCount() async {
    var dailyCount = await wordDao.queryDailyPassWordCount();
    dailyStudyCount.value = dailyCount ?? 0;

    bookLearnedCount.value = await wordDao.queryProgressWordCount(appService.bookId) ?? 0;
    bookTotalCount.value = await wordDao.queryWordCount(appService.bookId) ?? 0;

    var rCount = await wordDao.queryAdapter.query(
      'select count(distinct word.word) as count from word_status status left join word word on word.word = status.word where status.status=1 and word.book=?1',
      mapper: (Map<String, Object?> row) => (row['count'] as int?) ?? 0,
      arguments:[appService.bookId]
    );
    reviewCount.value = rCount ?? 0;

    var time = (await wordDao.queryStudyTime()) ?? 0;
    var use = (time / 1000 / 60).toStringAsFixed(1);
    studyTime.value = use + " 分钟";
  }

  Future<void> fetchWords() async {
    var studyQueueMaxCount = appService.queueCount;
    var words = await studyService.fetchStudyQueueWords(studyQueueMaxCount);
    playingWords = words;
  }

  Future<void> fetchNextWord(int index) async {
    var next = await studyService.fetchNextWord();
    if (next != null) {
      playingWords[index] = next;
      playingIndex++;
      if (playingIndex >= playingWords.length) {
        playingIndex = 0;
      }
    } else {
      playingWords.removeAt(index);
      if (playingWords.isEmpty) {
        word.value = null; // 非常关键：赋空后会自动触发渲染 buildEndView，展现我们刚刚写的按钮！
        stopPlay();
      }
    }
  }

  Future<void> stopPlay() async {
    if (!playButtonEnable.value) return;
    thinking.value = false;
    playButtonEnable.value = false;
    player?.stop();
    playing.value = false;
    playButtonEnable.value = true;
  }

  Future<void> startPlay() async {
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
        
        if (index >= arr.length) {
          playingIndex = index = 0;
        }
        
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
      showStart: (Player player) async {
      },
      showEnd: (Player player) async {
        if (appService.autoPass == true) {
          var key = player.wordStatus?.word ?? "";
          var wordPlayCount = playCount[key] ?? 0;
          wordPlayCount++;
          playCount[key] = wordPlayCount;
          var cycle = player.wordStatus?.studyCycle ?? 0;
          if (wordPlayCount > 3 || (cycle == 1 && wordPlayCount == 2) || cycle > 1) {
            return;
          }
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
        if (appService.autoPass == true) {
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

  void next() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();
    playingIndex++;
    if (playingIndex >= playingWords.length) playingIndex = 0;
    await startPlay();
    await fetchCount();
    controlEnable.value = true;
  }

  void previous() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();
    playingIndex--;
    if (playingIndex < 0) playingIndex = max(playingWords.length - 1, 0);
    await startPlay();
    await fetchCount();
    controlEnable.value = true;
  }

  void pass() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();
    var word = this.word.value?.wordId;
    if (word != null) {
      await studyService.pass(word);
      sessionPassCount.value++;
    }
    await fetchNextWord(playingIndex);
    await startPlay();
    await fetchCount();
    controlEnable.value = true;
  }

  void delete() async {
    if (!controlEnable.value) return;
    controlEnable.value = false;
    await stopPlay();
    var word = this.word.value?.wordId;
    if (word != null) {
      await studyService.delete(word);
    }
    await fetchNextWord(playingIndex);
    await startPlay();
    await fetchCount();
    controlEnable.value = true;
  }

  Future<void> deleteByWord(String? word) async {
    var wordIndex = playingWords.indexWhere((element) => element.word == word);
    if (wordIndex == -1) return;
    await fetchNextWord(wordIndex);
    await fetchCount();
  }

  void togglePlay() async {
    if (playing.value) {
      await stopPlay();
    } else {
      await startPlay();
    }
  }

  void fetchWordStatus() async {
    var word = this.word.value;
    if (word != null) {
      wordStatus.value = await wordDao.queryWordStatus(word.wordId ?? "");
    }
  }
}