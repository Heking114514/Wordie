import 'package:english/controller/selectBook/selectBook.dart';
import 'package:english/controller/study/wordList.dart';
import 'package:english/view/selectBook/selectBook.dart';
import 'package:get/get.dart';

// --- 导入控制器 ---
import '../controller/main/main_controller.dart';
import '../controller/home/home_v2.dart';
import '../controller/explore/explore.dart';
import '../controller/statistic/statistic.dart';
import '../controller/selectBook/selectBook.dart';
import '../controller/study/study.dart';
import '../controller/study/review_library_controller.dart';
import '../controller/import/import.dart';

// --- 导入视图 ---
import '../view/main/main_page.dart';
import '../view/home/home_v2.dart';
import '../view/explore/explore.dart';
import '../view/statistic/statistic.dart';
import '../view/selectBook/selectBook.dart';
import '../view/study/study.dart';
import '../view/study/review_library_page.dart';
import '../view/import/import.dart';
import '../view/splash/splash_page.dart';

// --- 导入服务 ---
import '../service/home/home.dart';
import '../service/study/study.dart';

var pages = [
  GetPage(
      name: "/",
      page: () => const SplashPage()),

  GetPage(
      name: "/main",
      page: () {
        Get.lazyPut(() => HomeService());
        Get.lazyPut(() => MainController());
        Get.lazyPut(() => HomeControllerV2());
        Get.lazyPut(() => ExploreController());
        Get.lazyPut(() => StatisticController());
        return const MainPage();
      }),

  GetPage(
      name: "/study",
      page: () {
        Get.put(StudyService());
        Get.put(StudyController());
        return StudyPage();
      }),

  GetPage(
      name: "/selectBook",
      page: () {
        Get.put(SelectBookController());
        return SelectBookPage();
      }),

  GetPage(
      name: "/statistic",
      page: () {
        Get.put(StatisticController());
        return StatisticPage();
      }),

  GetPage(
      name: "/review_library",
      page: () {
        Get.put(ReviewLibraryController());
        return const ReviewLibraryPage();
      }),

  GetPage(
      name: "/explore",
      page: () {
        Get.put(ExploreController());
        return ExplorePage();
      }),

  GetPage(
      name: "/import",
      page: () {
        Get.put(ImportController());
        return ImportPage();
      }),
];
