// lib/controller/selectBook/selectBook.dart
import 'dart:io';
import 'package:english/dicts/reader.dart';
import 'package:english/service/app/app.dart';
import 'package:english/service/word/word.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:english/dao/word/word.dart';
import '../../util/dictionary.dart';
import '../../controller/home/home_v2.dart';
import '../../controller/main/main_controller.dart';

class SelectBookController extends GetxController {
  AppService appService = Get.find();
  var rxBookNames = <String>[].obs;
  var validWordCounts = <String, int>{}.obs;

  @override
  void onInit() {
    super.onInit();
    refreshBooks();
  }

  Future<void> refreshBooks() async {
    await appService.wordService.loadCustomBooks();
    rxBookNames.value = List.from(appService.wordService.bookNames);
    final wordDao = Get.find<WordDao>();
    final allNames = <String>[
      ...appService.wordService.systemBookNames,
      ...appService.wordService.customBookNames,
    ];
    final nextCounts = <String, int>{};

    for (final name in allNames) {
      final book = appService.wordService.bookMap[name];
      final bookId = int.tryParse(book?.id ?? '') ?? 0;
      if (bookId == 0) continue;
      nextCounts[name] = await wordDao.queryWordCount(bookId) ?? 0;
    }
    validWordCounts.assignAll(nextCounts);
  }

  get bookCount => rxBookNames.length;
  get bookNames => rxBookNames;
  get selectBookName => appService.bookName;
  get bookInfo => appService.wordService.bookInfo;
  get bookMap => appService.wordService.bookMap;

  void showBookOptions(
      BuildContext context, String bookName, bool isDark) async {
    var bookId = appService.wordService.bookMap[bookName]?.id ?? "";
    if (bookId.isEmpty) return;
    int bId = int.tryParse(bookId) ?? 0;

    var wordDao = Get.find<WordDao>();
    int progressCount = await wordDao.queryProgressWordCount(bId) ?? 0;
    final pool = await appService.loadWordPool(bookName);

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("《$bookName》配置",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 15),
              if (progressCount > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text("提示：本书已产生 $progressCount 个学习记录进度",
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 13)),
                ),
              ListTile(
                leading: Icon(Icons.sort_by_alpha,
                    color: isDark ? Colors.white : Colors.black),
                title: Text("正序背诵 (A-Z)",
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () => _confirmSetOrder(bId, 'ASC', progressCount),
              ),
              ListTile(
                leading: Icon(Icons.sort_by_alpha,
                    color: isDark ? Colors.white : Colors.black),
                title: Text("倒序背诵 (Z-A)",
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () => _confirmSetOrder(bId, 'DESC', progressCount),
              ),
              ListTile(
                leading: Icon(Icons.shuffle,
                    color: isDark ? Colors.white : Colors.black),
                title: Text("乱序背诵 (随机)",
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () => _confirmSetOrder(bId, 'RANDOM', progressCount),
              ),
              Divider(color: isDark ? Colors.white24 : Colors.black26),
              _buildPoolTile(
                bookName: bookName,
                bookId: bId,
                isDark: isDark,
                type: WordPoolType.ordinary,
                snapshot: pool,
              ),
              _buildPoolTile(
                bookName: bookName,
                bookId: bId,
                isDark: isDark,
                type: WordPoolType.familiar,
                snapshot: pool,
              ),
              _buildPoolTile(
                bookName: bookName,
                bookId: bId,
                isDark: isDark,
                type: WordPoolType.difficult,
                snapshot: pool,
              ),
              ListTile(
                leading: const Icon(Icons.search, color: Colors.blue),
                title: Text("搜索本书单词",
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  Get.back();
                  _showBookSearch(context, bookName, isDark);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_suggest, color: Colors.blue),
                title: Text("重选播放模式",
                    style:
                        TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  Get.back();
                  appService.showModeSelectionDialog(bookName, bId, context,
                      isReselect: true);
                },
              ),
              Divider(color: isDark ? Colors.white24 : Colors.black26),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.orange),
                title: const Text("清空本词书进度",
                    style: TextStyle(color: Colors.orange)),
                onTap: () => _confirmClearProgress(bId, progressCount),
              ),
              Divider(color: isDark ? Colors.white24 : Colors.black26),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title:
                    const Text("彻底删除该词库", style: TextStyle(color: Colors.red)),
                onTap: () => _confirmDeleteBook(bookName, bId, progressCount),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildPoolTile({
    required String bookName,
    required int bookId,
    required bool isDark,
    required WordPoolType type,
    required WordPoolSnapshot snapshot,
  }) {
    late final IconData icon;
    late final String subtitle;
    switch (type) {
      case WordPoolType.ordinary:
        icon = Icons.format_list_bulleted;
        subtitle = '导出时包含顽固词';
        break;
      case WordPoolType.familiar:
        icon = Icons.check_circle_outline;
        subtitle = '已退出学习与复习';
        break;
      case WordPoolType.difficult:
        icon = Icons.local_fire_department_outlined;
        subtitle = '当前词书独立记录';
        break;
    }
    return ListTile(
      leading: Icon(icon, color: Colors.teal),
      title: Text(
        type.label,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
      ),
      subtitle: Text(
        '$subtitle · ${snapshot.countFor(type)} 个',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        Get.back();
        _showWordPool(
          bookName,
          bookId,
          isDark,
          type,
          snapshot,
        );
      },
    );
  }

  void _showWordPool(
    String bookName,
    int bookId,
    bool isDark,
    WordPoolType type,
    WordPoolSnapshot snapshot,
  ) {
    final words = snapshot.wordsFor(type);
    Get.bottomSheet(
      Container(
        height: Get.height * 0.78,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${type.label} · ${words.length}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          bookName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '导出 ${type.exportLabel} TXT',
                    onPressed: words.isEmpty
                        ? null
                        : () => _exportWordPool(
                              bookName,
                              type,
                              snapshot,
                            ),
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            Expanded(
              child: words.isEmpty
                  ? const Center(
                      child: Text(
                        '当前分类暂无单词',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 30),
                      itemCount: words.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFF1F5F9),
                      ),
                      itemBuilder: (_, index) {
                        final word = words[index];
                        final meaning =
                            (word.means ?? '').replaceAll('\n', '；');
                        return ListTile(
                          title: Text(
                            word.word ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            meaning.isEmpty ? '暂无释义' : meaning,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: '单词操作',
                            onSelected: (action) => _handlePoolAction(
                              action: action,
                              word: word,
                              bookName: bookName,
                              bookId: bookId,
                              isDifficult: snapshot.isDifficult(word),
                            ),
                            itemBuilder: (_) => [
                              if (type == WordPoolType.familiar)
                                const PopupMenuItem(
                                  value: 'restore',
                                  child: Text('恢复学习'),
                                )
                              else
                                const PopupMenuItem(
                                  value: 'familiar',
                                  child: Text('设为熟词'),
                                ),
                              if (type == WordPoolType.ordinary &&
                                  !snapshot.isDifficult(word))
                                const PopupMenuItem(
                                  value: 'difficult',
                                  child: Text('设为顽固词'),
                                ),
                              if (snapshot.isDifficult(word))
                                const PopupMenuItem(
                                  value: 'remove-difficult',
                                  child: Text('移出顽固词库'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  '从本书彻底删除',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _handlePoolAction({
    required String action,
    required Word word,
    required String bookName,
    required int bookId,
    required bool isDifficult,
  }) async {
    if (action == 'delete') {
      _confirmPermanentWordDelete(word, bookName);
      return;
    }
    try {
      if (action == 'familiar') {
        final changed = await appService.markWordFamiliar(
          word.id,
          bookName: bookName,
        );
        if (!changed) return;
      } else if (action == 'restore') {
        await appService.restoreWord(word.id, bookName: bookName);
      } else if (action == 'difficult') {
        final added = await appService.wordService.addWordToDifficultBook(
          word.word ?? '',
          bookId: bookId.toString(),
        );
        if (!added) return;
      } else if (action == 'remove-difficult' && isDifficult) {
        final removed =
            await appService.wordService.removeWordFromDifficultBook(
          word.word ?? '',
          bookId: bookId.toString(),
        );
        if (!removed) return;
      } else {
        return;
      }

      if (Get.isBottomSheetOpen == true) Get.back();
      await refreshBooks();
      Get.snackbar('操作成功', '《${word.word ?? ''}》已更新');
    } catch (error) {
      Get.snackbar('操作失败', '$error');
    }
  }

  void _confirmPermanentWordDelete(Word word, String bookName) {
    Get.defaultDialog(
      title: '彻底删除单词',
      middleText: '《${word.word ?? ''}》将从《$bookName》的词源中移除，是否继续？',
      textConfirm: '彻底删除',
      textCancel: '取消',
      confirmTextColor: Colors.white,
      buttonColor: Colors.red,
      cancelTextColor: Colors.grey,
      onConfirm: () async {
        Get.back();
        try {
          final deleted = await appService.deleteWord(
            word.id,
            bookName: bookName,
          );
          if (!deleted) {
            Get.snackbar('删除失败', '未找到该单词的词源记录');
            return;
          }
          if (Get.isBottomSheetOpen == true) Get.back();
          await refreshBooks();
          Get.snackbar('删除成功', '《${word.word ?? ''}》已从本书移除');
        } catch (error) {
          Get.snackbar('删除失败', '$error');
        }
      },
    );
  }

  Future<void> _exportWordPool(
    String bookName,
    WordPoolType type,
    WordPoolSnapshot snapshot,
  ) async {
    final words = snapshot.wordsFor(type);
    if (words.isEmpty) {
      Get.snackbar('提示', '${type.exportLabel}为空');
      return;
    }

    final content = DifficultWordStore.buildTxt(words);
    final rawFileName = '${bookName}_${type.exportLabel}';
    final safeFileName =
        rawFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final fileName =
        safeFileName.isEmpty ? '词库_${type.exportLabel}' : safeFileName;

    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );
    try {
      String? outputPath;
      if (Platform.isAndroid) {
        final directory = await getExternalStorageDirectory();
        if (directory == null) throw '未获取到外部存储目录';
        outputPath = '${directory.path}/$fileName.txt';
      } else {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '导出 ${type.exportLabel}',
          fileName: '$fileName.txt',
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );
      }
      if (outputPath == null) {
        if (Get.isDialogOpen == true) Get.back();
        return;
      }
      await File(outputPath).writeAsString(content, flush: true);
      if (Get.isDialogOpen == true) Get.back();
      Get.snackbar(
        '导出成功',
        '${type.exportLabel} ${words.length} 个，已保存至：\n$outputPath',
        duration: const Duration(seconds: 6),
      );
    } catch (error) {
      if (Get.isDialogOpen == true) Get.back();
      Get.snackbar('导出失败', '$error');
    }
  }

  void _showBookSearch(BuildContext context, String bookName, bool isDark) {
    final words = appService.wordService.bookMap[bookName]?.words ?? [];
    final searchController = TextEditingController();
    final results = <Word>[].obs;
    final searchQuery = ''.obs;

    Get.bottomSheet(
      Container(
        height: Get.height * 0.75,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text("搜索《$bookName》",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: isDark ? Colors.white70 : Colors.black54),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
            ),
            // search bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: searchController,
                autofocus: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  icon: Icon(Icons.search,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF94A3B8)),
                  hintText: "输入英文单词...",
                  hintStyle: TextStyle(
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                      fontSize: 15),
                  border: InputBorder.none,
                ),
                onChanged: (q) {
                  final query = q.toLowerCase().trim();
                  searchQuery.value = query;
                  if (query.isEmpty) {
                    results.clear();
                    return;
                  }
                  final matches = words
                      .where((w) =>
                          w.word != null &&
                          w.word!.toLowerCase().contains(query))
                      .toList();
                  matches.sort((a, b) {
                    final aExact = a.word!.toLowerCase() == query;
                    final bExact = b.word!.toLowerCase() == query;
                    if (aExact && !bExact) return -1;
                    if (!aExact && bExact) return 1;
                    final aStart = a.word!.toLowerCase().startsWith(query);
                    final bStart = b.word!.toLowerCase().startsWith(query);
                    if (aStart && !bStart) return -1;
                    if (!aStart && bStart) return 1;
                    return a.word!
                        .toLowerCase()
                        .compareTo(b.word!.toLowerCase());
                  });
                  results.value = matches.take(30).toList();
                },
              ),
            ),
            const SizedBox(height: 10),
            // results
            Expanded(
              child: Obx(() {
                if (searchQuery.value.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 48,
                            color: isDark
                                ? const Color(0xFF475569)
                                : const Color(0xFFCBD5E1)),
                        const SizedBox(height: 12),
                        Text("输入单词进行搜索",
                            style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : Colors.grey,
                                fontSize: 14)),
                      ],
                    ),
                  );
                }
                if (results.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline,
                              size: 48,
                              color: isDark
                                  ? const Color(0xFF475569)
                                  : const Color(0xFFCBD5E1)),
                          const SizedBox(height: 12),
                          Text("本书没有这个词",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black)),
                          const SizedBox(height: 8),
                          Text("可前往搜索界面查询并添加到词书",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : Colors.grey,
                                  fontSize: 13)),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.search, size: 18),
                            label: const Text("去搜索界面"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF407BFF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Get.back(); // close search sheet
                              Get.back(); // back to main
                              Future.delayed(const Duration(milliseconds: 100),
                                  () {
                                if (Get.isRegistered<MainController>()) {
                                  Get.find<MainController>().changePage(1);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(top: 5, bottom: 30),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFF1F5F9),
                      indent: 20,
                      endIndent: 20),
                  itemBuilder: (_, index) {
                    final word = results[index];
                    final vo = appService.toWordVO(word);
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      title: Text(word.word ?? "",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B))),
                      subtitle: Text(
                        vo?.means?.join("；") ?? "",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            fontSize: 13),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _confirmSetOrder(int bookId, String order, int count) {
    if (count > 0) {
      Get.defaultDialog(
          title: "重置进度提醒",
          middleText: "重新选择背诵顺序将会重置该词书目前的 $count 个学习进度，从头开始，是否继续？",
          textConfirm: "确定重置",
          textCancel: "取消",
          confirmTextColor: Colors.white,
          buttonColor: Colors.orange,
          cancelTextColor: Colors.grey,
          onConfirm: () async {
            Get.back();
            await Get.find<WordDao>().clearBookProgress(bookId);
            _setOrderAndClose(bookId.toString(), order);
          });
    } else {
      _setOrderAndClose(bookId.toString(), order);
    }
  }

  void _setOrderAndClose(String bookId, String order) async {
    GetStorage().write('book_order_$bookId', order);
    // 清空所有游标，确保新顺序从头开始
    GetStorage().write('study_cursor_$bookId', '');
    GetStorage().write('study_cursor_desc_$bookId', '');
    GetStorage().remove('study_cursor_manual_$bookId');
    GetStorage().remove('study_cursor_manual_${bookId}_new');
    GetStorage().write('study_cursor_manual_${bookId}_new_initialized', true);
    GetStorage().remove('saved_queue_${bookId}_new');
    GetStorage().remove('saved_queue_pos_${bookId}_new');
    // 清空复习相关状态，避免旧复习批次干扰新顺序
    GetStorage().remove('review_date_$bookId');
    GetStorage().remove('review_round_done_$bookId');
    GetStorage().remove('review_batch_$bookId');
    GetStorage().remove('review_batch_pos_$bookId');
    GetStorage().remove('review_batch_selected_$bookId');
    GetStorage().remove('review_queue_$bookId');
    GetStorage().remove('review_passed_$bookId');
    GetStorage().remove('review_target_$bookId');
    GetStorage().remove('review_cycles_$bookId');
    await appService.clearReviewState(
      int.tryParse(bookId) ?? 0,
      clearStats: true,
      clearPreferences: true,
    );
    Get.back();
    if (Get.isRegistered<HomeControllerV2>()) {
      Get.find<HomeControllerV2>().fetchInfo();
    }
    Get.snackbar("设置成功", "该词书将按所选顺序从头开始背诵");
  }

  void _confirmClearProgress(int bookId, int count) {
    if (count == 0) {
      Get.snackbar("提示", "当前并没有相关学习进度哦");
      return;
    }
    Get.defaultDialog(
        title: "危险警告",
        middleText: "确定要清空这 $count 个单词的学习进度吗？清空后将从头开始。（熟词记录不会被清除）",
        textConfirm: "清空",
        textCancel: "取消",
        confirmTextColor: Colors.white,
        buttonColor: Colors.orange,
        cancelTextColor: Colors.grey,
        onConfirm: () async {
          var storage = GetStorage();
          await Get.find<WordDao>().clearBookProgress(bookId);
          // 清空所有游标
          storage.remove('study_cursor_$bookId');
          storage.remove('study_cursor_desc_$bookId');
          storage.remove('study_cursor_manual_$bookId');
          storage.remove('study_cursor_manual_${bookId}_new');
          storage.write('study_cursor_manual_${bookId}_new_initialized', true);
          storage.remove('saved_queue_${bookId}_new');
          storage.remove('saved_queue_pos_${bookId}_new');
          // 清空复习相关状态
          storage.remove('review_date_$bookId');
          storage.remove('review_round_done_$bookId');
          storage.remove('review_batch_$bookId');
          storage.remove('review_batch_pos_$bookId');
          storage.remove('review_batch_selected_$bookId');
          storage.remove('review_queue_$bookId');
          storage.remove('review_passed_$bookId');
          storage.remove('review_target_$bookId');
          storage.remove('review_cycles_$bookId');
          await appService.clearReviewState(
            bookId,
            clearStats: true,
            clearPreferences: true,
          );
          // 清空学习顺序偏好（重置为默认）
          storage.remove('book_order_$bookId');
          Get.back();
          Get.back();
          if (Get.isRegistered<HomeControllerV2>())
            Get.find<HomeControllerV2>().fetchInfo();
          Get.snackbar("成功", "进度已重置清空，熟词保留");
        });
  }

  void _confirmDeleteBook(String bookName, int bookId, int count) {
    String warning =
        count > 0 ? "该书有 $count 个学习进度记录，删除将永久丢失这些进度！" : "确定要删除这本自定义词库吗？";
    Get.defaultDialog(
        title: "不可逆删除",
        middleText: warning,
        textConfirm: "强行删除",
        textCancel: "取消",
        confirmTextColor: Colors.white,
        buttonColor: Colors.red,
        cancelTextColor: Colors.grey,
        onConfirm: () async {
          Get.dialog(const Center(child: CircularProgressIndicator()),
              barrierDismissible: false);
          try {
            await appService.deleteCustomBook(bookName, bookId);
            await refreshBooks();

            if (appService.bookName == bookName) {
              appService.selectBook(appService.wordService.bookNames.first);
            }

            Get.back(); // close loading
            Get.back(); // close confirmation dialog
            Get.back(); // close book-options bottom sheet
            if (Get.isRegistered<HomeControllerV2>()) {
              Get.find<HomeControllerV2>().fetchInfo();
            }
            Get.snackbar("成功", "《$bookName》已被彻底抹除");
          } catch (error) {
            Get.back();
            Get.snackbar("删除失败", "$error");
          }
        });
  }

  Future<void> createCustomBook(String bookName, String rawText) async {
    if (bookName.trim().isEmpty) {
      Get.snackbar("提示", "书名不能为空！");
      return;
    }

    // 1. 先进行初步处理：拆分、去空格、转小写、过滤空行
    // 只取左边第一列（支持 tab、逗号分隔的多列格式）
    var rawList = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.split(RegExp(r'[\t,]'))[0].trim().toLowerCase())
        .where((e) => e.isNotEmpty && RegExp(r'[a-z]').hasMatch(e));

    // 2. 使用 Set 强制去重，并转换成 List
    List<String> spells = rawList.toSet().toList();

    // 3. 显式调用排序（不要用 .. 级联符，这样最稳妥）
    spells.sort();

    if (spells.isEmpty) {
      Get.snackbar("提示", "单词列表为空，或者格式不正确！");
      return;
    }

    Get.dialog(const Center(child: CircularProgressPath()),
        barrierDismissible: false);

    int fetched = 0;
    for (var spell in spells) {
      if (appService.getWordBySpell(spell) == null) {
        final word = await fetchWordDefinition(spell);
        if (word != null) {
          appService.wordService.mergeFetchedWord(word);
          fetched++;
        }
      }
    }
    await appService.replaceCustomBookWords(bookName.trim(), spells);

    refreshBooks();

    Get.back(); // 关闭 loading
    Get.back(); // 关闭弹窗
    Get.snackbar(
        "成功",
        "《$bookName》已创建，共 ${spells.length} 个单词" +
            (fetched > 0 ? "（从网络获取 $fetched 个释义）" : ""));
  }

  Future<String?> pickTxtFile() async {
    FilePickerResult? result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      return await file.readAsString();
    }
    return null;
  }
}

class CircularProgressPath extends StatelessWidget {
  const CircularProgressPath({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return const Card(
        child: Padding(
            padding: EdgeInsets.all(20.0), child: CircularProgressIndicator()));
  }
}
