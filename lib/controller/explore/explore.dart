// lib/controller/explore/explore.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../dao/word/word.dart';
import '../../entity/word/vo/word.dart';
import '../../service/app/app.dart';
import '../../util/dictionary.dart';
import '../home/home_v2.dart';
import '../main/main_controller.dart';

class ExploreController extends GetxController {
  final AppService appService = Get.find();
  var searchResult = <WordVO>[].obs;
  final TextEditingController searchInput = TextEditingController();
  var isSearchingApi = false.obs;
  var validWordCounts = <String, int>{}.obs;

  @override
  void onInit() {
    super.onInit();
    loadValidCounts();
  }

  void loadValidCounts() async {
    var wordDao = Get.find<WordDao>();
    var deletedStatuses = await wordDao.queryAdapter.queryList(
      'SELECT word FROM word_status WHERE status = -1',
      mapper: (Map<String, Object?> row) => row['word'] as String,
    );
    Set<String> deletedWords = deletedStatuses.where((w) => w.contains('_')).toSet();

    for (var name in appService.wordService.systemBookNames) {
      var book = appService.wordService.bookMap[name];
      if (book != null && book.words != null) {
        int validCount = book.words!.where((w) => w.id != null && !deletedWords.contains("${book.id}_${w.id}")).length;
        validWordCounts[name] = validCount;
      }
    }
  }

  void search(String q) {
    if (q.isEmpty) {
      searchResult.clear();
      isSearchingApi.value = false;
      return;
    }

    String query = q.toLowerCase().trim();

    var allMatches = appService.wordService.wordMap.values
        .where((w) => w.word != null && w.word!.toLowerCase().contains(query))
        .toList();

    allMatches.sort((a, b) {
      String wordA = a.word!.toLowerCase();
      String wordB = b.word!.toLowerCase();
      bool exactA = wordA == query;
      bool exactB = wordB == query;
      if (exactA && !exactB) return -1;
      if (!exactA && exactB) return 1;
      bool startsA = wordA.startsWith(query);
      bool startsB = wordB.startsWith(query);
      if (startsA && !startsB) return -1;
      if (!startsA && startsB) return 1;
      if (wordA.length != wordB.length) {
        return wordA.length.compareTo(wordB.length);
      }
      return wordA.compareTo(wordB);
    });

    var results = allMatches
        .take(20)
        .map((e) => appService.toWordVO(e)!)
        .toList();

    searchResult.value = results;

    // 本地完全匹配没命中，且是纯英文单词 → 自动从 API 拉取
    final hasExact = allMatches.any((w) => w.word!.toLowerCase() == query);
    if (!hasExact && RegExp(r'^[a-zA-Z]+$').hasMatch(query) && query.length >= 2) {
      _fetchFromApi(query);
    }
  }

  void _fetchFromApi(String spell) async {
    print('[SEARCH] _fetchFromApi "$spell" triggered');
    isSearchingApi.value = true;
    final word = await fetchWordDefinition(spell);
    if (word != null) {
      appService.wordService.wordMap[word.id!] = word;
      final vo = appService.toWordVO(word);
      if (vo != null && searchInput.text.trim().toLowerCase() == spell) {
        if (!searchResult.any((e) => e.word == vo.word)) {
          searchResult.insert(0, vo);
          searchResult.refresh();
        }
      }
    } else {
      print('[SEARCH] fetchWordDefinition returned null for "$spell"');
    }
    isSearchingApi.value = false;
  }

  void addToCustomLibrary(WordVO word) async {
    if (word.word == null) return;
    HapticFeedback.heavyImpact();

    List<String> customBooks = appService.wordService.customBookNames;

    if (customBooks.isEmpty) {
      await _addWordToSpecificLibrary(word.word!, "我的生词本");
      return;
    }

    bool isDark = Get.isDarkMode;

    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text("选择要加入的生词本", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: customBooks.map((bookName) => ListTile(
                      leading: Icon(Icons.library_books, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
                      title: Text(bookName, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      onTap: () async {
                        Get.back();
                        await _addWordToSpecificLibrary(word.word!, bookName);
                      },
                    )).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _addWordToSpecificLibrary(String spell, String bookName) async {
    print('[ADD] _addWordToSpecificLibrary spell="$spell" book="$bookName"');
    var storage = GetStorage();
    Map<String, dynamic> customData = storage.read('custom_books') ?? {};

    List<String> words = List<String>.from(customData[bookName] ?? []);
    if (!words.contains(spell)) {
      words.add(spell);
      words.sort();
      customData[bookName] = words;
      await storage.write('custom_books', customData);
      print('[ADD] saved spell to custom_books, book "$bookName" now has ${words.length} words');

      if (storage.read('book_id_$bookName') == null) {
        String customId = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
        await storage.write('book_id_$bookName', customId);
        print('[ADD] assigned new book_id=$customId');
      }

      await appService.wordService.loadCustomBooks();
      await appService.insertCustomBookToDb(bookName);

      final existing = appService.getWordBySpell(spell);
      print('[ADD] getWordBySpell("$spell") = ${existing != null ? "FOUND id=${existing.id}" : "NULL"}');
      if (existing == null) {
        print('[ADD] word not in wordMap, fetching from API...');
        final fetched = await fetchWordDefinition(spell);
        print('[ADD] fetchWordDefinition("$spell") = ${fetched != null ? "OK id=${fetched.id}" : "NULL"}');
        if (fetched != null) {
          appService.wordService.wordMap[fetched.id!] = fetched;
          print('[ADD] added to wordMap[id=${fetched.id}], wordMap now has ${appService.wordService.wordMap.length} entries');
          await appService.wordService.loadCustomBooks();
          print('[ADD] after reloadCustomBooks, book words count: ${appService.wordService.bookMap[bookName]?.words?.length}');
          await appService.insertCustomBookToDb(bookName);
          Get.snackbar("收藏成功", "已从网络获取《$spell》释义并加入《$bookName》");
          return;
        }
      }

      Get.snackbar("收藏成功", "已加入《$bookName》");
    } else {
      Get.snackbar("提示", "《$bookName》中已存在该词");
    }
  }

  // 新增：专门处理系统词书的切换，并同步刷新首页
  void selectSystemBook(String bookName) {
    appService.promptAndSelectBook(bookName);
  }
}