// lib/view/profile/profile_page.dart
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controller/profile/profile_controller.dart';

class ProfilePage extends GetView<ProfileController> {
  const ProfilePage({Key? key}) : super(key: key);

  // ---------------- 动态色彩映射（CSS 变量深度适配） ----------------
  Color get bgColor => controller.isDarkMode.value ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get cardBg => controller.isDarkMode.value ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);
  Color get textMain => controller.isDarkMode.value ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  Color get textMuted => controller.isDarkMode.value ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get borderColor => controller.isDarkMode.value ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
  Color get primaryColor => controller.isDarkMode.value ? const Color(0xFF818CF8) : const Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
      backgroundColor: bgColor,
      body: SingleChildScrollView(
        // 彻底移除滑动回弹效果，原生手感
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 用户资料头部（头像、昵称、打卡天数、格言）
            _buildHeader(),
            
            // 已经彻底删除 [累计词汇] 和 [今日完成度] 卡片区
            
            // 2. 个人资料设置组
            _buildSectionLabel("个人资料设置"),
            _buildSettingsGroup([
              _buildSettingItem(
                icon: Icons.camera_alt_rounded, 
                iconColor: const Color(0xFF6366F1), 
                iconBg: const Color(0xFFEEF2FF),
                title: "更换头像", 
                trailing: Icon(Icons.chevron_right, size: 16, color: textMuted), 
                onTap: controller.changeAvatar,
              ),
              _buildSettingItem(
                icon: Icons.local_offer_rounded, 
                iconColor: const Color(0xFFF59E0B), 
                iconBg: const Color(0xFFFFF7ED),
                title: "修改昵称", 
                trailing: Icon(Icons.chevron_right, size: 16, color: textMuted), 
                onTap: () => controller.editProfile('name'),
              ),
              _buildSettingItem(
                icon: Icons.format_quote_rounded, 
                iconColor: const Color(0xFF10B981), 
                iconBg: const Color(0xFFF0FDF4),
                title: "编辑个性格言", 
                trailing: Icon(Icons.chevron_right, size: 16, color: textMuted), 
                onTap: () => controller.editProfile('motto'),
              ),
            ]),

            // 3. 偏好设置组
            _buildSectionLabel("偏好设置"),
            _buildSettingsGroup([
              _buildSettingItem(
                icon: Icons.nightlight_round, 
                iconColor: const Color(0xFF6366F1), 
                iconBg: const Color(0xFFEEF2FF),
                title: "黑暗模式", 
                trailing: CupertinoSwitch(
                  value: controller.isDarkMode.value, 
                  activeColor: primaryColor, 
                  onChanged: controller.toggleDarkMode
                ),
              ),
              _buildSettingItem(
                icon: Icons.notifications_active, 
                iconColor: const Color(0xFFF59E0B), 
                iconBg: const Color(0xFFFFF7ED),
                title: "学习提醒",
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => controller.selectReminderTime(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: controller.isDarkMode.value ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: Text(
                          controller.reminderTime.value, 
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor)
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    CupertinoSwitch(
                      value: controller.reminderEnabled.value, 
                      activeColor: const Color(0xFFF59E0B), 
                      onChanged: controller.toggleReminder
                    ),
                  ],
                ),
              ),
              _buildSettingItem(
                icon: Icons.volume_up_rounded, 
                iconColor: const Color(0xFF10B981), 
                iconBg: const Color(0xFFF0FDF4),
                title: "自动播放发音", 
                trailing: CupertinoSwitch(
                  value: controller.autoPlayVoice.value, 
                  activeColor: const Color(0xFF10B981), 
                  onChanged: controller.toggleAutoPlay
                ),
              ),
            ]),

            // 4. 数据管理组
            _buildSectionLabel("数据管理"),
            _buildSettingsGroup([
              _buildSettingItem(
                icon: Icons.file_download_rounded, 
                iconColor: const Color(0xFF475569), 
                iconBg: const Color(0xFFF1F5F9),
                title: "自主导出词库 (TXT)", 
                trailing: Icon(Icons.download_rounded, size: 20, color: textMuted), 
                onTap: controller.showExportDialog,
              ),
              _buildSettingItem(
                icon: Icons.delete_forever_rounded, 
                iconColor: const Color(0xFFEF4444), 
                iconBg: const Color(0xFFFEF2F2),
                title: "清除学习记录", 
                titleColor: const Color(0xFFEF4444), 
                onTap: controller.clearStudyRecords,
              ),
            ]),

            // 5. 关于项目
            _buildSectionLabel("关于项目"),
            _buildSettingsGroup([
              _buildSettingItem(
                icon: Icons.code_rounded, 
                iconColor: const Color(0xFF64748B), 
                iconBg: const Color(0xFFF8FAFC),
                title: "版本信息",
                trailing: Text("v1.5.0 (Stable)", style: TextStyle(fontSize: 13, color: textMuted)),
                onTap: () => controller.onVersionClick(),
              ),
              _buildSettingItem(
                // --- 100% 还原 GitHub 章鱼猫图标 ---
                customIcon: Container(
                  width: 36, height: 36,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: controller.isDarkMode.value ? Colors.white10 : const Color(0xFFF1F5F9), 
                    borderRadius: BorderRadius.circular(11)
                  ),
                  child: Image.network(
                    'https://cdn-icons-png.flaticon.com/512/25/25231.png',
                    color: controller.isDarkMode.value ? Colors.white : Colors.black,
                  ),
                ),
                title: "开源仓库 (GitHub)",
                trailing: Icon(Icons.open_in_new_rounded, size: 16, color: textMuted),
                onTap: () async {
                  const url = 'https://github.com/Heking114514/Wordie';
                  if (!await launch(url)) {
                    Get.snackbar("错误", "无法打开链接");
                  }
                }
              ),
            ]),

            const SizedBox(height: 30),
            Center(
              child: Text(
                "Made with ❤️ for Personal Learning", 
                style: TextStyle(fontSize: 12, color: textMuted, letterSpacing: 0.5)
              )
            ),
          ],
        ),
      ),
    ));
  }

  // ---------------- 内部组件构建函数 ----------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 80, bottom: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          // 头像
          GestureDetector(
            onTap: controller.changeAvatar,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primaryColor, const Color(0xFFA855F7)]),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: controller.avatarPath.value.isNotEmpty
                    ? Image.file(File(controller.avatarPath.value), fit: BoxFit.cover)
                    : const Icon(Icons.face_retouching_natural, size: 45, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 昵称
          GestureDetector(
            onTap: () => controller.editProfile('name'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(controller.username.value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textMain)),
                const SizedBox(width: 8),
                Icon(Icons.edit_note_rounded, size: 20, color: textMuted),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 格言
          GestureDetector(
            onTap: () => controller.editProfile('motto'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                controller.motto.value.isEmpty ? "请留下你的格言吧 ✎" : "“${controller.motto.value}”",
                style: TextStyle(fontSize: 14, color: textMuted, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 25, top: 20, bottom: 12),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted, letterSpacing: 1.2))
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)]
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingItem({
    IconData? icon, 
    Color? iconColor, 
    Color? iconBg, 
    Widget? customIcon, 
    required String title, 
    Color? titleColor, 
    Widget? trailing, 
    VoidCallback? onTap
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor, width: 0.8))),
        child: Row(
          children: [
            customIcon ?? Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 15),
            Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: titleColor ?? textMain))),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}