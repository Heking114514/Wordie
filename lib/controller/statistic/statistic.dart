// lib/controller/statistic/statistic.dart
import 'package:get/get.dart';
import '../../dao/word/word.dart';
import '../../service/app/app.dart';

class StatisticController extends GetxController {
  final AppService appService = Get.find();
  final WordDao wordDao = Get.find<WordDao>();

  var totalStudyTime = 0.obs;     // 总共学习时长 (分钟)
  var customBookCount = 0.obs;    // 自定义单词书数量
  var totalLearnedWords = 0.obs;  // 一共背了多少词
  var needReviewWords = 0.obs;    // 还有多少词要复习

  @override
  void onInit() {
    super.onInit();
    fetchStats();
  }

  Future<void> fetchStats() async {
    // 1. 获取总学习时长
    var timeMs = (await wordDao.queryStudyTime()) ?? 0;
    totalStudyTime.value = timeMs ~/ (1000 * 60);

    // 2. 获取自定义单词书数量
    customBookCount.value = appService.wordService.customBookNames.length;

    // 3. 获取一共背了多少词 (使用 queryAdapter 直接查询所有状态为已学或进入周期的单词)
    var learnedCount = await wordDao.queryAdapter.query(
      'SELECT count(0) as count FROM word_status WHERE status=1 OR studyCycle>0',
      mapper: (Map<String, Object?> row) => row['count'] as int?,
    );
    totalLearnedWords.value = learnedCount ?? 0;

    // 4. 获取待复习单词数
    needReviewWords.value = (await wordDao.queryReviewWordCount()) ?? 0;
  }
}