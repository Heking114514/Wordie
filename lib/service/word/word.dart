// lib/service/word/word.dart
import 'package:english/dicts/reader.dart';
import 'package:english/util/dictionary.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:get/get.dart'; 

class WordService {
  var bookNames =[
    "小学英语", "初中英语", "高中英语", "大学英语四级词汇",
    "大学英语六级词汇", "大学英语专业四级", "大学英语专业八级",
    "全国等级考试", "考研英语", "考博英语", "BEC词汇",
    "GMAT词汇", "GRE词汇", "托福词汇", "雅思词汇",
    "托业词汇", "SAT词汇", "ACT词汇", "MBA词汇",
  ];
  var bookInfo = {
    "小学英语": {"color":Color(0xFF2A5485), "fontColor":Colors.white, "title":"小学", "subTitle":"小学英语"},
    "初中英语": {"color":Color(0xFF471DA9), "fontColor":Colors.white, "title":"初中", "subTitle":"初中英语"},
    "高中英语": {"color":Color(0xFF137A52), "fontColor":Colors.white, "title":"高中", "subTitle":"高中英语"},
    "大学英语四级词汇": {"color":Color(0xFF4E7C16), "fontColor":Colors.white, "title":"四级", "subTitle":"四级词汇"},
    "大学英语六级词汇": {"color":Color(0xFF8F4D1F), "fontColor":Colors.white, "title":"六级", "subTitle":"六级词汇"},
    "大学英语专业四级": {"color":Color(0xFF73143F), "fontColor":Colors.white, "title":"专四", "subTitle":"专业四级词汇"},
    "大学英语专业八级": {"color":Color(0xFF611DA1), "fontColor":Colors.white, "title":"专八", "subTitle":"专业八级词汇"},
    "考博英语": {"color":Color(0xFF6B802D), "fontColor":Colors.white, "title":"考博", "subTitle":"考博英语"},
    "考研英语": {"color":Color(0xFFA2342A), "fontColor":Colors.white, "title":"考研", "subTitle":"考研英语"},
    "全国等级考试": {"color":Color(0xFF88580F), "fontColor":Colors.white, "title":"等级考试", "subTitle":"全国等级考试"},
    "BEC词汇": {"color":Color(0xFF750E58), "fontColor":Colors.white, "title":"BEC", "subTitle":"BEC词汇"},
    "GMAT词汇": {"color":Color(0xFF387312), "fontColor":Colors.white, "title":"GMAT", "subTitle":"GMAT词汇"},
    "GRE词汇": {"color":Color(0xFF0F4B8F), "fontColor":Colors.white, "title":"GRE", "subTitle":"GRE词汇"},
    "托福词汇": {"color":Color(0xFF7C300E), "fontColor":Colors.white, "title":"托福", "subTitle":"托福词汇"},
    "雅思词汇": {"color":Color(0xFF528D21), "fontColor":Colors.white, "title":"雅思", "subTitle":"雅思词汇"},
    "托业词汇": {"color":Color(0xFF8C1136), "fontColor":Colors.white, "title":"托业", "subTitle":"托业词汇"},
    "SAT词汇": {"color":Color(0xFF438535), "fontColor":Colors.white, "title":"SAT", "subTitle":"SAT词汇"},
    "ACT词汇": {"color": Color(0xFF8A6515), "fontColor":Colors.white, "title":"ACT", "subTitle":"ACT词汇"},
    "MBA词汇": {"color":Color(0xFFB61553), "fontColor":Colors.white, "title":"MBA", "subTitle":"MBA词汇"},
  };
  var systemBookNames = <String>[].obs;
  var customBookNames = <String>[].obs;
  var wordMap = <String, Word>{};
  var bookMap = <String, Book>{};

  // O(1) 拼写极速查询索引
  var spellMap = <String, Word>{};

  var loaded = false;
  bool _isLoading = false;

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

      loadFetchedWordsCache(wordMap);

      // 将网络缓存词并入索引
      try {
        for (var w in wordMap.values) {
          if (w.word != null && !spellMap.containsKey(w.word)) {
            spellMap[w.word!] = w;
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

      customBookNames.clear();
      customData.forEach((name, spells) {
        customBookNames.add(name);
        List<Word> words = [];

        if (spells is List) {
          for (var s in spells) {
            String spellStr = s.toString();
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
    List<String> words = List<String>.from(storage.read('difficult_words') ?? []);
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

  Future<void> addWordToRawLibrary(String spell) async {
    const String libName = "raw words";
    var storage = GetStorage();
    Map<String, dynamic> customData = storage.read('custom_books') ?? {};

    List<String> words = List<String>.from(customData[libName] ??[]);
    if (!words.contains(spell)) {
      words.add(spell);
      // ==== 修复：加入单调词后强行排序保存 ====
      words.sort(); 
      customData[libName] = words;
      await storage.write('custom_books', customData);

      if (storage.read('book_id_$libName') == null) {
        await storage.write('book_id_$libName', "1001");
      }
      await loadCustomBooks(); 
    }
  }

  Future<void> addCustomBook(String bookName, List<String> spells) async {
    var storage = GetStorage();
    Map<String, dynamic> customBooks = storage.read('custom_books') ?? {};
    
    // ==== 修复：加入自定义词库前强行去重排序 ====
    List<String> sortedSpells = spells.toSet().toList()..sort();
    customBooks[bookName] = sortedSpells; 

    String customId = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    storage.write('book_id_$bookName', customId);
    await storage.write('custom_books', customBooks);

    loaded = false;
    await loadWords();
  }
}