import 'dart:async';

import 'package:english/dao/word/word.dart';
import 'package:english/dicts/reader.dart';
import 'package:english/service/word/word.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../entity/word/po/word.dart';
import '../../entity/word/vo/word.dart';
import '../../controller/home/home_v2.dart';
import '../../controller/main/main_controller.dart';

class AppService {
  WordService wordService = Get.find();
  var wordDao = Get.find<WordDao>();
  var queueCount = 4;
  int dailyWantCount = 100;
  bool autoPass = false;
  bool autoPlayVoice = true;
  String? _bookName;
  Future<void> _customBookWriteQueue = Future<void>.value();

  String get bookName {
    return _bookName ?? wordService.bookNames[0];
  }

  String getBookId(String? bookName) {
    return wordService.bookMap[bookName]?.id ?? "2";
  }

  int get bookId {
    return int.parse(getBookId(_bookName));
  }

  String getStudyMode(int bId) {
    return GetStorage().read('study_mode_$bId') ?? 'manual';
  }

  void setStudyMode(int bId, String mode) {
    GetStorage().write('study_mode_$bId', mode);
  }

  void promptAndSelectBook(String bName) {
    int bId = int.tryParse(getBookId(bName)) ?? 0;
    String? existingMode = GetStorage().read('study_mode_$bId');

    if (existingMode != null) {
      _executeSelectBook(bName, existingMode);
    } else {
      // need context for isDark — obtain from Get
      final context = Get.context;
      if (context != null) {
        showModeSelectionDialog(bName, bId, context);
      } else {
        _executeSelectBook(bName, 'manual');
      }
    }
  }

  void showModeSelectionDialog(String bName, int bId, BuildContext context,
      {bool isReselect = false}) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
            const SizedBox(height: 20),
            Text(isReselect ? "重新选择播放模式" : "选择《$bName》的播放模式",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 8),
            Text("后续可长按词书卡片重新配置",
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 25),
            _buildModeCard(
                title: "手动沉浸模式 (推荐)",
                desc: "看英文回想释义，点击屏幕揭晓并自动发音，自主控制进度。",
                icon: Icons.touch_app_rounded,
                color: const Color(0xFF6366F1),
                isDark: isDark,
                onTap: () {
                  setStudyMode(bId, 'manual');
                  Get.back();
                  _executeSelectBook(bName, 'manual', isReselect: isReselect);
                }),
            const SizedBox(height: 15),
            _buildModeCard(
                title: "自动循环模式",
                desc: "传统分组记忆。按设定数量分组，自动轮播发音与释义。",
                icon: Icons.autorenew_rounded,
                color: const Color(0xFF10B981),
                isDark: isDark,
                onTap: () {
                  setStudyMode(bId, 'auto');
                  Get.back();
                  _executeSelectBook(bName, 'auto', isReselect: isReselect);
                }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(
      {required String title,
      required String desc,
      required IconData icon,
      required Color color,
      required bool isDark,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                          height: 1.4)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _executeSelectBook(String bName, String mode,
      {bool isReselect = false}) {
    if (isReselect) Get.back(); // close selectBook page
    selectBook(bName);
    if (Get.isRegistered<HomeControllerV2>())
      Get.find<HomeControllerV2>().fetchInfo();
    if (Get.isRegistered<MainController>())
      Get.find<MainController>().changePage(0);
    Get.snackbar(
        "配置完成", "当前词书:《$bName》\n播放模式: ${mode == 'manual' ? '手动沉浸' : '自动循环'}");
  }

  int thinkWaitTime = 1;
  int readWaitTime = 7;

  List<int> get reviewTimes {
    int minutes = 60 * 1000;
    int hour = 60 * minutes;
    int day = 24 * 60 * 60 * 1000;
    int month = 30 * day;
    return [
      5 * minutes,
      25 * minutes,
      hour,
      1 * day - hour,
      1 * day - hour,
      2 * day - hour,
      3 * day - hour,
      8 * day - hour,
      month - 15 * day - hour,
      1 * month - hour,
      2 * month - hour,
      3 * month - hour,
      8 * month - hour,
      15 * month - hour,
    ];
  }

  int get wordCount {
    return wordService.bookMap[bookName]?.words?.length ?? 0;
  }

  Future<void> insertCustomBookToDb(String customBookName) async {
    final book = wordService.bookMap[customBookName];
    final bookId = int.tryParse(book?.id ?? '0') ?? 0;
    if (book == null || book.words == null || bookId == 0) return;

    final desiredWords = book.words!
        .map((word) => word.id)
        .whereType<String>()
        .where((word) => word.isNotEmpty)
        .toSet();
    final existingWords = await wordDao.queryWords(bookId);
    final existingIds =
        existingWords.map((word) => word.word).whereType<String>().toSet();

    for (final staleWord in existingIds.difference(desiredWords)) {
      await wordDao.deleteBookWord(bookId, staleWord);
    }
    for (final newWord in desiredWords.difference(existingIds)) {
      await wordDao.addWord(WordPO(word: newWord, book: book.id));
    }
  }

  Future<T> _serializeCustomBookWrite<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _customBookWriteQueue = _customBookWriteQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  List<String> _normalizeCustomBookWords(Iterable<String> spells) {
    final normalized = spells
        .map((spell) => spell.trim().toLowerCase())
        .where((spell) => spell.isNotEmpty)
        .toSet()
        .toList();
    normalized.sort();
    return normalized;
  }

  String _newCustomBookId() {
    return (DateTime.now().microsecondsSinceEpoch % 1000000000000).toString();
  }

  /// The only write path for a custom book. Storage, memory and SQLite are
  /// updated as one serialized operation so callers cannot leave them apart.
  Future<int> replaceCustomBookWords(
    String bookName,
    Iterable<String> spells, {
    String? preferredBookId,
  }) {
    return _serializeCustomBookWrite(() async {
      final storage = GetStorage();
      final customBooks = Map<String, dynamic>.from(
        storage.read('custom_books') ?? <String, dynamic>{},
      );
      customBooks[bookName] = _normalizeCustomBookWords(spells);

      final existingId = storage.read('book_id_$bookName')?.toString();
      final bookId = existingId ?? preferredBookId ?? _newCustomBookId();
      await storage.write('book_id_$bookName', bookId);
      await storage.write('custom_books', customBooks);
      await wordService.loadCustomBooks();
      await insertCustomBookToDb(bookName);
      return int.tryParse(bookId) ?? 0;
    });
  }

  Future<bool> addWordToCustomBook(String bookName, String spell) {
    return _serializeCustomBookWrite(() async {
      final normalizedSpell = spell.trim().toLowerCase();
      if (normalizedSpell.isEmpty) return false;

      final storage = GetStorage();
      final customBooks = Map<String, dynamic>.from(
        storage.read('custom_books') ?? <String, dynamic>{},
      );
      final words = List<String>.from(customBooks[bookName] ?? const []);
      if (words.contains(normalizedSpell)) return false;

      words.add(normalizedSpell);
      customBooks[bookName] = _normalizeCustomBookWords(words);
      if (storage.read('book_id_$bookName') == null) {
        await storage.write('book_id_$bookName', _newCustomBookId());
      }
      await storage.write('custom_books', customBooks);
      await wordService.loadCustomBooks();
      await insertCustomBookToDb(bookName);
      return true;
    });
  }

  Future<bool> removeWordFromCustomBook(String bookName, String spell) {
    return _serializeCustomBookWrite(() async {
      final normalizedSpell = spell.trim().toLowerCase();
      final storage = GetStorage();
      final customBooks = Map<String, dynamic>.from(
        storage.read('custom_books') ?? <String, dynamic>{},
      );
      final words = List<String>.from(customBooks[bookName] ?? const []);
      final removed = words.remove(normalizedSpell);
      if (!removed) return false;

      customBooks[bookName] = _normalizeCustomBookWords(words);
      await storage.write('custom_books', customBooks);
      await wordService.loadCustomBooks();
      await insertCustomBookToDb(bookName);

      final bookId = int.tryParse(
            storage.read('book_id_$bookName')?.toString() ?? '',
          ) ??
          0;
      final wordId = getWordBySpell(normalizedSpell)?.id ?? normalizedSpell;
      if (bookId != 0) {
        await wordDao.deleteBookWord(bookId, wordId);
        await wordDao.deleteWordStatus(bookId, wordId);
        if (normalizedSpell != wordId) {
          await wordDao.deleteWordStatus(bookId, normalizedSpell);
        }
        await wordService.removeWordFromDifficultBook(
          normalizedSpell,
          bookId: bookId.toString(),
        );
      }
      return true;
    });
  }

  Future<void> deleteCustomBook(String bookName, int bookId) {
    return _serializeCustomBookWrite(() async {
      final storage = GetStorage();
      final originalCustomBooks = Map<String, dynamic>.from(
        storage.read('custom_books') ?? <String, dynamic>{},
      );
      final originalBookId = storage.read('book_id_$bookName');
      final updatedCustomBooks = Map<String, dynamic>.from(originalCustomBooks)
        ..remove(bookName);

      try {
        await storage.write('custom_books', updatedCustomBooks);
        await storage.remove('book_id_$bookName');
        await wordDao.clearBookProgressAll(bookId);
        await wordDao.deleteBookWords(bookId);
        await clearReviewState(
          bookId,
          clearStats: true,
          clearPreferences: true,
        );
        await wordService.clearDifficultWordsForBook(bookId.toString());
        for (final rawKey in storage.getKeys()) {
          if (rawKey == null) continue;
          final key = rawKey.toString();
          if (key == 'study_mode_$bookId' ||
              key == 'book_order_$bookId' ||
              key.startsWith('study_cursor_${bookId}_') ||
              key.startsWith('saved_queue_${bookId}_') ||
              key == 'deleted_system_words_$bookId') {
            await storage.remove(key);
          }
        }
        wordService.bookMap.remove(bookName);
        await wordService.loadCustomBooks();
      } catch (_) {
        await storage.write('custom_books', originalCustomBooks);
        if (originalBookId != null) {
          await storage.write('book_id_$bookName', originalBookId);
        }
        await wordService.loadCustomBooks();
        await insertCustomBookToDb(bookName);
        rethrow;
      }
    });
  }

  Future<void> clearReviewState(
    int bookId, {
    bool clearStats = false,
    bool clearPreferences = false,
  }) async {
    final storage = GetStorage();
    final keys = <String>[
      'review_date_$bookId',
      'review_round_done_$bookId',
      'review_batch_$bookId',
      'review_batch_key_$bookId',
      'review_batch_pos_$bookId',
      'review_batch_selected_$bookId',
      'review_next_batch_$bookId',
      'review_opened_at_$bookId',
      'review_queue_$bookId',
      'review_passed_$bookId',
      'ai_article_cache_$bookId',
    ];
    if (clearStats) keys.add('review_word_stats_$bookId');
    if (clearPreferences) {
      keys
        ..add('review_target_$bookId')
        ..add('review_cycles_$bookId');
    }
    for (final key in keys) {
      await storage.remove(key);
    }
  }

  Future<void> _removeWordFromReviewState(
    int bookId,
    String wordId,
    String spelling,
  ) async {
    final storage = GetStorage();
    final keysToRemove = <String>{
      wordId.trim().toLowerCase(),
      spelling.trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);
    if (keysToRemove.isEmpty) return;

    bool matches(dynamic value) {
      return keysToRemove.contains(value.toString().trim().toLowerCase());
    }

    var activeChanged = false;
    final batch = storage.read('review_batch_$bookId');
    if (batch is List) {
      final oldPosition =
          int.tryParse('${storage.read('review_batch_pos_$bookId') ?? 0}') ?? 0;
      final safePosition = oldPosition.clamp(0, batch.length).toInt();
      final removedBefore = batch.take(safePosition).where(matches).length;
      final updated = batch.where((value) => !matches(value)).toList();
      activeChanged = updated.length != batch.length;
      if (activeChanged) {
        await storage.write('review_batch_$bookId', updated);
        await storage.write(
          'review_batch_pos_$bookId',
          (oldPosition - removedBefore).clamp(0, updated.length).toInt(),
        );
      }
    }

    for (final key in <String>[
      'review_batch_selected_$bookId',
      'review_next_batch_$bookId',
      'review_round_done_$bookId',
    ]) {
      final raw = storage.read(key);
      if (raw is! List) continue;
      final updated = raw.where((value) => !matches(value)).toList();
      if (updated.length != raw.length) {
        await storage.write(key, updated);
      }
    }

    final rawStats = storage.read('review_word_stats_$bookId');
    if (rawStats is Map) {
      final stats = Map<String, dynamic>.from(rawStats);
      stats.removeWhere((key, _) => matches(key));
      await storage.write('review_word_stats_$bookId', stats);
    }

    if (activeChanged) {
      await storage.remove('review_batch_key_$bookId');
      await storage.remove('ai_article_cache_$bookId');
    }
  }

  Future<void> readWords() async {
    await wordService.loadWords();
  }

  Future<void> refreshWordsAfterRestore() async {
    wordService.wordMap.clear();
    wordService.spellMap.clear();
    wordService.bookMap.clear();
    wordService.systemBookNames.clear();
    wordService.customBookNames.clear();
    wordService.loaded = false;
    await wordService.loadWords();

    final storedBookName = GetStorage().read('study.bookName');
    if (storedBookName is String &&
        storedBookName.isNotEmpty &&
        wordService.bookMap.containsKey(storedBookName)) {
      _bookName = storedBookName;
    } else if (wordService.bookNames.isNotEmpty) {
      _bookName = wordService.bookNames.first;
    }
  }

  Future<void> insertToDb() async {
    if (bookLoaded()) return;
    wordDao.clearWord();
    for (var book in wordService.bookMap.values) {
      var words = book.words;
      if (words != null) {
        var wordPOs =
            words.map((e) => WordPO(word: e.id, book: book.id)).toList();
        await wordDao.addWords(wordPOs);
      }
    }
    setBookLoaded();
  }

  bool bookLoaded() {
    return GetStorage().read("book-loaded") == "true";
  }

  void setBookLoaded() {
    GetStorage().write("book-loaded", "true");
  }

  int reviewDailyCount = 50;

  void saveOptions() {
    var storage = GetStorage();
    storage.write("study.dailyWantCount", dailyWantCount);
    storage.write("study.thinkWaitTime", thinkWaitTime);
    storage.write("study.readWaitTime", readWaitTime);
    storage.write("study.queueCount", queueCount);
    storage.write("study.bookName", bookName);
    storage.write("study.autoPass", autoPass ? "true" : "false");
    storage.write("study.reviewDailyCount", reviewDailyCount);
    storage.write('auto_play', autoPlayVoice);
  }

  void readOptions() {
    var storage = GetStorage();
    dailyWantCount =
        int.parse((storage.read("study.dailyWantCount") ?? "100").toString());
    thinkWaitTime =
        int.parse((storage.read("study.thinkWaitTime") ?? "1").toString());
    readWaitTime =
        int.parse((storage.read("study.readWaitTime") ?? "7").toString());
    queueCount =
        int.parse((storage.read("study.queueCount") ?? "4").toString());
    _bookName = storage.read("study.bookName");
    autoPass = storage.read("study.autoPass").toString() == "true";
    reviewDailyCount =
        int.parse((storage.read("study.reviewDailyCount") ?? "50").toString());
    autoPlayVoice = storage.read('auto_play') ?? true;
    if (_bookName is String && wordService.bookMap.containsKey(_bookName)) {
      wordService.activateDifficultBook(getBookId(_bookName));
    }
  }

  Word? getWord(String? id) {
    if (id == null) return null;
    var w = wordService.wordMap[id];
    if (w != null) return w;
    // 兜底：按拼写查找
    return wordService.spellMap[id];
  }

  Word? getWordBySpell(String? spell) {
    if (spell == null) return null;
    var find = wordService.spellMap[spell];
    if (find != null && find.id != null) return find;
    return null;
  }

  WordVO? getWordVO(String? id) => toWordVO(getWord(id));

  WordVO? toWordVO(Word? word) {
    if (word != null) {
      return WordVO(
        wordId: word.id,
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

  void selectBook(String bookName) {
    _bookName = bookName;
    wordService.activateDifficultBook(getBookId(bookName));
    saveOptions();
  }

  Future<WordPoolSnapshot> loadWordPool(String bookName) async {
    await wordService.loadWords();
    final book = wordService.bookMap[bookName];
    final parsedBookId = int.tryParse(book?.id ?? '');
    if (book == null || parsedBookId == null) {
      return const WordPoolSnapshot(
        ordinaryWords: <Word>[],
        familiarWords: <Word>[],
        difficultWords: <Word>[],
      );
    }

    final sourceRows = await wordDao.queryWords(parsedBookId);
    final sourceWords = <Word>[];
    for (final row in sourceRows) {
      final wordId = row.word;
      if (wordId == null || wordId.isEmpty) continue;
      final source = getWord(wordId) ?? getWordBySpell(wordId);
      sourceWords.add(Word(
        id: wordId,
        word: source?.word ?? wordId,
        usVoice: source?.usVoice,
        ukVoice: source?.ukVoice,
        means: source?.means,
        helper: source?.helper,
        sentences: source?.sentences,
      ));
    }

    final statuses = await wordDao.queryWordStatusByBook(parsedBookId);
    final familiarKeys = statuses
        .where((status) => status.status == -1 && status.word != null)
        .map((status) => _wordIdFromStatusKey(
              status.word!,
              parsedBookId,
            ))
        .where((wordId) => wordId.isNotEmpty);
    return WordPoolSnapshot.fromWords(
      sourceWords: sourceWords,
      familiarKeys: familiarKeys,
      difficultSpellings: wordService.getDifficultWords(bookId: book.id),
      deletedKeys: wordService.deletedSystemWordSpellings(book.id!),
    );
  }

  String _wordIdFromStatusKey(String statusKey, int targetBookId) {
    final prefix = '${targetBookId}_';
    return statusKey.startsWith(prefix)
        ? statusKey.substring(prefix.length)
        : statusKey;
  }

  String? _wordSpelling(String? wordId) {
    if (wordId == null || wordId.isEmpty) return null;
    final word = getWord(wordId) ?? getWordBySpell(wordId);
    final spelling = word?.word?.trim();
    if (spelling != null && spelling.isNotEmpty) return spelling;
    final normalized = wordId.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<bool> markWordFamiliar(
    String? wordId, {
    String? bookName,
  }) async {
    final targetBookName = bookName ?? this.bookName;
    final targetBookId =
        int.tryParse(wordService.bookMap[targetBookName]?.id ?? '') ?? 0;
    final spelling = _wordSpelling(wordId);
    if (wordId == null ||
        wordId.isEmpty ||
        targetBookId == 0 ||
        spelling == null) {
      return false;
    }
    await wordDao.markWordFamiliarById(wordId, targetBookId);
    await wordService.removeWordFromDifficultBook(
      spelling,
      bookId: targetBookId.toString(),
    );
    await _removeWordFromReviewState(targetBookId, wordId, spelling);
    return true;
  }

  /// Permanently removes a word from this book's source.
  ///
  /// Custom books update custom_books, SQLite and the in-memory Book together.
  /// System books cannot mutate the bundled dictionary, so their SQLite source
  /// row is removed and a per-book deletion overlay keeps the word hidden after
  /// a reload.
  Future<bool> deleteWord(
    String? wordId, {
    String? bookName,
  }) async {
    final targetBookName = bookName ?? this.bookName;
    final book = wordService.bookMap[targetBookName];
    final targetBookId = int.tryParse(book?.id ?? '') ?? 0;
    final spelling = _wordSpelling(wordId);
    if (wordId == null ||
        wordId.isEmpty ||
        targetBookId == 0 ||
        spelling == null) {
      return false;
    }

    final deleted = wordService.customBookNames.contains(targetBookName)
        ? await _serializeCustomBookWrite(
            () => _deleteCustomBookWord(
              targetBookName,
              targetBookId,
              wordId,
              spelling,
            ),
          )
        : await _deleteSystemBookWord(
            targetBookName,
            targetBookId,
            wordId,
            spelling,
          );
    if (deleted) {
      await _removeWordFromReviewState(targetBookId, wordId, spelling);
    }
    return deleted;
  }

  Future<bool> _deleteCustomBookWord(
    String bookName,
    int bookId,
    String wordId,
    String spelling,
  ) async {
    final storage = GetStorage();
    final originalCustomBooks = Map<String, dynamic>.from(
      storage.read('custom_books') ?? <String, dynamic>{},
    );
    final updatedCustomBooks = Map<String, dynamic>.from(originalCustomBooks);
    final words = List<String>.from(originalCustomBooks[bookName] ?? const []);
    final matchesWord = words.any(
      (word) => word.trim().toLowerCase() == spelling.trim().toLowerCase(),
    );
    if (!matchesWord) return false;
    words.removeWhere(
      (word) => word.trim().toLowerCase() == spelling.trim().toLowerCase(),
    );

    try {
      updatedCustomBooks[bookName] = _normalizeCustomBookWords(words);
      await storage.write('custom_books', updatedCustomBooks);
      await wordService.loadCustomBooks();
      await insertCustomBookToDb(bookName);
      await wordDao.deleteBookWord(bookId, wordId);
      await wordDao.deleteWordStatus(bookId, wordId);
      if (spelling != wordId) {
        await wordDao.deleteWordStatus(bookId, spelling);
      }
      await wordService.removeWordFromDifficultBook(
        spelling,
        bookId: bookId.toString(),
      );
      return true;
    } catch (_) {
      await storage.write('custom_books', originalCustomBooks);
      await wordService.loadCustomBooks();
      await insertCustomBookToDb(bookName);
      rethrow;
    }
  }

  Future<bool> _deleteSystemBookWord(
    String bookName,
    int bookId,
    String wordId,
    String spelling,
  ) async {
    final book = wordService.bookMap[bookName];
    if (book == null) return false;

    await wordService.hideSystemWord(bookId.toString(), spelling);
    try {
      await wordDao.deleteBookWord(bookId, wordId);
      await wordDao.deleteWordStatus(bookId, wordId);
      if (spelling != wordId) {
        await wordDao.deleteWordStatus(bookId, spelling);
      }
    } catch (_) {
      // The persisted per-book overlay still hides the word; startup retries DB
      // cleanup when WordService loads the bundled source again.
    }
    try {
      await wordService.removeWordFromDifficultBook(
        spelling,
        bookId: bookId.toString(),
      );
    } catch (_) {
      // The source is already hidden; stale difficult metadata is harmless.
    }
    book.words?.removeWhere((word) {
      final sameId = word.id == wordId;
      final sameSpelling =
          word.word?.trim().toLowerCase() == spelling.trim().toLowerCase();
      return sameId || sameSpelling;
    });
    return true;
  }

  Future<bool?> queryWordDeleteStatus(String? word) async {
    String wordKey = "${bookId}_$word";
    var status = await wordDao.queryWordStatus(wordKey);
    return status?.status == -1;
  }

  Future<void> restoreWord(
    String? wordId, {
    String? bookName,
  }) async {
    final targetBookId = int.tryParse(
            wordService.bookMap[bookName ?? this.bookName]?.id ?? '') ??
        bookId;
    await wordDao.restoreWordForStudy(wordId, targetBookId);
  }
}
