import 'dart:convert';
import 'dart:typed_data';

import 'package:english/dao/word/word.dart';
import 'package:english/dicts/reader.dart';
import 'package:english/service/word/word.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../entity/word/po/word.dart';
import '../../entity/word/vo/word.dart';

class AppService {
  WordService wordService = Get.find();
  var wordDao = Get.find<WordDao>();
  var queueCount = 4;
  int dailyWantCount = 100;
  bool autoPass = false;
  bool autoPlayVoice = true; // 新增：独立的发音设置开关
  String? _bookName;

  String get bookName {
    return _bookName ?? wordService.bookNames[0];
  }

  String getBookId(String? bookName) {
    return wordService.bookMap[bookName]?.id ?? "2";
  }

  int get bookId {
    return int.parse(getBookId(_bookName));
  }

  int thinkWaitTime = 1;
  int readWaitTime = 7;

  //艾宾浩斯记忆曲线时间点
  List<int> get reviewTimes {
    int minutes = 60 * 1000;
    int hour = 60 * minutes;
    int day = 24 * 60 * 60 * 1000;
    int month = 30 * day;
    return [
      5 * minutes, 25 * minutes, hour,
      1 * day - hour, 1 * day - hour, 2 * day - hour, 3 * day - hour,
      8 * day - hour, month - 15 * day - hour, 1 * month - hour,
      2 * month - hour, 3 * month - hour, 8 * month - hour,
      15 * month - hour,
    ];
  }

  int get wordCount {
    return wordService.bookMap[bookName]?.words?.length ?? 0;
  }

  Future<void> insertCustomBookToDb(String customBookName) async {
    var book = wordService.bookMap[customBookName];
    print('[DB] insertCustomBookToDb "$customBookName" book=${book != null} words=${book?.words?.length}');
    if (book != null && book.words != null) {
      int bId = int.tryParse(book.id ?? '0') ?? 0;
      print('[DB] book.id="${book.id}" bId=$bId');
      if (bId != 0) {
        await wordDao.deleteBookWords(bId);
        print('[DB] deleted old words for bookId=$bId');
      }

      var wordPOs = book.words!.map((e) {
        return WordPO(word: e.id, book: book.id);
      }).toList();

      print('[DB] inserting ${wordPOs.length} WordPOs: ${wordPOs.map((e) => "word=${e.word} book=${e.book}").join(", ")}');
      if (wordPOs.isNotEmpty) {
        await wordDao.addWords(wordPOs);
        print('[DB] insert done');
      }
    } else {
      print('[DB] SKIP: book null or words null');
    }
  }

  Future<void> readWords() async {
    await wordService.loadWords();
  }

  Future<void> insertToDb() async {
    if (bookLoaded()) {
      return;
    }
    wordDao.clearWord();
    var start = DateTime.now().millisecondsSinceEpoch;
    var count = 0;
    for (var book in wordService.bookMap.values) {
      var words = book.words;
      if (words != null) {
        var wordPOs = words.map((e) {
          return WordPO(word: e.id, book: book.id);
        }).toList();
        count += wordPOs.length;
        await wordDao.addWords(wordPOs);
      }
    }
    var end = DateTime.now().millisecondsSinceEpoch;
    print('insert words use time: ${end - start} word count:$count');
    setBookLoaded();
  }

  bool bookLoaded() {
    var storage = GetStorage();
    return storage.read("book-loaded") == "true";
  }

  void setBookLoaded() {
    var storage = GetStorage();
    storage.write("book-loaded", "true");
    storage.save();
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
    storage.write('auto_play', autoPlayVoice); // 保存发音开关
    storage.save();
  }

  void readOptions() {
    var storage = GetStorage();
    var dCount = storage.read("study.dailyWantCount") ?? "100";
    dailyWantCount = int.parse(dCount.toString());
    var tWaitTime = storage.read("study.thinkWaitTime") ?? "1";
    thinkWaitTime = int.parse(tWaitTime.toString());
    var rWaitTime = storage.read("study.readWaitTime") ?? "7";
    readWaitTime = int.parse(rWaitTime.toString());
    var qCount = storage.read("study.queueCount") ?? "4";
    queueCount = int.parse(qCount.toString());

    _bookName = storage.read("study.bookName");
    var aPass = storage.read("autoPass");
    autoPass = aPass.toString() == "true";
    reviewDailyCount = int.parse((storage.read("study.reviewDailyCount") ?? "50").toString());
    
    autoPlayVoice = storage.read('auto_play') ?? true; // 读取发音开关
  }

  Word? getWord(String? id) {
    return wordService.wordMap[id];
  }

  Word? getWordBySpell(String? spell) {
    var find = wordService.wordMap.values
        .firstWhere((element) => element.word == spell, orElse: () {
      return Word();
    });
    if (find.id == null) return null;
    return find;
  }

  WordVO? getWordVO(String? id) {
    return toWordVO(wordService.wordMap[id]);
  }

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
    saveOptions();
  }

  Future<bool?> queryWordDeleteStatus(String? word) async {
    var status = await wordDao.queryWordStatus(word ?? "");
    var statusFlag = status?.status;
    return statusFlag == -1;
  }

  Future<void> deleteWord(String? wordId) async {
    await wordDao.upsetWordStatusById(wordId, -1);
  }

  Future<void> restoreWord(String? wordId) async {
    await wordDao.upsetWordStatusById(wordId, 0);
  }
}