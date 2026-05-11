import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controller/statistic/statistic.dart';

class StatisticPage extends GetView<StatisticController> {
  const StatisticPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("学习统计", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false, 
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("你的学习总览", style: TextStyle(fontSize: 15, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
            const SizedBox(height: 20),
            
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              children: [
                _buildStatCard(
                  isDark: isDark,
                  title: "总学习时长", 
                  valueText: Obx(() => Text("${controller.totalStudyTime.value}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B)))), 
                  unit: "分钟", 
                  icon: Icons.timer, 
                  color: const Color(0xFF3B82F6)
                ),
                _buildStatCard(
                  isDark: isDark,
                  title: "累计学习词汇", 
                  valueText: Obx(() => Text("${controller.totalLearnedWords.value}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B)))), 
                  unit: "个", 
                  icon: Icons.translate, 
                  color: const Color(0xFF10B981)
                ),
                _buildStatCard(
                  isDark: isDark,
                  title: "自定义词书", 
                  valueText: Obx(() => Text("${controller.customBookCount.value}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B)))), 
                  unit: "本", 
                  icon: Icons.my_library_books, 
                  color: const Color(0xFFA855F7)
                ),
                _buildStatCard(
                  isDark: isDark,
                  title: "待复习词汇", 
                  valueText: Obx(() => Text("${controller.needReviewWords.value}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)))), 
                  unit: "个", 
                  icon: Icons.history_edu, 
                  color: const Color(0xFFF59E0B)
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({required bool isDark, required String title, required Widget valueText, required String unit, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.transparent),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              valueText,
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(unit, style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}