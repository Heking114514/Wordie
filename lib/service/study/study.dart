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

  List<WordVO> _reviewBatch =[];
  int _reviewIndex = 0;

  Future<List<WordVO>> fetchStudyQueueWords(int studyQueueMaxCount) async {
    String mode = Get.parameters['mode'] ?? 'new';

    if (mode == 'review') {
      var dailyBatch = await wordDao.queryAdapter.queryList(
        'select word.* from word_status status left join word word on word.word = status.word where status.status = 1 and word.book=?1 group by word.word order by status.updateTime ASC limit ?2',
        mapper: (Map<String, Object?> row) => WordPO(id: row['id'] as int?, word: row['word'] as String?, book: row['book'] as String?),
        arguments: [appService.bookId, appService.reviewDailyCount]
      );
      if (dailyBatch.isEmpty) return [];
      dailyBatch.shuffle();
      _reviewBatch = dailyBatch.map((e) => toWord(e)).whereType<WordVO>().toList();
      _reviewIndex = 0;
      var batch = _reviewBatch.take(studyQueueMaxCount).toList();
      _reviewIndex = batch.length;
      return batch;
    } else {
      bool isCustom = appService.wordService.customBookNames.contains(appService.bookName);
      String orderPref = GetStorage().read('book_order_${appService.bookId}') ?? (isCustom ? 'ASC' : 'RANDOM');
      bool isAsc = orderPref.contains('ASC');
      bool isDesc = orderPref.contains('DESC');

      // 1. 获取处于正在学习状态的单词 (status = 0)
      var studyingPOs = await wordDao.queryAdapter.queryList(
        'select word.* from word_status status left join word word on word.word = status.word where status.status = 0 and word.book = ?1 group by word.word',
        mapper: (Map<String, Object?> row) => WordPO(id: row['id'] as int?, word: row['word'] as String?, book: row['book'] as String?),
        arguments:[appService.bookId]
      );

      List<WordVO> batch = [];
      for (var po in studyingPOs) {
        var vo = toWord(po);
        if (vo != null) batch.add(vo);
      }

      // 2. 如果不足，继续从新的未学单词里取
      if (batch.length < studyQueueMaxCount) {
        var unstudiedPOs = await wordDao.queryAllNotStudyWords(appService.bookId);
        List<WordVO> allUnstudied = [];
        for (var po in unstudiedPOs) {
          var vo = toWord(po);
          if (vo != null) allUnstudied.add(vo);
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

        var needed = studyQueueMaxCount - batch.length;
        var toAdd = allUnstudied.take(needed).toList();
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

      var allUnstudiedPOs = await wordDao.queryAllNotStudyWords(appService.bookId);
      if (allUnstudiedPOs.isEmpty) return null;

      List<WordVO> allUnstudied = [];
      for (var po in allUnstudiedPOs) {
        var vo = toWord(po);
        if (vo != null) allUnstudied.add(vo);
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

      if (isAsc) {
        GetStorage().write('study_cursor_${appService.bookId}', nextWord.word);
      } else if (isDesc) {
        GetStorage().write('study_cursor_desc_${appService.bookId}', nextWord.word);
      }

      return nextWord;
    }
  }

  List<WordVO> resetReviewBatch(int studyQueueMaxCount) {
    _reviewBatch.shuffle(); 
    _reviewIndex = 0;
    var batch = _reviewBatch.take(studyQueueMaxCount).toList();
    _reviewIndex = batch.length;
    return batch;
  }

  WordVO? toWord(WordPO po) {
    var word = appService.getWord(po.word);
    if (word != null) {
      return WordVO(
        wordId: po.word,
        word: word.word,
        usaVoice: word.usVoice,
        ukVoice: word.ukVoice,
        means: word.means?.split("\n"),
        sentence: () {
          var len = word.sentences?.length ?? 0;
          if (len > 0) return word.sentences?[0].sentence;
        }(),
        sentenceMeans: () {
          var len = word.sentences?.length ?? 0;
          if (len > 0) return word.sentences?[0].sentenceCn;
        }(),
      );
    }
    return null;
  }

  Future<void> _markWordAsStudying(String? wordId) async {
    var existing = await wordDao.queryWordStatus(wordId ?? '');
    if (existing == null) {
      await wordDao.createWordStatus(WordStatusPO(
        word: wordId,
        status: 0,
        studyCycle: 0,
        nextReviewTime: 0,
        createTime: DateTime.now().millisecondsSinceEpoch,
        updateTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } else {
      existing.status = 0;
      existing.updateTime = DateTime.now().millisecondsSinceEpoch;
      await wordDao.updateStatus(existing);
    }
  }

  Future<void> pass(String word) async {
    var status = await wordDao.queryWordStatus(word);
    if (status != null) {
      status.status = 1;
      status.studyCycle = (status.studyCycle ?? 0) + 1;
      status.nextReviewTime = 0;
      status.updateTime = DateTime.now().millisecondsSinceEpoch;
      await wordDao.updateStatus(status);
    }
  }

  Future<void> delete(String word) async {
    var status = await wordDao.queryWordStatus(word);
    if (status != null) {
      status.status = -1;
      status.updateTime = DateTime.now().millisecondsSinceEpoch;
      await wordDao.updateStatus(status);
    }
  }

  Future<void> addWordStudyRecord(int startTime, int endTime, bool playComplete, WordStatusPO status) async {
    wordDao.addWordStudyTimeRecord(WordStudyTimeCountPO(
      word: status.word,
      startTime: startTime,
      endTime: endTime,
      studyCycle: status.studyCycle,
      playComplete: playComplete ? 1 : 0,
    ));
  }

  Future<void> addStudyRecord(int startTime, int endTime) async {
    wordDao.addStudyTimeRecord(StudyTimeCountPO(
      startTime: startTime,
      endTime: endTime,
    ));
  }
}