import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controller/study/review_library_controller.dart';
import '../../entity/word/vo/word.dart';

class ReviewLibraryPage extends GetView<ReviewLibraryController> {
  const ReviewLibraryPage({Key? key}) : super(key: key);

  // ---------------- 黑暗模式颜色映射 ----------------
  Color _getBgColor(bool isDark) => isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color _getCardColor(bool isDark) => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color _getTextMain(bool isDark) => isDark ? Colors.white : const Color(0xFF1E293B);
  Color _getTextMuted(bool isDark) => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color _getBorderColor(bool isDark) => isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
  Color _getPrimaryColor(bool isDark) => isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    // 获取当前系统的深浅模式状态
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _getBgColor(isDark),
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          // 搜索框区域
          _buildSearchSection(isDark),
          
          // 词库内容列表
          Expanded(
            child: Obx(() {
              // 加载状态
              if (controller.isLoading.value) {
                return Center(
                  child: CircularProgressIndicator(color: _getPrimaryColor(isDark)),
                );
              }
              
              // 空库状态
              if (controller.displayWords.isEmpty) {
                return _buildEmptyState(isDark);
              }

              // 单词列表
              return ListView.separated(
                // 彻底移除回弹手感，使用原生稳重感布局
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 30),
                itemCount: controller.displayWords.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1, 
                  color: _getBorderColor(isDark), 
                  indent: 20, 
                  endIndent: 20
                ),
                itemBuilder: (context, index) {
                  return _buildWordItem(controller.displayWords[index], isDark);
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  // ---------------- AppBar 构建 ----------------
  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      leading: IconButton(
        icon: Icon(Icons.chevron_left, color: _getTextMain(isDark), size: 28),
        onPressed: () => Get.back(),
      ),
      title: Text(
        "待复习词库",
        style: TextStyle(
          color: _getTextMain(isDark),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
      actions: [
        Obx(() => Container(
          padding: const EdgeInsets.only(right: 20),
          alignment: Alignment.center,
          child: Text(
            "共 ${controller.allWords.length} 词",
            style: TextStyle(color: _getTextMuted(isDark), fontSize: 13),
          ),
        ))
      ],
    );
  }

  // ---------------- 搜索框构建 ----------------
  Widget _buildSearchSection(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(15),
        ),
        child: TextField(
          onChanged: (v) => controller.searchText.value = v,
          style: TextStyle(fontSize: 15, color: _getTextMain(isDark)),
          decoration: InputDecoration(
            icon: Icon(Icons.search, color: _getTextMuted(isDark), size: 20),
            hintText: "快速查找单词或释义...",
            hintStyle: TextStyle(color: _getTextMuted(isDark), fontSize: 15),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  // ---------------- 单词行构建 ----------------
  Widget _buildWordItem(WordVO word, bool isDark) {
    return Material(
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: InkWell(
        // 点击预览发音
        onTap: () {
          // 这里可以调用播放音频的逻辑
        },
        // 长按呼出高级操作菜单
        onLongPress: () {
          HapticFeedback.mediumImpact(); // 给予物理反馈
          _showActionMenu(word, isDark);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.word ?? "",
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.w600, 
                        color: _getPrimaryColor(isDark),
                        letterSpacing: 0.2
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      word.means?.join("；") ?? "暂无释义",
                      style: TextStyle(fontSize: 14, color: _getTextMain(isDark).withOpacity(0.8)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // 显示单词来源书籍，解耦来源识别
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getBorderColor(isDark),
                        borderRadius: BorderRadius.circular(4)
                      ),
                      child: Text(
                        "来自：${word.usaVoice ?? '外部导入'}", 
                        style: TextStyle(
                          fontSize: 10, 
                          color: _getTextMuted(isDark),
                          fontWeight: FontWeight.w500
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.more_horiz, color: _getTextMuted(isDark).withOpacity(0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 空状态构建 ----------------
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_motion_rounded, size: 64, color: _getBorderColor(isDark)),
          const SizedBox(height: 16),
          Text(
            controller.searchText.value.isEmpty ? "复习库空空如也\n快去学习新词吧！" : "没有找到相关的单词",
            textAlign: TextAlign.center,
            style: TextStyle(color: _getTextMuted(isDark), fontSize: 15, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ---------------- 底部操作面板构建 ----------------
  void _showActionMenu(WordVO word, bool isDark) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: _getCardColor(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 指示条
            Container(
              width: 40, height: 4, 
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: _getBorderColor(isDark), borderRadius: BorderRadius.circular(2)),
            ),
            Text(
              "针对该单词的操作", 
              style: TextStyle(color: _getTextMuted(isDark), fontSize: 13)
            ),
            const SizedBox(height: 10),
            Text(
              word.word ?? "",
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold, 
                color: _getPrimaryColor(isDark)
              ),
            ),
            const SizedBox(height: 30),
            
            // 操作一：移回生词库
            _buildActionButton(
              label: "移回新词库重新学习", 
              icon: Icons.refresh_rounded, 
              color: _getPrimaryColor(isDark), 
              bg: _getPrimaryColor(isDark).withOpacity(0.12), 
              onTap: () {
                Get.back();
                controller.returnToStudy(word);
              }
            ),
            
            const SizedBox(height: 12),
            
            // 操作二：彻底永久删除
            _buildActionButton(
              label: "从此词书中彻底移除", 
              icon: Icons.delete_forever_rounded, 
              color: const Color(0xFFEF4444), 
              bg: const Color(0xFFEF4444).withOpacity(0.12), 
              onTap: () {
                Get.back();
                controller.deletePermanently(word);
              }
            ),
            
            const SizedBox(height: 20),
            
            // 取消
            TextButton(
              onPressed: () => Get.back(),
              child: Text(
                "点错了，返回", 
                style: TextStyle(color: _getTextMuted(isDark), fontSize: 16)
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      isScrollControlled: true,
      enterBottomSheetDuration: const Duration(milliseconds: 250),
    );
  }

  Widget _buildActionButton({
    required String label, 
    required IconData icon, 
    required Color color, 
    required Color bg, 
    required VoidCallback onTap
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color, 
                fontSize: 16, 
                fontWeight: FontWeight.bold
              ),
            ),
          ],
        ),
      ),
    );
  }
}