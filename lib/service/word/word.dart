// lib/service/word/word.dart
import 'package:english/dao/word/word.dart';
import 'package:english/dicts/reader.dart';
import 'package:english/entity/word/po/word.dart';
import 'package:english/util/dictionary.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

enum WordPoolType { ordinary, familiar, difficult }

extension WordPoolTypeText on WordPoolType {
  String get label {
    switch (this) {
      case WordPoolType.ordinary:
        return '普通词';
      case WordPoolType.familiar:
        return '熟词';
      case WordPoolType.difficult:
        return '顽固词';
    }
  }

  String get exportLabel {
    switch (this) {
      case WordPoolType.ordinary:
        return '普通词汇';
      case WordPoolType.familiar:
        return '熟词';
      case WordPoolType.difficult:
        return '顽固词汇';
    }
  }
}

/// A read-only snapshot of the three overlapping pools for one book.
///
/// Familiar words are source words with status -1. Difficult words are an
/// overlay, so ordinary words intentionally include every difficult word even
/// when that word is also familiar.
class WordPoolSnapshot {
  final List<Word> ordinaryWords;
  final List<Word> familiarWords;
  final List<Word> difficultWords;

  const WordPoolSnapshot({
    required this.ordinaryWords,
    required this.familiarWords,
    required this.difficultWords,
  });

  factory WordPoolSnapshot.fromWords({
    required Iterable<Word> sourceWords,
    Iterable<String> familiarKeys = const <String>[],
    Iterable<String> difficultSpellings = const <String>[],
    Iterable<String> deletedKeys = const <String>[],
  }) {
    final familiar = familiarKeys.map(_normalizeKey).where(_isPresent).toSet();
    final difficult =
        difficultSpellings.map(_normalizeKey).where(_isPresent).toSet();
    final deleted = deletedKeys.map(_normalizeKey).where(_isPresent).toSet();
    final ordinary = <Word>[];
    final familiarWords = <Word>[];
    final difficultWords = <Word>[];
    final seen = <String>{};

    for (final word in sourceWords) {
      final identity = _wordIdentity(word);
      if (!_isPresent(identity) || !seen.add(identity)) continue;

      final keys = _wordKeys(word);
      if (keys.any(deleted.contains)) continue;
      final isFamiliar = keys.any(familiar.contains);
      final isDifficult = keys.any(difficult.contains);

      if (!isFamiliar || isDifficult) ordinary.add(word);
      if (isFamiliar) familiarWords.add(word);
      if (isDifficult) difficultWords.add(word);
    }

    return WordPoolSnapshot(
      ordinaryWords: List<Word>.unmodifiable(ordinary),
      familiarWords: List<Word>.unmodifiable(familiarWords),
      difficultWords: List<Word>.unmodifiable(difficultWords),
    );
  }

  List<Word> wordsFor(WordPoolType type) {
    switch (type) {
      case WordPoolType.ordinary:
        return ordinaryWords;
      case WordPoolType.familiar:
        return familiarWords;
      case WordPoolType.difficult:
        return difficultWords;
    }
  }

  int countFor(WordPoolType type) => wordsFor(type).length;

  bool isDifficult(Word word) {
    final keys = _wordKeys(word);
    return difficultWords.any((item) => item.word == word.word) ||
        keys.any((key) =>
            difficultWords.any((item) => _wordKeys(item).contains(key)));
  }

  static Set<String> _wordKeys(Word word) {
    return <String>{
      if (_isPresent(word.id ?? '')) _normalizeKey(word.id!),
      if (_isPresent(word.word ?? '')) _normalizeKey(word.word!),
    };
  }

  static String _wordIdentity(Word word) {
    if (_isPresent(word.word ?? '')) return _normalizeKey(word.word!);
    return _normalizeKey(word.id ?? '');
  }

  static bool _isPresent(String value) => value.isNotEmpty;

  static String _normalizeKey(String value) => value.trim().toLowerCase();
}

/// Pure migration helpers for the legacy global `difficult_words` list.
class DifficultWordStore {
  static const String byBookKey = 'difficult_words_by_book_v1';
  static const String legacyKey = 'difficult_words';
  static const String migrationKey = 'difficult_words_by_book_migrated';
  static const String mirrorBookKey = 'difficult_words_mirror_book';

  static List<String> normalizeWords(dynamic raw) {
    if (raw is! List) return <String>[];
    final words = raw
        .map((value) => value.toString().trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    words.sort();
    return words;
  }

  static Map<String, List<String>> normalizeBookMap(dynamic raw) {
    if (raw is! Map) return <String, List<String>>{};
    final result = <String, List<String>>{};
    raw.forEach((key, value) {
      final bookId = key.toString().trim();
      if (bookId.isEmpty) return;
      result[bookId] = normalizeWords(value);
    });
    return result;
  }

  static Map<String, List<String>> migrateLegacy({
    required Map<String, List<String>> byBook,
    required List<String> legacyWords,
    required String activeBookId,
    required bool alreadyMigrated,
  }) {
    final result = <String, List<String>>{
      for (final entry in byBook.entries)
        entry.key: normalizeWords(entry.value),
    };
    if (!alreadyMigrated &&
        legacyWords.isNotEmpty &&
        (result[activeBookId]?.isEmpty ?? true)) {
      result[activeBookId] = normalizeWords(legacyWords);
    }
    return result;
  }

  static String buildTxt(Iterable<Word> words) {
    final buffer = StringBuffer();
    for (final word in words) {
      final spelling = word.word?.trim() ?? '';
      if (spelling.isEmpty) continue;
      final meaning = (word.means ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      buffer.writeln('$spelling\t${meaning.isEmpty ? '暂无释义' : meaning}');
    }
    return buffer.toString();
  }
}

class WordService {
  var bookNames = [
    "小学英语",
    "初中英语",
    "高中英语",
    "大学英语四级词汇",
    "大学英语六级词汇",
    "大学英语专业四级",
    "大学英语专业八级",
    "全国等级考试",
    "考研英语",
    "考博英语",
    "BEC词汇",
    "GMAT词汇",
    "GRE词汇",
    "托福词汇",
    "雅思词汇",
    "托业词汇",
    "SAT词汇",
    "ACT词汇",
    "MBA词汇",
  ];
  var bookInfo = {
    "小学英语": {
      "color": Color(0xFF2A5485),
      "fontColor": Colors.white,
      "title": "小学",
      "subTitle": "小学英语"
    },
    "初中英语": {
      "color": Color(0xFF471DA9),
      "fontColor": Colors.white,
      "title": "初中",
      "subTitle": "初中英语"
    },
    "高中英语": {
      "color": Color(0xFF137A52),
      "fontColor": Colors.white,
      "title": "高中",
      "subTitle": "高中英语"
    },
    "大学英语四级词汇": {
      "color": Color(0xFF4E7C16),
      "fontColor": Colors.white,
      "title": "四级",
      "subTitle": "四级词汇"
    },
    "大学英语六级词汇": {
      "color": Color(0xFF8F4D1F),
      "fontColor": Colors.white,
      "title": "六级",
      "subTitle": "六级词汇"
    },
    "大学英语专业四级": {
      "color": Color(0xFF73143F),
      "fontColor": Colors.white,
      "title": "专四",
      "subTitle": "专业四级词汇"
    },
    "大学英语专业八级": {
      "color": Color(0xFF611DA1),
      "fontColor": Colors.white,
      "title": "专八",
      "subTitle": "专业八级词汇"
    },
    "考博英语": {
      "color": Color(0xFF6B802D),
      "fontColor": Colors.white,
      "title": "考博",
      "subTitle": "考博英语"
    },
    "考研英语": {
      "color": Color(0xFFA2342A),
      "fontColor": Colors.white,
      "title": "考研",
      "subTitle": "考研英语"
    },
    "全国等级考试": {
      "color": Color(0xFF88580F),
      "fontColor": Colors.white,
      "title": "等级考试",
      "subTitle": "全国等级考试"
    },
    "BEC词汇": {
      "color": Color(0xFF750E58),
      "fontColor": Colors.white,
      "title": "BEC",
      "subTitle": "BEC词汇"
    },
    "GMAT词汇": {
      "color": Color(0xFF387312),
      "fontColor": Colors.white,
      "title": "GMAT",
      "subTitle": "GMAT词汇"
    },
    "GRE词汇": {
      "color": Color(0xFF0F4B8F),
      "fontColor": Colors.white,
      "title": "GRE",
      "subTitle": "GRE词汇"
    },
    "托福词汇": {
      "color": Color(0xFF7C300E),
      "fontColor": Colors.white,
      "title": "托福",
      "subTitle": "托福词汇"
    },
    "雅思词汇": {
      "color": Color(0xFF528D21),
      "fontColor": Colors.white,
      "title": "雅思",
      "subTitle": "雅思词汇"
    },
    "托业词汇": {
      "color": Color(0xFF8C1136),
      "fontColor": Colors.white,
      "title": "托业",
      "subTitle": "托业词汇"
    },
    "SAT词汇": {
      "color": Color(0xFF438535),
      "fontColor": Colors.white,
      "title": "SAT",
      "subTitle": "SAT词汇"
    },
    "ACT词汇": {
      "color": Color(0xFF8A6515),
      "fontColor": Colors.white,
      "title": "ACT",
      "subTitle": "ACT词汇"
    },
    "MBA词汇": {
      "color": Color(0xFFB61553),
      "fontColor": Colors.white,
      "title": "MBA",
      "subTitle": "MBA词汇"
    },
  };
  var systemBookNames = <String>[].obs;
  var customBookNames = <String>[].obs;
  var wordMap = <String, Word>{};
  var bookMap = <String, Book>{};

  // O(1) 拼写极速查询索引
  var spellMap = <String, Word>{};

  var loaded = false;
  bool _isLoading = false;

  /// 将网络抓取到的 Word 合并到 wordMap / spellMap：
  /// - 若拼写已存在（词典词或占位符），就地更新释义，保留原始 ID 和所有引用
  /// - 若不存在，加入两张索引表
  void mergeFetchedWord(Word fetched) {
    var spell = fetched.word;
    if (spell == null) return;
    var existing = spellMap[spell];
    if (existing != null) {
      existing.means = fetched.means;
      if (fetched.usVoice != null && fetched.usVoice!.isNotEmpty)
        existing.usVoice = fetched.usVoice;
      if (fetched.ukVoice != null && fetched.ukVoice!.isNotEmpty)
        existing.ukVoice = fetched.ukVoice;
      if (fetched.sentences != null && fetched.sentences!.isNotEmpty)
        existing.sentences = fetched.sentences;
      if (existing.helper == null || existing.helper!.isEmpty)
        existing.helper = fetched.helper;
    } else {
      wordMap[fetched.id!] = fetched;
      spellMap[spell] = fetched;
    }
  }

  Future<void> loadWords() async {
    if (loaded) return;

    if (_isLoading) {
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }
    _isLoading = true;

    try {
      var words = await readWordMap();
      var books = await readBookMap(words);
      await _filterDeletedSystemWords(books);
      wordMap.addAll(words);

      // 同步构建拼写索引
      try {
        spellMap.clear();
        for (var w in wordMap.values) {
          if (w.word != null) spellMap[w.word!] = w;
        }
      } catch (e) {
        print('[WordService] spellMap build error: $e');
      }

      systemBookNames.clear();
      for (var value in books) {
        var name = value.name!;
        bookMap[name] = value;
        if (!systemBookNames.contains(name)) systemBookNames.add(name);
      }

      loadFetchedWordsCache(wordMap, spellMap);

      // 将网络缓存词并入索引（对已有空释义的词，用有释义的缓存覆盖）
      try {
        for (var w in wordMap.values) {
          if (w.word != null) {
            var existing = spellMap[w.word!];
            bool existingEmpty = existing == null ||
                existing.means == null ||
                existing.means!.trim().isEmpty;
            bool newHasMeans = w.means != null && w.means!.trim().isNotEmpty;
            if (existing == null || (existingEmpty && newHasMeans)) {
              spellMap[w.word!] = w;
            }
          }
        }
      } catch (e) {
        print('[WordService] spellMap cache sync error: $e');
      }

      await loadCustomBooks();
      activateDifficultBook(_activeBookId());
      loaded = true;
    } catch (e) {
      print('[WordService] FATAL ERROR during loadWords: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> loadCustomBooks() async {
    try {
      var storage = GetStorage();
      Map<String, dynamic> customData = storage.read('custom_books') ?? {};
      final previousNames = customBookNames.toList();

      customBookNames.clear();
      for (final name in previousNames) {
        if (!customData.containsKey(name)) {
          bookMap.remove(name);
        }
      }
      customData.forEach((name, spells) {
        customBookNames.add(name);
        List<Word> words = [];

        if (spells is List) {
          Set<String> seen = {};
          for (var s in spells) {
            String spellStr = s.toString();
            if (!seen.add(spellStr)) continue; // 去重：跳过已添加的单词
            var find = spellMap[spellStr];

            if (find != null && find.id != null) {
              words.add(find);
            } else {
              var placeholder = Word(id: spellStr, word: spellStr, means: '');
              wordMap[spellStr] = placeholder;
              spellMap[spellStr] = placeholder;
              words.add(placeholder);
            }
          }
        }
        String id = storage.read('book_id_$name') ?? "${name.hashCode.abs()}";
        bookMap[name] = Book(id: id, name: name, words: words);
      });
      await _ensureCustomBookRowsInDb();
    } catch (e) {
      print('[WordService] loadCustomBooks error: $e');
    }
  }

  Future<void> _ensureCustomBookRowsInDb() async {
    if (!Get.isRegistered<WordDao>()) return;
    final dao = Get.find<WordDao>();
    for (final name in customBookNames) {
      final book = bookMap[name];
      final bookId = int.tryParse(book?.id ?? '');
      if (book == null || book.words == null || bookId == null) continue;
      final desired = book.words!
          .map((word) => word.id)
          .whereType<String>()
          .where((wordId) => wordId.isNotEmpty)
          .toSet();
      if (desired.isEmpty) continue;
      final existingRows = await dao.queryWords(bookId);
      final existing =
          existingRows.map((word) => word.word).whereType<String>().toSet();
      for (final wordId in desired.difference(existing)) {
        await dao.addWord(WordPO(word: wordId, book: book.id));
      }
    }
  }

  String? _activeBookId() {
    final selectedName = GetStorage().read('study.bookName');
    if (selectedName is! String) return null;
    final id = bookMap[selectedName]?.id;
    return id == null || id.isEmpty ? null : id;
  }

  String? _resolveBookId(String? requestedBookId) {
    if (requestedBookId != null && requestedBookId.trim().isNotEmpty) {
      return requestedBookId.trim();
    }
    return _activeBookId();
  }

  Map<String, List<String>> _readDifficultWordMap(
    GetStorage storage, {
    String? activeBookId,
  }) {
    var byBook = DifficultWordStore.normalizeBookMap(
        storage.read(DifficultWordStore.byBookKey));
    final migrated = storage.read(DifficultWordStore.migrationKey) == true;
    final migrationTarget = activeBookId;
    if (!migrated && migrationTarget != null) {
      byBook = DifficultWordStore.migrateLegacy(
        byBook: byBook,
        legacyWords: DifficultWordStore.normalizeWords(
          storage.read(DifficultWordStore.legacyKey),
        ),
        activeBookId: migrationTarget,
        alreadyMigrated: false,
      );
      storage.write(DifficultWordStore.byBookKey, byBook);
      storage.write(DifficultWordStore.migrationKey, true);
    }
    return byBook;
  }

  /// Keeps the legacy global key as a mirror of the active book.
  ///
  /// StudyController still has a few direct reads/writes to `difficult_words`.
  /// The per-book map is authoritative, while this mirror preserves those
  /// existing call sites and migrates the old global data exactly once.
  void activateDifficultBook(String? bookId) {
    if (bookId == null || bookId.isEmpty) return;
    final storage = GetStorage();
    var byBook = _readDifficultWordMap(storage, activeBookId: bookId);
    final mirrorBook =
        storage.read(DifficultWordStore.mirrorBookKey)?.toString();
    if (mirrorBook != null && mirrorBook.isNotEmpty && mirrorBook != bookId) {
      byBook[mirrorBook] = DifficultWordStore.normalizeWords(
        storage.read(DifficultWordStore.legacyKey),
      );
      storage.write(DifficultWordStore.byBookKey, byBook);
    }
    final words = byBook[bookId] ?? <String>[];
    storage.write(DifficultWordStore.mirrorBookKey, bookId);
    storage.write(DifficultWordStore.legacyKey, words);
  }

  Future<bool> addWordToDifficultBook(String spell, {String? bookId}) async {
    final normalized = spell.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final storage = GetStorage();
    final activeBookId = _activeBookId();
    final resolvedBookId = _resolveBookId(bookId);

    // Preserve the old global behavior if no book has been selected yet.
    if (resolvedBookId == null) {
      final words = DifficultWordStore.normalizeWords(
        storage.read(DifficultWordStore.legacyKey),
      );
      if (words.contains(normalized)) return false;
      words
        ..add(normalized)
        ..sort();
      await storage.write(DifficultWordStore.legacyKey, words);
      return true;
    }

    final words = getDifficultWords(bookId: resolvedBookId);
    if (words.contains(normalized)) return false;
    final byBook = _readDifficultWordMap(storage, activeBookId: activeBookId);
    words
      ..add(normalized)
      ..sort();
    byBook[resolvedBookId] = words;
    await storage.write(DifficultWordStore.byBookKey, byBook);
    if (activeBookId == resolvedBookId) {
      await storage.write(DifficultWordStore.mirrorBookKey, resolvedBookId);
      await storage.write(DifficultWordStore.legacyKey, words);
    }
    return true;
  }

  Future<bool> removeWordFromDifficultBook(
    String spell, {
    String? bookId,
  }) async {
    final normalized = spell.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final storage = GetStorage();
    final activeBookId = _activeBookId();
    final resolvedBookId = _resolveBookId(bookId);
    if (resolvedBookId == null) {
      final words = DifficultWordStore.normalizeWords(
        storage.read(DifficultWordStore.legacyKey),
      );
      if (!words.remove(normalized)) return false;
      await storage.write(DifficultWordStore.legacyKey, words);
      return true;
    }

    final words = getDifficultWords(bookId: resolvedBookId);
    if (!words.remove(normalized)) return false;
    final byBook = _readDifficultWordMap(storage, activeBookId: activeBookId);
    byBook[resolvedBookId] = words;
    await storage.write(DifficultWordStore.byBookKey, byBook);
    if (activeBookId == resolvedBookId) {
      await storage.write(DifficultWordStore.legacyKey, words);
    }
    return true;
  }

  Future<void> clearDifficultWordsForBook(String bookId) async {
    final storage = GetStorage();
    final activeBookId = _activeBookId();
    final byBook = _readDifficultWordMap(storage, activeBookId: activeBookId);
    byBook.remove(bookId);
    await storage.write(DifficultWordStore.byBookKey, byBook);
    if (activeBookId == bookId) {
      await storage.write(DifficultWordStore.legacyKey, <String>[]);
    }
  }

  List<String> getDifficultWords({String? bookId}) {
    final storage = GetStorage();
    final activeBookId = _activeBookId();
    final resolvedBookId = _resolveBookId(bookId);
    if (resolvedBookId == null) {
      return DifficultWordStore.normalizeWords(
        storage.read(DifficultWordStore.legacyKey),
      );
    }

    var byBook = _readDifficultWordMap(storage, activeBookId: activeBookId);
    if (activeBookId == resolvedBookId) {
      final mirrorBook =
          storage.read(DifficultWordStore.mirrorBookKey)?.toString();
      if (mirrorBook == resolvedBookId) {
        final legacyRaw = storage.read(DifficultWordStore.legacyKey);
        if (legacyRaw is List) {
          byBook[resolvedBookId] = DifficultWordStore.normalizeWords(legacyRaw);
          storage.write(DifficultWordStore.byBookKey, byBook);
        }
      } else {
        storage.write(DifficultWordStore.mirrorBookKey, resolvedBookId);
        storage.write(
          DifficultWordStore.legacyKey,
          byBook[resolvedBookId] ?? <String>[],
        );
      }
    }
    return List<String>.from(byBook[resolvedBookId] ?? const <String>[]);
  }

  bool isDifficultWord(String spell, {String? bookId}) {
    return getDifficultWords(bookId: bookId)
        .contains(spell.trim().toLowerCase());
  }

  String _deletedSystemWordsKey(String bookId) =>
      'deleted_system_words_$bookId';

  Set<String> deletedSystemWordSpellings(String bookId) {
    return DifficultWordStore.normalizeWords(
      GetStorage().read(_deletedSystemWordsKey(bookId)),
    ).toSet();
  }

  Future<void> hideSystemWord(String bookId, String spell) async {
    final normalized = spell.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final storage = GetStorage();
    final words = deletedSystemWordSpellings(bookId)..add(normalized);
    final sorted = words.toList()..sort();
    await storage.write(_deletedSystemWordsKey(bookId), sorted);
  }

  Future<void> _filterDeletedSystemWords(List<Book> books) async {
    final hasWordDao = Get.isRegistered<WordDao>();
    final wordDao = hasWordDao ? Get.find<WordDao>() : null;
    for (final book in books) {
      final bookId = book.id;
      if (bookId == null || bookId.isEmpty) continue;
      final deleted = deletedSystemWordSpellings(bookId);
      if (deleted.isEmpty) continue;

      final deletedIds = <String>{};
      for (final word in book.words ?? const <Word>[]) {
        final spelling = word.word?.trim().toLowerCase();
        final id = word.id;
        if (spelling != null && deleted.contains(spelling) && id != null) {
          deletedIds.add(id);
        }
      }
      book.words?.removeWhere(
        (word) => deleted.contains(word.word?.trim().toLowerCase()),
      );

      final numericBookId = int.tryParse(bookId);
      if (wordDao == null || numericBookId == null) continue;
      for (final wordId in deletedIds) {
        try {
          await wordDao.deleteBookWord(numericBookId, wordId);
          await wordDao.deleteWordStatus(numericBookId, wordId);
        } catch (_) {
          // The in-memory overlay still hides the word; retry on next load.
        }
      }
    }
  }
}
