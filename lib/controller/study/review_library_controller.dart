// lib/controller/study/review_library_controller.dart
import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/app/app.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart'; 

class ReviewLibraryController extends GetxController {
  final AppService appService = Get.find();
  final WordDao wordDao = Get.find<WordDao>();

  var allWords = <WordVO>[].obs;
  var displayWords = <WordVO>[].obs;
  
  var isLoading = true.obs;
  var searchText = "".obs;

  @override
  void onInit() {
    super.onInit();
    fetchReviewWords();
    debounce(searchText, (_) => _filterWords(), time: const Duration(milliseconds: 300));
  }

  Future<void> fetchReviewWords() async {
    isLoading.value = true;
    try {
      var pos = await wordDao.queryNeedReviewWords(9999);
      List<WordVO> vos =[];
      for (var po in pos) {
        var wordData = appService.getWord(po.word);
        var vo = appService.toWordVO(wordData);
        if (vo != null) {
          // === 核心修复点 3：通过强大的内存层层筛选，准确获得词书来源，不再依赖模糊的 SQL ===
          vo.usaVoice = _findAccurateSourceBook(vo.word); 
          vos.add(vo);
        }
      }
      allWords.value = vos;
      _filterWords();
    } catch (e) {
      print("加载复习库失败: $e");
    } finally {
      isLoading.value = false;
    }
  }

  // 精准锁定词书来源
  String _findAccurateSourceBook(String? wordText) {
    if (wordText == null || wordText.isEmpty) return "未知";
    var curBook = appService.bookName;
    
    // 1. 优先查当前正在背的书
    if (appService.wordService.bookMap[curBook]?.words?.any((w) => w.word == wordText) == true) {
      return curBook;
    }
    // 2. 其次查其他的自定义书
    for (var b in appService.wordService.customBookNames) {
      if (appService.wordService.bookMap[b]?.words?.any((w) => w.word == wordText) == true) return b;
    }
    // 3. 最后查系统书
    for (var b in appService.wordService.systemBookNames) {
      if (appService.wordService.bookMap[b]?.words?.any((w) => w.word == wordText) == true) return b;
    }
    return "外部导入";
  }

  void _filterWords() {
    if (searchText.value.isEmpty) {
      displayWords.value = List.from(allWords);
    } else {
      displayWords.value = allWords.where((word) {
        final query = searchText.value.toLowerCase();
        return (word.word?.toLowerCase().contains(query) ?? false) ||
               (word.means?.join().toLowerCase().contains(query) ?? false);
      }).toList();
    }
  }

  Future<void> returnToStudy(WordVO word) async {
    await wordDao.upsetWordStatusById(word.wordId, 0);
    allWords.removeWhere((element) => element.wordId == word.wordId);
    _filterWords();
    Get.snackbar("操作成功", "${word.word} 已移回新词库", snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> deletePermanently(WordVO word) async {
    if (word.wordId == null || word.word == null) {
      Get.snackbar("错误", "无法识别该单词数据");
      return;
    }

    var storage = GetStorage();
    Map<String, dynamic> customData = storage.read('custom_books') ?? {};
    bool removedFromCustom = false;

    // 1. 从所有的自定义书中，把这个单词摘除
    for (String bName in appService.wordService.customBookNames) {
      List<String> wList = List<String>.from(customData[bName] ??[]);
      if (wList.contains(word.word)) {
        wList.remove(word.word);
        customData[bName] = wList;
        appService.wordService.bookMap[bName]?.words?.removeWhere((e) => e.word == word.word);
        
        String bId = appService.wordService.bookMap[bName]?.id ?? "";
        if (bId.isNotEmpty) {
          await wordDao.queryAdapter.queryNoReturn(
              'DELETE FROM word WHERE word=?1 AND book=?2', 
              arguments:[word.wordId!, bId]
          );
        }
        removedFromCustom = true;
      }
    }

    if (removedFromCustom) {
      await storage.write('custom_books', customData);
    }

    // === 核心修复点 4：强制设定该单词状态为 -1 (熟词彻底删除) ===
    // 这样下次 `queryNeedReviewWords` SQL 查状态为 1 的时候，就绝对不可能再查到它了！
    await wordDao.upsetWordStatusById(word.wordId, -1);

    allWords.removeWhere((element) => element.wordId == word.wordId);
    _filterWords();
    Get.snackbar("操作成功", "${word.word} 已彻底移除不再出现", snackPosition: SnackPosition.BOTTOM);
  }
}