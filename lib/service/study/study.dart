// lib/service/study/study.dart
import 'dart:math';

import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/app/app.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../entity/word/po/word.dart';
import '../../util/time.dart';

class ReviewWordSnapshot {
  final String id;
  final int updateTime;
  final int lastReviewTime;

  const ReviewWordSnapshot({
    required this.id,
    required this.updateTime,
    required this.lastReviewTime,
  });
}

class ReviewQueuePlan {
  final List<String> activeIds;
  final List<String> nextIds;

  const ReviewQueuePlan({
    required this.activeIds,
    required this.nextIds,
  });
}

class ReviewQueueSnapshot {
  final List<WordVO> words;
  final int position;
  final int activeUniqueCount;
  final int nextUniqueCount;

  const ReviewQueueSnapshot({
    required this.words,
    required this.position,
    required this.activeUniqueCount,
    required this.nextUniqueCount,
  });

  bool get isCompleted => position >= words.length;
}

bool isReviewStateForDay(String? storedDay, String currentDay) {
  return storedDay == currentDay;
}

List<String> uniqueReviewIds(Iterable<String> ids) {
  final seen = <String>{};
  final result = <String>[];
  for (final rawId in ids) {
    final id = rawId.trim();
    if (id.isNotEmpty && seen.add(id)) result.add(id);
  }
  return result;
}

int _compareReviewSnapshots(ReviewWordSnapshot a, ReviewWordSnapshot b) {
  final lastReviewOrder = a.lastReviewTime.compareTo(b.lastReviewTime);
  if (lastReviewOrder != 0) return lastReviewOrder;
  final updateOrder = a.updateTime.compareTo(b.updateTime);
  if (updateOrder != 0) return updateOrder;
  return a.id.compareTo(b.id);
}

List<String> freezeReviewIdsForOpening({
  required Iterable<ReviewWordSnapshot> candidates,
  required int dayStart,
  required int openedAt,
  required int maxCount,
  Iterable<String> excludedIds = const <String>[],
}) {
  if (maxCount <= 0) return <String>[];

  final excluded = excludedIds.map((id) => id.trim()).toSet();
  final eligibleById = <String, ReviewWordSnapshot>{};
  for (final candidate in candidates) {
    final id = candidate.id.trim();
    if (id.isEmpty ||
        candidate.updateTime < dayStart ||
        candidate.updateTime > openedAt ||
        excluded.contains(id)) {
      continue;
    }
    final existing = eligibleById[id];
    if (existing == null || candidate.updateTime > existing.updateTime) {
      eligibleById[id] = ReviewWordSnapshot(
        id: id,
        updateTime: candidate.updateTime,
        lastReviewTime: candidate.lastReviewTime,
      );
    }
  }

  final eligible = eligibleById.values.toList()..sort(_compareReviewSnapshots);
  return eligible.take(maxCount).map((item) => item.id).toList();
}

List<String> buildPendingReviewIds({
  required Iterable<ReviewWordSnapshot> candidates,
  required int dayStart,
  required Iterable<String> activeIds,
  Iterable<String> excludedIds = const <String>[],
}) {
  final excluded = <String>{
    ...activeIds.map((id) => id.trim()),
    ...excludedIds.map((id) => id.trim()),
  };
  final eligibleById = <String, ReviewWordSnapshot>{};
  for (final candidate in candidates) {
    final id = candidate.id.trim();
    if (id.isEmpty ||
        candidate.updateTime < dayStart ||
        excluded.contains(id)) {
      continue;
    }
    final existing = eligibleById[id];
    if (existing == null || candidate.updateTime > existing.updateTime) {
      eligibleById[id] = ReviewWordSnapshot(
        id: id,
        updateTime: candidate.updateTime,
        lastReviewTime: candidate.lastReviewTime,
      );
    }
  }

  final eligible = eligibleById.values.toList()
    ..sort((a, b) {
      final updateOrder = a.updateTime.compareTo(b.updateTime);
      if (updateOrder != 0) return updateOrder;
      return a.id.compareTo(b.id);
    });
  return eligible.map((item) => item.id).toList();
}

List<String> limitReviewIds(Iterable<String> ids, int maxCount) {
  final uniqueIds = uniqueReviewIds(ids);
  if (maxCount <= 0 || uniqueIds.length <= maxCount) return uniqueIds;
  return uniqueIds.take(maxCount).toList();
}

List<String> expandReviewQueue(Iterable<String> ids, int cycles) {
  final uniqueIds = uniqueReviewIds(ids);
  if (uniqueIds.isEmpty) return <String>[];
  final safeCycles = cycles < 1 ? 1 : cycles;
  final expanded = <String>[];
  for (var cycle = 0; cycle < safeCycles; cycle++) {
    expanded.addAll(uniqueIds);
  }
  return expanded;
}

ReviewQueuePlan promoteReviewQueuePlan({
  required Iterable<String> currentActiveIds,
  required Iterable<String> nextIds,
  required Iterable<ReviewWordSnapshot> candidates,
  required int dayStart,
  Iterable<String> completedIds = const <String>[],
}) {
  final newActiveIds = uniqueReviewIds(nextIds);
  final excluded = <String>[
    ...completedIds,
    ...currentActiveIds,
  ];
  final pendingIds = buildPendingReviewIds(
    candidates: candidates,
    dayStart: dayStart,
    activeIds: newActiveIds,
    excludedIds: excluded,
  );
  return ReviewQueuePlan(
    activeIds: newActiveIds,
    nextIds: pendingIds,
  );
}

class StudyService {
  AppService appService = Get.find();
  WordDao wordDao = Get.find();

  List<WordVO> _reviewBatch = [];
  int _reviewIndex = 0;

  String get _reviewStatsKey => 'review_word_stats_${appService.bookId}';
  String get _reviewDateKey => 'review_date_${appService.bookId}';
  String get _reviewActiveKey => 'review_batch_${appService.bookId}';
  String get _reviewActiveSelectedKey =>
      'review_batch_selected_${appService.bookId}';
  String get _reviewActivePositionKey =>
      'review_batch_pos_${appService.bookId}';
  String get _reviewBatchKeyKey => 'review_batch_key_${appService.bookId}';
  String get _reviewRoundDoneKey => 'review_round_done_${appService.bookId}';
  String get _reviewNextKey => 'review_next_batch_${appService.bookId}';
  String get _reviewOpenedAtKey => 'review_opened_at_${appService.bookId}';
  String get _aiArticleCacheKey => 'ai_article_cache_${appService.bookId}';

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
    bool persistNormalization = true,
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
    if (persistNormalization &&
        (original.length != normalized.length ||
            original.asMap().entries.any(
                  (entry) => entry.value != normalized[entry.key],
                ))) {
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
    final today = getDayKey();
    if (isReviewStateForDay(storage.read(_reviewDateKey), today)) return;

    for (final key in <String>[
      _reviewRoundDoneKey,
      _reviewActiveKey,
      _reviewBatchKeyKey,
      _reviewActivePositionKey,
      _reviewActiveSelectedKey,
      _reviewNextKey,
      _reviewOpenedAtKey,
      'review_queue_${appService.bookId}',
      'review_passed_${appService.bookId}',
      _aiArticleCacheKey,
    ]) {
      await storage.remove(key);
    }
    await storage.write(_reviewDateKey, today);
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

  Future<List<ReviewWordSnapshot>> _reviewCandidates() async {
    final statuses = await _bookReviewStatuses();
    final stats = _readReviewStats();
    return statuses
        .map((status) {
          final id = _wordIdFromStatusKey(status.word ?? '');
          return ReviewWordSnapshot(
            id: id,
            updateTime: status.updateTime ?? 0,
            lastReviewTime: _lastReviewTime(stats, id),
          );
        })
        .where((candidate) => candidate.id.isNotEmpty)
        .toList();
  }

  int? _readStoredInt(String key) {
    final value = GetStorage().read(key);
    if (value is int) return value;
    return int.tryParse('${value ?? ''}');
  }

  String _newReviewBatchKey() {
    return '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 32)}';
  }

  Future<void> _writeActiveReviewQueue({
    required List<String> activeIds,
    required List<String> selectedIds,
    required int position,
    required bool rotateBatchKey,
  }) async {
    final storage = GetStorage();
    final uniqueSelectedIds = uniqueReviewIds(selectedIds);
    await storage.write(_reviewActiveKey, activeIds);
    await storage.write(_reviewActiveSelectedKey, uniqueSelectedIds);
    await storage.write(_reviewActivePositionKey, position);
    if (rotateBatchKey) {
      await storage.write(_reviewBatchKeyKey, _newReviewBatchKey());
      await storage.remove(_aiArticleCacheKey);
    }
  }

  Future<int> refreshNextReviewQueue() async {
    await ensureTodayReviewState();
    final activeIds = await _readNormalizedReviewIds(
      _reviewActiveKey,
      deduplicate: false,
      persistNormalization: false,
    );
    final selectedIds =
        await _readNormalizedReviewIds(_reviewActiveSelectedKey);
    final roundDoneIds = await _readNormalizedReviewIds(_reviewRoundDoneKey);
    final candidates = await _reviewCandidates();
    final pendingIds = buildPendingReviewIds(
      candidates: candidates,
      dayStart: getDayStartTime(),
      activeIds: <String>[...activeIds, ...selectedIds],
      excludedIds: roundDoneIds,
    );
    await GetStorage().write(_reviewNextKey, pendingIds);
    return pendingIds.length;
  }

  Future<ReviewQueuePlan?> _promotePendingReviewQueue({
    required List<String> activeIds,
    required int cycles,
    required int targetCount,
    required int dayStart,
  }) async {
    final storage = GetStorage();
    var nextIds = await _readNormalizedReviewIds(_reviewNextKey);
    if (nextIds.isEmpty) {
      await refreshNextReviewQueue();
      nextIds = await _readNormalizedReviewIds(_reviewNextKey);
    }
    if (nextIds.isEmpty) return null;
    nextIds = limitReviewIds(nextIds, targetCount);

    final roundDoneIds = await _readNormalizedReviewIds(_reviewRoundDoneKey);
    final completedIds = uniqueReviewIds(<String>[
      ...roundDoneIds,
      ...activeIds,
    ]);
    final candidates = await _reviewCandidates();
    final plan = promoteReviewQueuePlan(
      currentActiveIds: activeIds,
      nextIds: nextIds,
      candidates: candidates,
      dayStart: dayStart,
      completedIds: completedIds,
    );
    if (plan.activeIds.isEmpty) return null;

    await storage.write(_reviewRoundDoneKey, completedIds);
    await _writeActiveReviewQueue(
      activeIds: expandReviewQueue(plan.activeIds, cycles),
      selectedIds: plan.activeIds,
      position: 0,
      rotateBatchKey: true,
    );
    await storage.write(_reviewNextKey, plan.nextIds);
    return plan;
  }

  // The active queue is written only here and when the pending queue is
  // promoted. Reopening the review screen refreshes only the pending queue.
  Future<ReviewQueueSnapshot> loadOrFreezeActiveReviewQueue({
    required int targetCount,
    required int cycles,
  }) async {
    final openedAtTime = DateTime.now();
    final openedAt = openedAtTime.millisecondsSinceEpoch;
    final openedDayStart = getDayStartTime(openedAtTime);
    await appService.readWords();
    await ensureTodayReviewState();

    final storage = GetStorage();
    var activeIds = await _readNormalizedReviewIds(
      _reviewActiveKey,
      deduplicate: false,
      persistNormalization: false,
    );
    var selectedIds = await _readNormalizedReviewIds(_reviewActiveSelectedKey);
    final storedOpenedAt = _readStoredInt(_reviewOpenedAtKey);

    if (storedOpenedAt == null) {
      if (activeIds.isEmpty && selectedIds.isNotEmpty) {
        activeIds = expandReviewQueue(selectedIds, cycles);
        await _writeActiveReviewQueue(
          activeIds: activeIds,
          selectedIds: selectedIds,
          position: 0,
          rotateBatchKey: false,
        );
      } else if (activeIds.isEmpty && selectedIds.isEmpty) {
        final candidates = await _reviewCandidates();
        final roundDoneIds =
            await _readNormalizedReviewIds(_reviewRoundDoneKey);
        selectedIds = freezeReviewIdsForOpening(
          candidates: candidates,
          dayStart: openedDayStart,
          openedAt: openedAt,
          maxCount: targetCount,
          excludedIds: roundDoneIds,
        );
        activeIds = expandReviewQueue(selectedIds, cycles);
        await _writeActiveReviewQueue(
          activeIds: activeIds,
          selectedIds: selectedIds,
          position: 0,
          rotateBatchKey: true,
        );
      } else {
        selectedIds = uniqueReviewIds(activeIds);
        await storage.write(_reviewActiveSelectedKey, selectedIds);
      }
      await storage.write(_reviewOpenedAtKey, openedAt);
    } else if (activeIds.isEmpty && selectedIds.isNotEmpty) {
      activeIds = expandReviewQueue(selectedIds, cycles);
      await _writeActiveReviewQueue(
        activeIds: activeIds,
        selectedIds: selectedIds,
        position: 0,
        rotateBatchKey: false,
      );
    }

    if (activeIds.isNotEmpty && selectedIds.isEmpty) {
      selectedIds = uniqueReviewIds(activeIds);
      await storage.write(_reviewActiveSelectedKey, selectedIds);
    }
    if (activeIds.isNotEmpty &&
        '${storage.read(_reviewBatchKeyKey) ?? ''}'.isEmpty) {
      await storage.write(_reviewBatchKeyKey, _newReviewBatchKey());
      await storage.remove(_aiArticleCacheKey);
    }

    var nextUniqueCount = await refreshNextReviewQueue();
    if (activeIds.isEmpty && nextUniqueCount > 0) {
      final promoted = await _promotePendingReviewQueue(
        activeIds: activeIds,
        cycles: cycles,
        targetCount: targetCount,
        dayStart: getDayStartTime(),
      );
      if (promoted != null) {
        activeIds = expandReviewQueue(promoted.activeIds, cycles);
        selectedIds = promoted.activeIds;
        nextUniqueCount = promoted.nextIds.length;
      }
    }

    final words = await _reviewWordsForIds(activeIds);
    final savedPosition = _readStoredInt(_reviewActivePositionKey) ?? 0;
    final safePosition = savedPosition.clamp(0, words.length).toInt();
    return ReviewQueueSnapshot(
      words: words,
      position: safePosition,
      activeUniqueCount: uniqueReviewIds(activeIds).length,
      nextUniqueCount: nextUniqueCount,
    );
  }

  Future<bool> promoteNextReviewQueue({
    required int cycles,
    required int targetCount,
  }) async {
    await appService.readWords();
    await ensureTodayReviewState();

    final activeIds = await _readNormalizedReviewIds(
      _reviewActiveKey,
      deduplicate: false,
      persistNormalization: false,
    );
    final position = _readStoredInt(_reviewActivePositionKey) ?? 0;
    if (activeIds.isNotEmpty && position < activeIds.length) return false;

    final promoted = await _promotePendingReviewQueue(
      activeIds: activeIds,
      cycles: cycles,
      targetCount: targetCount,
      dayStart: getDayStartTime(),
    );
    return promoted != null;
  }

  Future<int> todayLearnedCount() async {
    await ensureTodayReviewState();
    return (await _bookReviewStatuses()).length;
  }

  Future<List<WordVO>> fetchStudyQueueWords(int studyQueueMaxCount) async {
    await appService.readWords();

    String mode = Get.parameters['mode'] ?? 'new';

    if (mode == 'review') {
      final target = GetStorage().read('review_target_${appService.bookId}') ??
          appService.reviewDailyCount;
      final cycles =
          GetStorage().read('review_cycles_${appService.bookId}') ?? 1;
      final snapshot = await loadOrFreezeActiveReviewQueue(
        targetCount: int.tryParse('$target') ?? appService.reviewDailyCount,
        cycles: int.tryParse('$cycles') ?? 1,
      );
      _reviewBatch = snapshot.words;
      final batch = _reviewBatch.take(studyQueueMaxCount).toList();
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
    final snapshot = await loadOrFreezeActiveReviewQueue(
      targetCount: targetCount,
      cycles: cycles,
    );
    return snapshot.words;
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

  Future<int> markWordsLearned(Iterable<String> wordIds) async {
    var changed = 0;
    for (final wordId in wordIds.toSet()) {
      if (wordId.isEmpty) continue;
      final wordKey = '${appService.bookId}_$wordId';
      final existing = await wordDao.queryWordStatus(wordKey);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (existing == null) {
        await wordDao.createWordStatus(WordStatusPO(
          word: wordKey,
          status: 1,
          studyCycle: 1,
          nextReviewTime: 0,
          createTime: now,
          updateTime: now,
        ));
        changed++;
        continue;
      }
      if (existing.status == -1) continue;
      if (existing.status == 1 && (existing.studyCycle ?? 0) > 0) continue;
      existing.status = 1;
      existing.studyCycle = max(1, existing.studyCycle ?? 0);
      existing.nextReviewTime = 0;
      existing.updateTime = now;
      await wordDao.updateStatus(existing);
      changed++;
    }
    return changed;
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
    final normalizedWordId = _normalizeWordId(wordId);
    final storage = GetStorage();
    final batchKey = 'review_batch_$bookId';
    final rawBatch = storage.read(batchKey);
    var activeChanged = false;
    if (rawBatch is List) {
      final batch = rawBatch.map((value) => value.toString()).toList();
      final oldPos =
          int.tryParse('${storage.read('review_batch_pos_$bookId') ?? 0}') ?? 0;
      final safePos = oldPos.clamp(0, batch.length).toInt();
      final removedBefore = batch
          .take(safePos)
          .where((value) => _normalizeWordId(value) == normalizedWordId)
          .length;
      final oldLength = batch.length;
      batch.removeWhere(
        (value) => _normalizeWordId(value) == normalizedWordId,
      );
      activeChanged = batch.length != oldLength;
      if (activeChanged) {
        await storage.write(batchKey, batch);
        await storage.write(
          'review_batch_pos_$bookId',
          (oldPos - removedBefore).clamp(0, batch.length).toInt(),
        );
      }
    }

    for (final key in <String>[
      'review_batch_selected_$bookId',
      'review_round_done_$bookId',
      'review_next_batch_$bookId',
    ]) {
      final raw = storage.read(key);
      if (raw is List) {
        final ids = raw.map((value) => value.toString()).toList()
          ..removeWhere(
            (value) => _normalizeWordId(value) == normalizedWordId,
          );
        await storage.write(key, ids);
      }
    }

    final statsRaw = storage.read('review_word_stats_$bookId');
    if (statsRaw is Map) {
      final stats = Map<String, dynamic>.from(statsRaw);
      stats.remove(wordId);
      stats.remove(normalizedWordId);
      await storage.write('review_word_stats_$bookId', stats);
    }
    if (activeChanged) {
      await storage.remove('review_batch_key_$bookId');
      await storage.remove('ai_article_cache_$bookId');
    }
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
