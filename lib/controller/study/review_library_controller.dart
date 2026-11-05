// lib/controller/study/review_library_controller.dart
import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/app/app.dart';
import 'package:english/service/study/study.dart';
import 'package:get/get.dart';
import '../../controller/selectBook/selectBook.dart';

class ReviewLibraryController extends GetxController {
  final AppService appService = Get.find();
  final WordDao wordDao = Get.find<WordDao>();
  final StudyService studyService = StudyService();

  var allWords = <WordVO>[].obs;
  var displayWords = <WordVO>[].obs;

  var isLoading = true.obs;
  var searchText = "".obs;

  @override
  void onInit() {
    super.onInit();
    fetchReviewWords();
    debounce(searchText, (_) => _filterWords(),
        time: const Duration(milliseconds: 300));
  }

  Future<void> fetchReviewWords() async {
    isLoading.value = true;
    try {
      await appService.readWords();
      var pos = await wordDao.queryTodayReviewWords();
      List<WordVO> vos = [];
      for (var po in pos) {
        var wordData = appService.getWord(po.word);
        var vo = appService.toWordVO(wordData);
        if (vo != null) {
          vo.wordId = po.word;
          vo.helper = po.book;
          vo.sentenceOrigin = _bookNameForId(po.book);
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

  String _bookNameForId(String? bookId) {
    for (final entry in appService.wordService.bookMap.entries) {
      if (entry.value.id == bookId) return entry.key;
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
    int bId = int.tryParse(word.helper ?? "") ?? appService.bookId;
    await wordDao.restoreWordForStudy(word.wordId, bId);
    if (word.wordId != null) {
      await studyService.removeReviewWordState(bId, word.wordId!);
    }
    allWords.removeWhere(
      (element) =>
          element.wordId == word.wordId && element.helper == word.helper,
    );
    _filterWords();
    Get.snackbar("操作成功", "${word.word} 已移回新词库",
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> deletePermanently(WordVO word) async {
    if (word.wordId == null || word.word == null) {
      Get.snackbar("错误", "无法识别该单词数据");
      return;
    }

    int bId = int.tryParse(word.helper ?? "") ?? appService.bookId;
    final sourceBook = _bookNameForId(word.helper);
    if (appService.wordService.customBookNames.contains(sourceBook)) {
      await appService.removeWordFromCustomBook(sourceBook, word.word!);
    }
    await wordDao.markWordFamiliarById(word.wordId, bId);
    await studyService.removeReviewWordState(bId, word.wordId!);

    allWords.removeWhere(
      (element) =>
          element.wordId == word.wordId && element.helper == word.helper,
    );
    _filterWords();
    if (Get.isRegistered<SelectBookController>()) {
      Get.find<SelectBookController>().refreshBooks();
    }
    Get.snackbar("操作成功", "${word.word} 已彻底移除不再出现",
        snackPosition: SnackPosition.BOTTOM);
  }
}
