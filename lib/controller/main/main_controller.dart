import 'package:get/get.dart';
import '../../controller/home/home_v2.dart';
import '../../controller/explore/explore.dart';
import '../../controller/statistic/statistic.dart';
import '../../controller/profile/profile_controller.dart'; // 导入个人中心控制器

class MainController extends GetxController {
  var currentIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    Get.put(HomeControllerV2());
    Get.put(ExploreController());
    Get.put(StatisticController());
    Get.put(ProfileController()); // 初始化
  }

  void changePage(int index) {
    currentIndex.value = index;
    if (index == 0 && Get.isRegistered<HomeControllerV2>()) {
      Get.find<HomeControllerV2>().fetchInfo();
    } else if (index == 2 && Get.isRegistered<StatisticController>()) {
      Get.find<StatisticController>().fetchStats();
    } else if (index == 3 && Get.isRegistered<ProfileController>()) {
      Get.find<ProfileController>().fetchProfileData(); // 切换时拉取打卡数据
    }
  }
}