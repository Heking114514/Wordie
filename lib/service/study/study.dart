// lib/service/study/study.dart
import 'dart:math';

import 'package:english/dao/word/word.dart';
import 'package:english/entity/record/po/record.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/app/app.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../entity/word/po/word.dart';

class StudyService {
  AppService appService = Get.find();
  WordDao wordDao = Get.find();

  List<WordVO> _reviewBatch = [];
  int _reviewIndex = 0;

  Future<List<WordVO>> fetchStudyQueueWords(int studyQueueMaxCount) async {
    await appService.readWords();

    String mode = Get.parameters['mode'] ?? 'new';

    if (mode == 'review') {
      String today = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
      String savedDate = GetStorage().read('review_date_${appService.bookId}') ?? '';

      if (savedDate != today) {
        String prefix = "${appService.bookId}_%";
        var statuses = await wordDao.queryAdapter.queryList(
          'select * from word_status where status = 1 and word like ?1',
          mapper: (Map<String, Object?> row) => WordStatusPO(word: row['word'] as String?),
          arguments: [prefix]
        );
        List<WordPO> dailyBatch = statuses.map((s) {
          var wordText = s.word!.split('_').sublist(1).join('_');
          return WordPO(id: 0, word: wordText, book: appService.bookId.toString());
        }).toList();

        dailyBatch.shuffle();
        int target = appService.reviewDailyCount;
        dailyBatch = dailyBatch.take(target).toList();

        _reviewBatch = dailyBatch.map((e) => toWord(e)).whereType<WordVO>().toList();

        List<String> ids = _reviewBatch.map((e) => e.wordId!).toList();
        GetStorage().write('review_date_${appService.bookId}', today);
        GetStorage().write('review_queue_${appService.bookId}', ids);
        GetStorage().write('review_passed_${appService.bookId}', 0);
        GetStorage().write('review_target_${appService.bookId}', ids.length);
      } else {
        List<dynamic> savedIds = GetStorage().read('review_queue_${appService.bookId}') ?? [];
        _reviewBatch = [];
        for (var id in savedIds) {
          var wordData = appService.getWord(id);
          if (wordData != null) {
            var vo = appService.toWordVO(wordData);
            if (vo != null) _reviewBatch.add(vo);
          }
        }
      }

      _reviewIndex = 0;
      var batch = _reviewBatch.take(studyQueueMaxCount).toList();
      _reviewIndex = batch.length;
      return batch;

    } else {
      bool isCustom = appService.wordService.customBookNames.contains(appService.bookName);
      String orderPref = GetStorage().read('book_order_${appService.bookId}') ?? (isCustom ? 'ASC' : 'RANDOM');
      bool isAsc = orderPref.contains('ASC');
      bool isDesc = orderPref.contains('DESC');

      var allBookWords = await wordDao.queryWords(appService.bookId);
      var statusMap = await fetchBookWordStatusMap();

      List<WordVO> studyingBatch = [];
      List<WordVO> unstudiedBatch = [];

      for (var po in allBookWords) {
        var status = statusMap[po.word];
        if (status == null) {
           var vo = toWord(po);
           if (vo != null) unstudiedBatch.add(vo);
        } else if (status.status == 0) {
           var vo = toWord(po);
           if (vo != null) studyingBatch.add(vo);
        }
      }

      List<WordVO> batch = List.from(studyingBatch);

      if (batch.length < studyQueueMaxCount) {
        if (isAsc) {
          String cursor = GetStorage().read('study_cursor_${appService.bookId}') ?? '';
          var filtered = unstudiedBatch.where((w) => (w.word ?? '').compareTo(cursor) > 0).toList();
          if (filtered.isEmpty && unstudiedBatch.isNotEmpty) {
            cursor = '';
            GetStorage().write('study_cursor_${appService.bookId}', '');
            filtered = unstudiedBatch;
          }
          filtered.sort((a, b) => (a.word ?? '').compareTo(b.word ?? ''));
          unstudiedBatch = filtered;
        } else if (isDesc) {
          String cursor = GetStorage().read('study_cursor_desc_${appService.bookId}') ?? '';
          var filtered = unstudiedBatch.where((w) {
            if (cursor.isEmpty) return true;
            return (w.word ?? '').compareTo(cursor) < 0;
          }).toList();
          if (filtered.isEmpty && unstudiedBatch.isNotEmpty) {
            cursor = '';
            GetStorage().write('study_cursor_desc_${appService.bookId}', '');
            filtered = unstudiedBatch;
          }
          filtered.sort((a, b) => (b.word ?? '').compareTo(a.word ?? ''));
          unstudiedBatch = filtered;
        } else {
          unstudiedBatch.shuffle();
        }

        var needed = studyQueueMaxCount - batch.length;
        var toAdd = unstudiedBatch.take(needed).toList();
        batch.addAll(toAdd);

        for (var word in toAdd) {
          await _markWordAsStudying(word.wordId);
          if (isAsc) {
            GetStorage().write('study_cursor_${appService.bookId}', word.word);
          } else if (isDesc) {
            GetStorage().write('study_cursor_desc_${appService.bookId}', word.word);
          }
        }
      } else {
        batch = batch.take(studyQueueMaxCount).toList();
      }

      if (isAsc) {
        batch.sort((a, b) => (a.word ?? '').compareTo(b.word ?? ''));
      } else if (isDesc) {
        batch.sort((a, b) => (b.word ?? '').compareTo(a.word ?? ''));
      } else {
        batch.shuffle();
      }
      return batch;
    }
  }

  Future<WordVO?> fetchNextWord() async {
    String mode = Get.parameters['mode'] ?? 'new';

    if (mode == 'review') {
      if (_reviewIndex < _reviewBatch.length) {
        var word = _reviewBatch[_reviewIndex];
        _reviewIndex++;
        return word;
      }
      return null;
    } else {
      bool isCustom = appService.wordService.customBookNames.contains(appService.bookName);
      String defaultOrder = isCustom ? 'ASC' : 'RANDOM';
      String orderPref = GetStorage().read('book_order_${appService.bookId}') ?? defaultOrder;
      bool isAsc = orderPref.contains('ASC');
      bool isDesc = orderPref.contains('DESC');

      var allBookWords = await wordDao.queryWords(appService.bookId);
      var statusMap = await fetchBookWordStatusMap();

      List<WordVO> allUnstudied = [];
      for (var po in allBookWords) {
        if (!statusMap.containsKey(po.word)) {
           var vo = toWord(po);
           if (vo != null) allUnstudied.add(vo);
        }
      }

      if (isAsc) {
        String cursor = GetStorage().read('study_cursor_${appService.bookId}') ?? '';
        var filtered = allUnstudied.where((w) => (w.word ?? '').compareTo(cursor) > 0).toList();
        if (filtered.isEmpty && allUnstudied.isNotEmpty) {
          cursor = '';
          GetStorage().write('study_cursor_${appService.bookId}', '');
          filtered = allUnstudied;
        }
        filtered.sort((a, b) => (a.word ?? '').compareTo(b.word ?? ''));
        allUnstudied = filtered;
      } else if (isDesc) {
        String cursor = GetStorage().read('study_cursor_desc_${appService.bookId}') ?? '';
        var filtered = allUnstudied.where((w) {
          if (cursor.isEmpty) return true;
          return (w.word ?? '').compareTo(cursor) < 0;
        }).toList();
        if (filtered.isEmpty && allUnstudied.isNotEmpty) {
          cursor = '';
          GetStorage().write('study_cursor_desc_${appService.bookId}', '');
          filtered = allUnstudied;
        }
        filtered.sort((a, b) => (b.word ?? '').compareTo(a.word ?? ''));
        allUnstudied = filtered;
      } else {
        allUnstudied.shuffle();
      }

      if (allUnstudied.isEmpty) return null;
      var nextWord = allUnstudied.first;
      await _markWordAsStudying(nextWord.wordId);
      if (isAsc) GetStorage().write('study_cursor_${appService.bookId}', nextWord.word);
      else if (isDesc) GetStorage().write('study_cursor_desc_${appService.bookId}', nextWord.word);
      return nextWord;
    }
  }

  List<WordVO> resetReviewBatch(int studyQueueMaxCount) {
    GetStorage().remove('review_date_${appService.bookId}');
    return [];
  }

  WordVO? toWord(WordPO po) {
    var word = appService.getWord(po.word);
    if (word != null) {
      return WordVO(
        wordId: po.word, word: word.word, usaVoice: word.usVoice, ukVoice: word.ukVoice,
        means: word.means?.split("\n"),
        sentence: () { var len = word.sentences?.length ?? 0; if (len > 0) return word.sentences?[0].sentence; }(),
        sentenceMeans: () { var len = word.sentences?.length ?? 0; if (len > 0) return word.sentences?[0].sentenceCn; }(),
      );
    }
    return null;
  }

  Future<List<WordVO>> fetchAllBookWords() async {
    await appService.readWords();
    String mode = Get.parameters['mode'] ?? 'new';

    if (mode == 'review') {
      String prefix = "${appService.bookId}_%";
      var statuses = await wordDao.queryAdapter.queryList(
        'select * from word_status where status = 1 and word like ?1 order by updateTime ASC',
        mapper: (Map<String, Object?> row) => WordStatusPO(
          word: row['word'] as String?,
          status: row['status'] as int?,
        ),
        arguments: [prefix]
      );
      List<WordVO> result = [];
      for (var s in statuses) {
        var wordText = s.word!.split('_').sublist(1).join('_');
        var po = WordPO(id: 0, word: wordText, book: appService.bookId.toString());
        var vo = toWord(po);
        if (vo != null) result.add(vo);
      }
      return result;
    } else {
      bool isCustom = appService.wordService.customBookNames.contains(appService.bookName);
      String orderPref = GetStorage().read('book_order_${appService.bookId}') ?? (isCustom ? 'ASC' : 'RANDOM');
      bool isAsc = orderPref.contains('ASC');
      bool isDesc = orderPref.contains('DESC');

      var allBookWords = await wordDao.queryWords(appService.bookId);
      var statusMap = await fetchBookWordStatusMap();

      List<WordVO> result = [];
      for (var po in allBookWords) {
        var status = statusMap[po.word];
        if (status != null && status.status == -1) continue;

        var wordData = appService.getWord(po.word);
        if (wordData != null) {
          var vo = appService.toWordVO(wordData);
          if (vo != null) result.add(vo);
        }
      }

      if (isAsc) {
        result.sort((a, b) => (a.word ?? '').compareTo(b.word ?? ''));
      } else if (isDesc) {
        result.sort((a, b) => (b.word ?? '').compareTo(a.word ?? ''));
      } else {
        result.shuffle();
      }
      return result;
    }
  }

  Future<int> getAvailableReviewCount() async {
    var roundDoneRaw = GetStorage().read('review_round_done_${appService.bookId}');
    List<String> roundDone = roundDoneRaw != null
        ? List<String>.from(roundDoneRaw is List ? roundDoneRaw : [])
        : [];
    String prefix = "${appService.bookId}_%";
    var statuses = await wordDao.queryAdapter.queryList(
      'select * from word_status where status = 1 and word like ?1',
      mapper: (Map<String, Object?> row) => WordStatusPO(word: row['word'] as String?),
      arguments: [prefix]
    );
    return statuses.length - roundDone.length;
  }

  Future<List<WordVO>> createReviewBatch(int targetCount, int cycles) async {
    await appService.readWords();
    var roundDoneRaw = GetStorage().read('review_round_done_${appService.bookId}');
    List<String> roundDone = roundDoneRaw != null
        ? List<String>.from(roundDoneRaw is List ? roundDoneRaw : [])
        : [];

    String prefix = "${appService.bookId}_%";
    var statuses = await wordDao.queryAdapter.queryList(
      'select * from word_status where status = 1 and word like ?1 order by updateTime ASC',
      mapper: (Map<String, Object?> row) => WordStatusPO(word: row['word'] as String?),
      arguments: [prefix]
    );

    if (roundDone.length >= statuses.length) {
      roundDone.clear();
      GetStorage().write('review_round_done_${appService.bookId}', roundDone);
    }

    var available = statuses.where((s) {
      var w = s.word!.split('_').sublist(1).join('_');
      return !roundDone.contains(w);
    }).toList();

    if (available.isEmpty) return [];

    available.shuffle();
    int N = targetCount < available.length ? targetCount : available.length;
    var selected = available.take(N).toList();

    List<WordVO> batch = [];
    for (int c = 0; c < cycles; c++) {
      selected.shuffle();
      for (var s in selected) {
        var wordText = s.word!.split('_').sublist(1).join('_');
        var po = WordPO(id: 0, word: wordText, book: appService.bookId.toString());
        var vo = toWord(po);
        if (vo != null) batch.add(vo);
      }
    }

    GetStorage().write('review_batch_${appService.bookId}',
        batch.map((e) => e.wordId).toList());
    GetStorage().write('review_batch_pos_${appService.bookId}', 0);
    GetStorage().write('review_batch_selected_${appService.bookId}',
        selected.map((e) {
      return e.word!.split('_').sublist(1).join('_');
    }).toList());
    return batch;
  }

  Future<Map<String, WordStatusPO?>> fetchBookWordStatusMap() async {
    var statuses = await wordDao.queryWordStatusByBook(appService.bookId);
    Map<String, WordStatusPO?> map = {};
    for (var s in statuses) {
      if (s.word != null) {
        var parts = s.word!.split('_');
        if (parts.length > 1) {
          map[parts.sublist(1).join('_')] = s;
        } else {
          map[s.word!] = s;
        }
      }
    }
    return map;
  }

  Future<void> _markWordAsStudying(String? wordId) async {
    String wordKey = "${appService.bookId}_$wordId";
    var existing = await wordDao.queryWordStatus(wordKey);
    if (existing == null) {
      await wordDao.createWordStatus(WordStatusPO(
        word: wordKey, status: 0, studyCycle: 0, nextReviewTime: 0,
        createTime: DateTime.now().millisecondsSinceEpoch, updateTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } else {
      existing.status = 0; existing.updateTime = DateTime.now().millisecondsSinceEpoch;
      await wordDao.updateStatus(existing);
    }
  }

  Future<void> pass(String word) async {
    String wordKey = "${appService.bookId}_$word";
    var status = await wordDao.queryWordStatus(wordKey);
    if (status == null) {
      await wordDao.createWordStatus(WordStatusPO(
        word: wordKey, status: 1, studyCycle: 1, nextReviewTime: 0,
        createTime: DateTime.now().millisecondsSinceEpoch, updateTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } else {
      status.status = 1;
      status.studyCycle = (status.studyCycle ?? 0) + 1;
      status.nextReviewTime = 0;
      status.updateTime = DateTime.now().millisecondsSinceEpoch;
      await wordDao.updateStatus(status);
    }
  }

  Future<void> delete(String word) async {
    String wordKey = "${appService.bookId}_$word";
    var status = await wordDao.queryWordStatus(wordKey);
    if (status == null) {
      await wordDao.createWordStatus(WordStatusPO(
        word: wordKey, status: -1, studyCycle: 0, nextReviewTime: 0,
        createTime: DateTime.now().millisecondsSinceEpoch, updateTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } else {
      status.status = -1;
      status.updateTime = DateTime.now().millisecondsSinceEpoch;
      await wordDao.updateStatus(status);
    }
  }

  Future<void> addWordStudyRecord(int startTime, int endTime, bool playComplete, WordStatusPO status) async {
    wordDao.addWordStudyTimeRecord(WordStudyTimeCountPO(
      word: status.word, startTime: startTime, endTime: endTime, studyCycle: status.studyCycle, playComplete: playComplete ? 1 : 0,
    ));
  }

  Future<void> addStudyRecord(int startTime, int endTime) async {
    wordDao.addStudyTimeRecord(StudyTimeCountPO(startTime: startTime, endTime: endTime));
  }
}
