// lib/controller/profile/profile_controller.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../../dao/word/word.dart';
import '../../service/app/app.dart';
import '../home/home_v2.dart';

class ProfileController extends GetxController {
  final AppService appService = Get.find();
  final WordDao wordDao = Get.find<WordDao>();
  final GetStorage storage = GetStorage();

  // --- 用户资料状态 ---
  var username = "学习者 001".obs;
  var motto = "".obs;
  var avatarPath = "".obs;
  var streakDays = 0.obs;

  // --- 统计与偏好状态 ---
  var totalLearned = 0.obs;
  var todayCompletionRate = "0%".obs;
  var isDarkMode = false.obs;
  var autoPlayVoice = true.obs;

  // --- 学习提醒状态 ---
  var reminderEnabled = false.obs;
  var reminderTime = "20:00".obs;

  int _versionClickCount = 0;

  @override
  void onInit() {
    super.onInit();
    _loadPreferences();
    fetchProfileData();
  }

  void _loadPreferences() {
    username.value = storage.read('profile_name') ?? "学习者 001";
    motto.value = storage.read('profile_motto') ?? "";
    avatarPath.value = storage.read('profile_avatar') ?? "";
    
    isDarkMode.value = storage.read('dark_mode') ?? false;
    autoPlayVoice.value = storage.read('auto_play') ?? true;
    appService.autoPlayVoice = autoPlayVoice.value;
    
    reminderEnabled.value = storage.read('reminder_enabled') ?? false;
    reminderTime.value = storage.read('reminder_time') ?? "20:00";
  }

  void fetchProfileData() async {
    _calculateStreakDays();

    // 累计词汇
    var learnedCount = await wordDao.queryAdapter.query(
      'SELECT count(0) as count FROM word_status WHERE status=1 OR studyCycle>0',
      mapper: (Map<String, Object?> row) => row['count'] as int?,
    );
    totalLearned.value = learnedCount ?? 0;

    // 今日完成度
    var allCount = await wordDao.queryWordCount(appService.bookId) ?? 0;
    var progressCount = await wordDao.queryProgressWordCount(appService.bookId) ?? 0;
    double rate = allCount > 0 ? progressCount / allCount : 0.0;
    if (rate > 1.0) rate = 1.0;
    todayCompletionRate.value = "${(rate * 100).toInt()}%";
  }

  void _calculateStreakDays() async {
    var records = await wordDao.queryAllStudyTimeRecords();
    if (records.isEmpty) { streakDays.value = 0; return; }
    Map<String, int> dailyTime = {};
    for (var r in records) {
      if (r.startTime != null && r.endTime != null) {
        var date = DateTime.fromMillisecondsSinceEpoch(r.startTime!);
        String key = "${date.year}-${date.month}-${date.day}";
        dailyTime[key] = (dailyTime[key] ?? 0) + (r.endTime! - r.startTime!);
      }
    }
    int streak = 0;
    DateTime check = DateTime.now();
    if ((dailyTime["${check.year}-${check.month}-${check.day}"] ?? 0) >= 600000) streak++;
    check = check.subtract(const Duration(days: 1));
    while ((dailyTime["${check.year}-${check.month}-${check.day}"] ?? 0) >= 600000) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    streakDays.value = streak;
  }

  // ==== 个人资料修改 ====
  Future<void> changeAvatar() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      avatarPath.value = result.files.single.path!;
      storage.write('profile_avatar', avatarPath.value);
    }
  }

  void editProfile(String type) {
    bool isName = type == 'name';
    TextEditingController textCtrl = TextEditingController(text: isName ? username.value : motto.value);
    
    Get.defaultDialog(
      title: isName ? "修改昵称" : "编辑格言",
      titleStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      content: TextField(
        controller: textCtrl, 
        decoration: InputDecoration(
          hintText: isName ? "请输入新昵称" : "留下你的学习格言...",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
        )
      ),
      textConfirm: "保存", 
      textCancel: "取消", 
      confirmTextColor: Colors.white, 
      buttonColor: const Color(0xFF6366F1),
      cancelTextColor: const Color(0xFF64748B),
      onConfirm: () {
        if (isName) { 
          username.value = textCtrl.text; 
          storage.write('profile_name', username.value); 
          // 强制刷新主页数据
          if (Get.isRegistered<HomeControllerV2>()) Get.find<HomeControllerV2>().fetchInfo();
        } else { 
          motto.value = textCtrl.text; 
          storage.write('profile_motto', motto.value); 
        }
        Get.back();
      }
    );
  }

  void onVersionClick() {
    _versionClickCount++;
    if (_versionClickCount >= 3) {
      _versionClickCount = 0;
      bool isDark = isDarkMode.value;
      Color primary = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
      Color bg = isDark ? const Color(0xFF1E293B) : Colors.white;
      Color text = isDark ? Colors.white : const Color(0xFF1E293B);
      Color muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

      Get.dialog(
        Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [primary, const Color(0xFFA855F7)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.code_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 16),
                Text("关于作者", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: text)),
                const SizedBox(height: 20),
                _buildInfoRow(Icons.person_rounded, "Heking", primary, text, muted),
                _buildInfoRow(Icons.wechat, "he-55782", primary, text, muted),
                _buildInfoRow(Icons.alternate_email, "3395695038@qq.com", primary, text, muted),
                _buildInfoRow(Icons.chat, "3395695038", primary, text, muted),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Get.back(),
                    child: const Text("我知道了", style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildInfoRow(IconData icon, String value, Color primary, Color text, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primary, size: 20),
          ),
          const SizedBox(width: 14),
          Text(value, style: TextStyle(fontSize: 15, color: text, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ==== 偏好设置开关 ====
  void toggleDarkMode(bool value) {
    isDarkMode.value = value;
    storage.write('dark_mode', value);
    Get.changeThemeMode(value ? ThemeMode.dark : ThemeMode.light);
  }

  void toggleAutoPlay(bool value) {
    autoPlayVoice.value = value;
    storage.write('auto_play', value);
    appService.autoPlayVoice = value; 
  }

  // ==== 学习提醒功能 ====
  void toggleReminder(bool value) {
    reminderEnabled.value = value;
    storage.write('reminder_enabled', value);
    if (value) {
      _writeToSystemCalendar();
    } else {
      _removeFromSystemCalendar();
    }
  }

  Future<void> selectReminderTime(BuildContext context) async {
    List<String> parts = reminderTime.value.split(":");
    TimeOfDay initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      String formattedTime = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      reminderTime.value = formattedTime;
      storage.write('reminder_time', formattedTime);
      if (reminderEnabled.value) {
        _writeToSystemCalendar();
      }
    }
  }

  void _writeToSystemCalendar() async {
    const channel = MethodChannel('com.example.english/calendar');
    try {
      final String? eventId = await channel.invokeMethod('addEvent', {
        'title': 'Wordie 学习提醒',
        'description': '坚持，自见曙光！快来完成今天的单词任务吧。',
        'time': reminderTime.value,
        'days': 3650,
        'count': 3650,
        'repeat': true,
        'rrule': 'FREQ=DAILY',
      });
      if (eventId != null) {
        storage.write('calendar_event_id', eventId);
        Get.snackbar("设置成功", "已静默授权并写入系统日历");
      }
    } catch (e) {
      Get.snackbar("提醒失败", "日历权限被拒绝或操作异常");
      reminderEnabled.value = false;
      storage.write('reminder_enabled', false);
    }
  }

  void _removeFromSystemCalendar() async {
    final String? eventId = storage.read('calendar_event_id');
    if (eventId == null) return;
    const channel = MethodChannel('com.example.english/calendar');
    try {
      await channel.invokeMethod('removeEvent', {'eventId': eventId});
      storage.remove('calendar_event_id');
      Get.snackbar("已关闭", "已自动擦除系统日历中的提醒");
    } catch (e) {
      Get.snackbar("提示", "关闭失败");
    }
  }

  // ==== 高级自选目录导出 ====
  void showExportDialog() {
    List<String> allBooks =[...appService.wordService.systemBookNames, ...appService.wordService.customBookNames];
    if (allBooks.isEmpty) {
      Get.snackbar("提示", "暂无可导出的词书");
      return;
    }
    
    var selectedBook = appService.bookName.obs;
    if (!allBooks.contains(selectedBook.value)) selectedBook.value = allBooks.first;
    TextEditingController fileNameCtrl = TextEditingController(text: "${selectedBook.value}_导出");

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(color: isDarkMode.value ? const Color(0xFF1E293B) : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Text("自主导出词库", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkMode.value ? Colors.white : Colors.black)),
            const SizedBox(height: 20),
            Obx(() => DropdownButton<String>(
              isExpanded: true, value: selectedBook.value,
              dropdownColor: isDarkMode.value ? const Color(0xFF1E293B) : Colors.white,
              style: TextStyle(color: isDarkMode.value ? Colors.white : Colors.black, fontSize: 16),
              items: allBooks.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
              onChanged: (v) { if (v != null) { selectedBook.value = v; fileNameCtrl.text = "${v}_导出"; } },
            )),
            const SizedBox(height: 15),
            TextField(
              controller: fileNameCtrl,
              style: TextStyle(color: isDarkMode.value ? Colors.white : Colors.black),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDarkMode.value ? const Color(0xFF0F172A) : Colors.grey.shade100,
                hintText: "请输入导出文件名",
                suffixText: ".txt",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_as, color: Colors.white),
                label: const Text("确认导出", style: TextStyle(fontSize: 16, color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => _executeExport(selectedBook.value, fileNameCtrl.text),
              ),
            )
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _executeExport(String bookName, String fileName) async {
    Get.back();

    try {
      var book = appService.wordService.bookMap[bookName];
      if (book == null || book.words == null || book.words!.isEmpty) throw "词书为空";

      StringBuffer buffer = StringBuffer();
      for (var w in book.words!) {
        String means = w.means?.replaceAll('\n', ' ') ?? '暂无释义';
        buffer.writeln("${w.word}\t$means");
      }

      String safeFileName = fileName.isEmpty ? "词库" : fileName;
      Get.dialog(const Center(child: CircularProgressIndicator()), barrierDismissible: false);

      if (Platform.isAndroid) {
        Directory? appDir = await getExternalStorageDirectory();
        if (appDir == null) throw "无法获取系统外部存储目录";
        String finalPath = '${appDir.path}/$safeFileName.txt';
        await File(finalPath).writeAsString(buffer.toString());

        Get.back();
        Get.snackbar(
          "导出成功 (免权限)",
          "文件已成功导出至安全目录：\n$finalPath\n您可以去文件管理器查看此文件。",
          duration: const Duration(seconds: 8),
        );
      } else {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '请选择保存位置',
          fileName: '$safeFileName.txt',
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );

        if (outputFile != null) {
          await File(outputFile).writeAsString(buffer.toString());
          Get.back();
          Get.snackbar("导出成功", "文件已成功保存至：\n$outputFile");
        } else {
          Get.back();
        }
      }
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      Get.snackbar("导出出错", "详情：$e", duration: const Duration(seconds: 4));
    }
  }

  // ==== 修复：清除学习记录时顺带清除时长记录 ====
  void clearStudyRecords() {
    Get.defaultDialog(
      title: "危险操作",
      middleText: "清除所有词书学习进度与打卡学习时长，不可恢复！确定吗？",
      textConfirm: "确认清除",
      textCancel: "取消",
      confirmTextColor: Colors.white,
      buttonColor: Colors.redAccent,
      cancelTextColor: const Color(0xFF64748B),
      onConfirm: () async {
        Get.back();
        // 清理进度表
        await wordDao.queryAdapter.queryNoReturn('DELETE FROM word_status');
        // 清理总学习时长表
        await wordDao.queryAdapter.queryNoReturn('DELETE FROM study_time_count');
        // 清理单词个体学习时长表
        await wordDao.queryAdapter.queryNoReturn('DELETE FROM word_study_time_count');
        
        // 重置前端绑定的显示数据
        streakDays.value = 0;
        totalLearned.value = 0;
        todayCompletionRate.value = "0%";
        
        // 通知主页同步刷新
        if (Get.isRegistered<HomeControllerV2>()) Get.find<HomeControllerV2>().fetchInfo();

        fetchProfileData(); 
        Get.snackbar("清除成功", "所有学习记录与打卡时间已彻底清空");
      }
    );
  }
}