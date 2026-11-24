import 'package:english/controller/app/app.dart';
import 'package:english/controller/study/study.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import '../../entity/word/vo/word.dart';
import '../../service/app/app.dart';

class WordListController extends GetxController {
  var pageController = PageController();
  var pageIndex = 0.obs;
  var title = "播放列表".obs;
  var passList = Rx(<String>[]);
  var deleteList = Rx(<String>[]);
  var allList = Rx(<WordVO>[]);
  var playingWords = <WordVO>[].obs;

  var wordSearchText = "".obs;
  @override
  void onInit() {
    super.onInit();
    fetchWordList();
  }

  Future<void> fetchWordList() async {
    await fetchBookPassWordList();
    await fetchBookDeleteWordList();
    await fetchBookAllWordList();
    playingWords.assignAll(Get.find<StudyController>().playingWords);
    onPageChanged(pageIndex.value);
  }

  /// 查询所有单词列表
  Future<void> fetchBookAllWordList() async {
    AppController app = Get.find();
    StudyController study = Get.find();
    var allList = await app.appService.wordDao
        .queryBookNotDeleteWord(app.appService.bookId);
    var all = allList.map((e) => study.appService.getWordVO(e)!).toList();
    this.allList.value = all;
  }

  /// 查询删除单词列表
  Future<void> fetchBookDeleteWordList() async {
    AppController app = Get.find();
    StudyController study = Get.find();
    var deleteList =
        await app.appService.wordDao.queryBookDeleteWord(app.appService.bookId);
    this.deleteList.value =
        deleteList.map((e) => study.appService.getWord(e)?.word ?? "").toList();
  }

  /// 查询pass单词列表
  Future<void> fetchBookPassWordList() async {
    AppController app = Get.find();
    StudyController study = Get.find();
    var passList =
        await app.appService.wordDao.queryBookPassWord(app.appService.bookId);
    this.passList.value =
        passList.map((e) => study.appService.getWord(e)?.word ?? "").toList();
  }

  @override
  void onReady() {
    super.onReady();
  }

  @override
  void onClose() {
    super.onClose();
  }

  void onPageChanged(int index) {
    pageIndex.value = index;
    StudyController studyService = Get.find();
    switch (index) {
      case 0:
        title.value = "播放列表 · ${studyService.playingWords.length}";
        break;
      case 1:
        title.value = "已学习(PASS) · ${passList.value.length}";
        break;
      case 2:
        title.value = "熟词库 · ${deleteList.value.length}";
        break;
      case 3:
        title.value = "全部单词 · ${allList.value.length}";
        break;
    }
  }

  WordVO? getWordVO(String word) {
    AppService wordService = Get.find();
    return wordService.toWordVO(wordService.getWordBySpell(word));
  }

  /// 根据单词含义搜索单词
  bool isContainsMeans(WordVO? word, String meansText) {
    var means = word?.means;
    if (means != null) {
      for (var mean in means) {
        var contains =
            mean.toString().toLowerCase().contains(meansText.toLowerCase());
        if (contains) {
          return true;
        }
      }
    }
    return false;
  }

  /// 熟词操作：退出学习/复习，但保留在当前词书的熟词库。
  Future<void> deleteWord(WordVO word) => markFamiliar(word);

  Future<void> markFamiliar(WordVO word) async {
    StudyController studyController = Get.find();
    await studyController.markFamiliarFromWordList(word);
    word.isDelete = true;
  }

  /// 永久删除：从当前词书的词源中移除，而不是放进熟词库。
  Future<bool> deleteWordPermanently(WordVO word) async {
    final studyController = Get.find<StudyController>();
    final deleted = await studyController.deleteWordPermanently(word);
    if (deleted) {
      word.isDelete = true;
      passList.value =
          passList.value.where((item) => item != word.word).toList();
      allList.value =
          allList.value.where((item) => item.wordId != word.wordId).toList();
      deleteList.value =
          deleteList.value.where((item) => item != word.word).toList();
    }
    return deleted;
  }

  /// 从熟词库恢复为待学习状态。
  Future<void> restoreWord(WordVO word) async {
    StudyController studyController = Get.find();
    await studyController.restoreWordFromWordList(word);
    word.isDelete = false;
  }

  /// 获取单词删除状态
  Future<void> getDeleteStatus(WordVO word) async {
    AppService wordService = Get.find();
    word.isDelete = await wordService.queryWordDeleteStatus(word.wordId);
  }
}
