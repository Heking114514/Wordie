// lib/service/word/word.dart
import 'package:english/dicts/reader.dart';
import 'package:english/util/dictionary.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

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
    } catch (e) {
      print('[WordService] loadCustomBooks error: $e');
    }
  }

  Future<bool> addWordToDifficultBook(String spell) async {
    var storage = GetStorage();
    List<String> words =
        List<String>.from(storage.read('difficult_words') ?? []);
    if (words.contains(spell)) {
      return false;
    }
    words.add(spell);
    words.sort();
    await storage.write('difficult_words', words);
    return true;
  }

  List<String> getDifficultWords() {
    var storage = GetStorage();
    return List<String>.from(storage.read('difficult_words') ?? []);
  }
}
