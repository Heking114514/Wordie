// lib/service/study/study.dart
import 'dart:math';

import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/app/app.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../entity/word/po/word.dart';
import '../../util/time.dart';

class StudyService {
  AppService appService = Get.find();
  WordDao wordDao = Get.find();

  List<WordVO> _reviewBatch = [];
  int _reviewIndex = 0;

  String get _reviewStatsKey => 'review_word_stats_${appService.bookId}';

  String _wordIdFromStatusKey(String statusKey) {
    final prefix = '${appService.bookId}_';
    return statusKey.startsWith(prefix)
        ? statusKey.substring(prefix.length)
        : statusKey;
  }

  String _normalizeWordId(String storedValue) {
    final word = appService.getWord(storedValue) ??
        appService.getWordBySpell(storedValue);
    return word?.id ?? storedValue;
  }

  Future<List<String>> _readNormalizedReviewIds(
    String key, {
    bool deduplicate = true,
  }) async {
    await appService.readWords();
    final storage = GetStorage();
    final raw = storage.read(key);
    if (raw is! List) return [];

    final migrated = raw
        .map((value) => _normalizeWordId(value.toString()))
        .where((value) => value.isNotEmpty)
        .toList();
    final normalized = deduplicate ? migrated.toSet().toList() : migrated;
    final original = raw.map((value) => value.toString()).toList();
    if (original.length != normalized.length ||
        original.asMap().entries.any(
              (entry) => entry.value != normalized[entry.key],
            )) {
      await storage.write(key, normalized);
    }
    return normalized;
  }

  Future<List<String>> normalizeReviewIds(
    String key, {
    bool deduplicate = true,
  }) {
    return _readNormalizedReviewIds(key, deduplicate: deduplicate);
  }

  Future<List<WordVO>> _reviewWordsForIds(Iterable<String> ids) async {
    await appService.readWords();
    final words = <WordVO>[];
    for (final id in ids) {
      final wordData = appService.getWord(id);
      final vo = appService.toWordVO(wordData);
      if (vo != null) {
        vo.wordId = id;
        words.add(vo);
      }
    }
    return words;
  }

  Map<String, dynamic> _readReviewStats() {
    final raw = GetStorage().read(_reviewStatsKey);
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  int _lastReviewTime(Map<String, dynamic> stats, String wordId) {
    final value = stats[wordId];
    if (value is Map) {
      return int.tryParse('${value['lastReviewTime'] ?? 0}') ?? 0;
    }
    return 0;
  }

  Future<void> ensureTodayReviewState() async {
    final storage = GetStorage();
    final dateKey = 'review_date_${appService.bookId}';
    final today = getDayKey();
    if (storage.read(dateKey) == today) return;

    for (final key in <String>[
      'review_round_done_${appService.bookId}',
      'review_batch_${appService.bookId}',
      'review_batch_key_${appService.bookId}',
      'review_batch_pos_${appService.bookId}',
      'review_batch_selected_${appService.bookId}',
      'review_queue_${appService.bookId}',
      'review_passed_${appService.bookId}',
      'ai_article_cache_${appService.bookId}',
    ]) {
      await storage.remove(key);
    }
    await storage.write(dateKey, today);
  }

  Future<List<WordStatusPO>> fetchTodayReviewStatuses() async {
    await ensureTodayReviewState();
    return _bookReviewStatuses();
  }

  Future<List<WordStatusPO>> _bookReviewStatuses() async {
    final reviewStatuses = await wordDao.queryTodayReviewStatuses(
      appService.bookId,
    );
    reviewStatuses.sort(
      (a, b) => (a.updateTime ?? 0).compareTo(b.updateTime ?? 0),
    );
    return reviewStatuses;
  }

  Future<int> todayLearnedCount() async {
    await ensureTodayReviewState();
    return (await _bookReviewStatuses()).length;
  }

  Future<List<WordVO>> fetchStudyQueueWords(int studyQueueMaxCount) async {
    await appService.readWords();

    String mode = Get.parameters['mode'] ?? 'new';

    if (mode == 'review') {
      await ensureTodayReviewState();
      final savedIds = await _readNormalizedReviewIds(
        'review_batch_${appService.bookId}',
        deduplicate: false,
      );
      final reviewableIds = (await _bookReviewStatuses())
          .map((status) => _wordIdFromStatusKey(status.word ?? ''))
          .where((id) => id.isNotEmpty)
          .toSet();
      final validSavedIds =
          savedIds.where((id) => reviewableIds.contains(id)).toList();
      if (validSavedIds.length != savedIds.length) {
        await GetStorage().write(
          'review_batch_${appService.bookId}',
          validSavedIds,
        );
      }
      _reviewBatch = validSavedIds.isEmpty
          ? await createReviewBatch(appService.reviewDailyCount, 1)
          : await _reviewWordsForIds(validSavedIds);

      _reviewIndex = 0;
      var batch = _reviewBatch.take(studyQueueMaxCount).toList();
      _reviewIndex = batch.length;
      return batch;
    } else {
      bool isCustom =
          appService.wordService.customBookNames.contains(appService.bookName);
      String orderPref = GetStorage().read('book_order_${appService.bookId}') ??
          (isCustom ? 'ASC' : 'RANDOM');
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

      // ==== 兜底：若 DB 结果全部无法匹配，直接从 bookMap 构建 unstudiedBatch ====
      if (unstudiedBatch.isEmpty &&
          studyingBatch.isEmpty &&
          allBookWords.isNotEmpty &&
          isCustom) {
        unstudiedBatch = _buildUnstudiedFromBookMap(statusMap);
      }
      // 兜底：DB 本身就没有词时，也从 bookMap 兜底
      if (unstudiedBatch.isEmpty &&
          studyingBatch.isEmpty &&
          allBookWords.isEmpty &&
          isCustom) {
        unstudiedBatch = _buildUnstudiedFromBookMap(statusMap);
      }

      if (batch.length < studyQueueMaxCount) {
        if (isAsc) {
          String cursor =
              GetStorage().read('study_cursor_${appService.bookId}') ?? '';
          var filtered = unstudiedBatch
              .where((w) => (w.word ?? '').compareTo(cursor) > 0)
              .toList();
          if (filtered.isEmpty && unstudiedBatch.isNotEmpty) {
            cursor = '';
            GetStorage().write('study_cursor_${appService.bookId}', '');
            filtered = unstudiedBatch;
          }
          filtered.sort((a, b) => (a.word ?? '').compareTo(b.word ?? ''));
          unstudiedBatch = filtered;
        } else if (isDesc) {
          String cursor =
              GetStorage().read('study_cursor_desc_${appService.bookId}') ?? '';
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
            GetStorage()
                .write('study_cursor_desc_${appService.bookId}', word.word);
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
      bool isCustom =
          appService.wordService.customBookNames.contains(appService.bookName);
      String defaultOrder = isCustom ? 'ASC' : 'RANDOM';
      String orderPref =
          GetStorage().read('book_order_${appService.bookId}') ?? defaultOrder;
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
        String cursor =
            GetStorage().read('study_cursor_${appService.bookId}') ?? '';
        var filtered = allUnstudied
            .where((w) => (w.word ?? '').compareTo(cursor) > 0)
            .toList();
        if (filtered.isEmpty && allUnstudied.isNotEmpty) {
          cursor = '';
          GetStorage().write('study_cursor_${appService.bookId}', '');
          filtered = allUnstudied;
        }
        filtered.sort((a, b) => (a.word ?? '').compareTo(b.word ?? ''));
        allUnstudied = filtered;
      } else if (isDesc) {
        String cursor =
            GetStorage().read('study_cursor_desc_${appService.bookId}') ?? '';
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
      if (isAsc)
        GetStorage().write('study_cursor_${appService.bookId}', nextWord.word);
      else if (isDesc)
        GetStorage()
            .write('study_cursor_desc_${appService.bookId}', nextWord.word);
      return nextWord;
    }
  }

  /// 兜底：当 DB 查不到词或所有词都无法匹配时，直接从 bookMap 构建 unstudiedBatch
  List<WordVO> _buildUnstudiedFromBookMap(
      Map<String, WordStatusPO?> statusMap) {
    var book = appService.wordService.bookMap[appService.bookName];
    if (book == null || book.words == null) return [];

    List<WordVO> unstudied = [];
    for (var w in book.words!) {
      if (w.id == null) continue;
      var status = statusMap[w.id];
      if (status == null) {
        var vo = appService.toWordVO(w);
        if (vo != null) unstudied.add(vo);
      }
    }
    return unstudied;
  }

  WordVO? toWord(WordPO po) {
    var word = appService.getWord(po.word);
    if (word == null) {
      // 兜底：按拼写查找（DB 中存储的可能是词典 ID 而非拼写）
      word = appService.getWordBySpell(po.word);
    }
    if (word != null) {
      var len = word.sentences?.length ?? 0;
      return WordVO(
        wordId: po.word,
        word: word.word,
        usaVoice: word.usVoice,
        ukVoice: word.ukVoice,
        means: word.means?.split("\n"),
        sentence: len > 0 ? word.sentences![0].sentence : null,
        sentenceMeans: len > 0 ? word.sentences![0].sentenceCn : null,
      );
    }
    return null;
  }

  Future<List<WordVO>> fetchAllBookWords() async {
    await appService.readWords();
    String mode = Get.parameters['mode'] ?? 'new';

    if (mode == 'review') {
      await ensureTodayReviewState();
      var statuses = await _bookReviewStatuses();
      List<WordVO> result = [];
      for (var s in statuses) {
        var wordText = s.word!.split('_').sublist(1).join('_');
        var po =
            WordPO(id: 0, word: wordText, book: appService.bookId.toString());
        var vo = toWord(po);
        if (vo != null) result.add(vo);
      }
      return result;
    } else {
      bool isCustom =
          appService.wordService.customBookNames.contains(appService.bookName);
      String orderPref = GetStorage().read('book_order_${appService.bookId}') ??
          (isCustom ? 'ASC' : 'RANDOM');
      bool isAsc = orderPref.contains('ASC');
      bool isDesc = orderPref.contains('DESC');

      var allBookWords = await wordDao.queryWords(appService.bookId);
      var statusMap = await fetchBookWordStatusMap();

      List<WordVO> result = [];
      for (var po in allBookWords) {
        final status = statusMap[po.word];
        if ((status?.status ?? 0) < 0) continue;

        var wordData = appService.getWord(po.word);
        if (wordData != null) {
          var vo = appService.toWordVO(wordData);
          if (vo != null) result.add(vo);
        } else {
          // DB 中有词但在 wordMap/spellMap 找不到，尝试按拼写查找
          var bySpell = appService.getWordBySpell(po.word);
          if (bySpell != null) {
            var vo = appService.toWordVO(bySpell);
            if (vo != null) {
              vo.wordId = po.word; // 保留原始 wordId 以免后续状态追踪断裂
              result.add(vo);
            }
          }
        }
      }

      // ==== 兜底：若 DB 返回空或所有词都无法匹配，直接从 bookMap 构建 ====
      if (result.isEmpty && isCustom) {
        var book = appService.wordService.bookMap[appService.bookName];
        if (book != null && book.words != null) {
          for (var w in book.words!) {
            if (w.id != null && (statusMap[w.id]?.status ?? 0) >= 0) {
              var vo = appService.toWordVO(w);
              if (vo != null) result.add(vo);
            }
          }
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
    await ensureTodayReviewState();
    final roundDone = await _readNormalizedReviewIds(
      'review_round_done_${appService.bookId}',
    );
    final statuses = await _bookReviewStatuses();
    final learnedIds = statuses
        .map((status) => _wordIdFromStatusKey(status.word ?? ''))
        .where((id) => id.isNotEmpty)
        .toSet();
    return learnedIds.difference(roundDone.toSet()).length;
  }

  Future<List<WordVO>> createReviewBatch(int targetCount, int cycles) async {
    await appService.readWords();
    await ensureTodayReviewState();
    final roundDone = await _readNormalizedReviewIds(
      'review_round_done_${appService.bookId}',
    );

    final statuses = await _bookReviewStatuses();
    final available = statuses.where((status) {
      final wordId = _wordIdFromStatusKey(status.word ?? '');
      return wordId.isNotEmpty && !roundDone.contains(wordId);
    }).toList();

    if (available.isEmpty) return [];

    final reviewStats = _readReviewStats();
    available.shuffle();
    available.sort((a, b) {
      final aId = _wordIdFromStatusKey(a.word ?? '');
      final bId = _wordIdFromStatusKey(b.word ?? '');
      return _lastReviewTime(reviewStats, aId)
          .compareTo(_lastReviewTime(reviewStats, bId));
    });
    int N = targetCount < available.length ? targetCount : available.length;
    var selected = available.take(N).toList();

    List<WordVO> batch = [];
    for (int c = 0; c < cycles; c++) {
      selected.shuffle();
      for (var s in selected) {
        final wordId = _wordIdFromStatusKey(s.word ?? '');
        var po =
            WordPO(id: 0, word: wordId, book: appService.bookId.toString());
        var vo = toWord(po);
        if (vo != null) batch.add(vo);
      }
    }

    var storage = GetStorage();
    await storage.write('review_batch_${appService.bookId}',
        batch.map((e) => e.wordId).toList());
    await storage.write(
      'review_batch_key_${appService.bookId}',
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}',
    );
    await storage.write('review_batch_pos_${appService.bookId}', 0);
    await storage.write('review_batch_selected_${appService.bookId}',
        selected.map((e) => _wordIdFromStatusKey(e.word ?? '')).toList());
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
    if (wordId == null || wordId.isEmpty) return;
    String wordKey = "${appService.bookId}_$wordId";
    var existing = await wordDao.queryWordStatus(wordKey);
    if (existing != null) return;
    await wordDao.createWordStatus(WordStatusPO(
      word: wordKey,
      status: 0,
      studyCycle: 0,
      nextReviewTime: 0,
      createTime: DateTime.now().millisecondsSinceEpoch,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> pass(String word) async {
    String wordKey = "${appService.bookId}_$word";
    var status = await wordDao.queryWordStatus(wordKey);
    if (status == null) {
      await wordDao.createWordStatus(WordStatusPO(
        word: wordKey,
        status: 1,
        studyCycle: 1,
        nextReviewTime: 0,
        createTime: DateTime.now().millisecondsSinceEpoch,
        updateTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } else {
      status.status = 1;
      status.studyCycle = (status.studyCycle ?? 0) + 1;
      status.nextReviewTime = 0;
      status.updateTime = DateTime.now().millisecondsSinceEpoch;
      await wordDao.updateStatus(status);
    }
  }

  Future<void> passReview(String wordId) async {
    final storage = GetStorage();
    final stats = _readReviewStats();
    final existing = stats[wordId];
    final existingMap = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    final reviewCount = int.tryParse('${existingMap['reviewCount'] ?? 0}') ?? 0;
    stats[wordId] = <String, dynamic>{
      'reviewCount': reviewCount + 1,
      'lastReviewTime': DateTime.now().millisecondsSinceEpoch,
    };
    await storage.write(_reviewStatsKey, stats);
  }

  Future<void> removeReviewWordState(int bookId, String wordId) async {
    await appService.readWords();
    final storage = GetStorage();
    final batchKey = 'review_batch_$bookId';
    final rawBatch = storage.read(batchKey);
    if (rawBatch is List) {
      final batch = rawBatch.map((value) => value.toString()).toList();
      final oldPos =
          int.tryParse('${storage.read('review_batch_pos_$bookId') ?? 0}') ?? 0;
      final safePos = oldPos.clamp(0, batch.length);
      final removedBefore = batch
          .take(safePos)
          .where((value) => _normalizeWordId(value) == wordId)
          .length;
      batch.removeWhere((value) => _normalizeWordId(value) == wordId);
      await storage.write(batchKey, batch);
      await storage.write(
        'review_batch_pos_$bookId',
        (oldPos - removedBefore).clamp(0, batch.length),
      );
    }

    for (final key in <String>[
      'review_batch_selected_$bookId',
      'review_round_done_$bookId',
    ]) {
      final raw = storage.read(key);
      if (raw is List) {
        final ids = raw.map((value) => value.toString()).toList()
          ..removeWhere((value) => _normalizeWordId(value) == wordId);
        await storage.write(key, ids);
      }
    }

    final statsRaw = storage.read('review_word_stats_$bookId');
    if (statsRaw is Map) {
      final stats = Map<String, dynamic>.from(statsRaw);
      stats.remove(wordId);
      await storage.write('review_word_stats_$bookId', stats);
    }
    await storage.remove('review_batch_key_$bookId');
    await storage.remove('ai_article_cache_$bookId');
  }

  Future<void> markFamiliar(String wordId) async {
    await wordDao.markWordFamiliarById(wordId, appService.bookId);
    await removeReviewWordState(appService.bookId, wordId);
  }

  Future<void> addWordStudyRecord(int startTime, int endTime, bool playComplete,
      WordStatusPO status) async {
    wordDao.addWordStudyTimeRecord(WordStudyTimeCountPO(
      word: status.word,
      startTime: startTime,
      endTime: endTime,
      studyCycle: status.studyCycle,
      playComplete: playComplete ? 1 : 0,
    ));
  }

  Future<void> addStudyRecord(int startTime, int endTime) async {
    wordDao.addStudyTimeRecord(
        StudyTimeCountPO(startTime: startTime, endTime: endTime));
  }
}
