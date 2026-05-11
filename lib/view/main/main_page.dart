import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/main/main_controller.dart';
import '../home/home_v2.dart';
import '../explore/explore.dart';
import '../statistic/statistic.dart';
import '../profile/profile_page.dart';

class MainPage extends GetView<MainController> {
  const MainPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() => IndexedStack(
            index: controller.currentIndex.value,
            children: [
              const HomeViewV2(),
              const ExplorePage(),
              const StatisticPage(),
              const ProfilePage(),
            ],
          )),
      bottomNavigationBar: Obx(() {
        bool isDark = Theme.of(context).brightness == Brightness.dark;
        return BottomNavigationBar(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          type: BottomNavigationBarType.fixed,
          currentIndex: controller.currentIndex.value,
          selectedItemColor: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
          unselectedItemColor: const Color(0xFF94A3B8),
          showUnselectedLabels: true,
          elevation: 10,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "首页"),
            BottomNavigationBarItem(icon: Icon(Icons.explore), label: "探索"),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "统计"),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: "我的"),
          ],
          onTap: controller.changePage,
        );
      }),
    );
  }
}