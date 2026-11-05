import 'dart:async';
import 'dart:math' as math;
import 'package:bottom_picker/bottom_picker.dart';
import 'package:bottom_picker/resources/arrays.dart';
import 'package:bottom_sheet/bottom_sheet.dart';
import 'package:english/controller/study/wordList.dart';
import 'package:english/dicts/reader.dart';
import 'package:english/entity/word/vo/word.dart';
import 'package:english/service/ai/openai_responses.dart';
import 'package:english/service/app/app.dart';
import 'package:english/service/word/word.dart';
import 'package:english/util/audio.dart';
import 'package:english/util/dictionary.dart';
import 'package:english/view/review/list.dart';
import 'package:english/widget/rotate_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
// import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:sliding_sheet/sliding_sheet.dart';

import '../../controller/study/study.dart';
import '../../controller/home/home_v2.dart';
import '../../controller/statistic/statistic.dart';
import '../../util/theme.dart';
import '../word/word.dart';

class StudyPage extends GetView<StudyController> {
  void showReviewCountPicker(BuildContext context) {
    // 这里可以复用已有的 BottomPicker 逻辑
    // 简单示例：
    Get.bottomSheet(
      Container(
        color: Colors.white,
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [10, 20, 50, 100]
              .map((count) => ListTile(
                    title: Text("$count 个"),
                    onTap: () {
                      controller.reviewDailyCount.value = count;
                      Get.back();
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildOptionTile(String title, String value) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 16)),
          Row(
            children: [
              Text(value, style: TextStyle(color: Colors.grey)),
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (controller.isDifficultMode.value) {
          controller.exitDifficultMode();
          return false;
        }
        if (Get.isRegistered<HomeControllerV2>())
          Get.find<HomeControllerV2>().fetchInfo();
        if (Get.isRegistered<StatisticController>())
          Get.find<StatisticController>().fetchStats();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            onPressed: () {
              if (controller.isDifficultMode.value) {
                controller.exitDifficultMode();
              } else {
                if (Get.isRegistered<HomeControllerV2>())
                  Get.find<HomeControllerV2>().fetchInfo();
                if (Get.isRegistered<StatisticController>())
                  Get.find<StatisticController>().fetchStats();
                Get.back();
              }
            },
            icon: const Icon(Icons.arrow_back_ios),
          ),
          title: Obx(() => Text(
                controller.isDifficultMode.value ? "🔥 攻克顽固词汇" : "学习",
                style: const TextStyle(fontSize: 20),
              )),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Obx(() {
            if (controller.isInitializing.value) {
              return const Center(child: CircularProgressIndicator());
            }
            return controller.word.value == null
                ? buildEndView(context)
                : buildWordView(context);
          }),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor, // 跟随主题
              boxShadow: [
                BoxShadow(blurRadius: 1, color: Colors.grey.withOpacity(0.1))
              ]),
          child: SafeArea(
            child: Container(
              height: 60,
              child: Obx(() {
                return Stack(
                  children: [
                    if (controller.word.value != null)
                      Container(
                        alignment: Alignment.center,
                        child: Row(
                          // mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: InkWell(
                                  onTap: () {
                                    controller.previous();
                                  },
                                  child: Container(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.fast_rewind_rounded,
                                      size: 32,
                                      color: Colors.black87,
                                    ),
                                  )),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: InkWell(
                                  onTap:
                                      controller.playButtonEnable.value == false
                                          ? null
                                          : () {
                                              controller.togglePlay();
                                            },
                                  child: Container(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(
                                      controller.playing.value
                                          ? Icons.pause_outlined
                                          : Icons.play_arrow_rounded,
                                      size: 32,
                                      color: Colors.black87,
                                    ),
                                  )),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: InkWell(
                                  onTap: () {
                                    //下一个
                                    controller.next();
                                  },
                                  child: Container(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.fast_forward_rounded,
                                      size: 28,
                                      color: Colors.black87,
                                    ),
                                  )),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (controller.isDifficultMode.value)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
                              child: IconButton(
                                onPressed: () => controller.exitDifficultMode(),
                                icon:
                                    const Icon(Icons.logout_rounded, size: 28),
                                color: Colors.redAccent,
                                tooltip: "退出顽固词汇",
                              ),
                            ),
                          if (controller.isManualMode.value &&
                              !controller.isDifficultMode.value)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
                              child: IconButton(
                                onPressed: () => controller.openDifficultBook(),
                                icon:
                                    const Icon(Icons.import_contacts, size: 28),
                                color: Colors.teal,
                                tooltip: "顽固词汇",
                              ),
                            ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4.0),
                            child: controller.isManualMode.value &&
                                    Get.parameters['mode'] == 'review'
                                // ==== 复习模式下展示 AI 大脑按钮 ====
                                ? IconButton(
                                    onPressed: () {
                                      final settings = AiSettings.fromStorage();
                                      if (!settings.isConfigured) {
                                        Get.snackbar(
                                            "提示", '请先在「我的」中配置 AI 站点、模型和 Key');
                                      } else {
                                        _showArticleBottomSheet(context);
                                      }
                                    },
                                    icon: const Icon(Icons.auto_awesome,
                                        size: 30, color: Colors.purpleAccent),
                                    tooltip: "AI 复习串记",
                                  )
                                // ==== 主线学习模式保持原有的旗帜/计时器图标 ====
                                : IconButton(
                                    onPressed: controller.isManualMode.value
                                        ? () =>
                                            controller.jumpToLearningPosition()
                                        : () => showOptions(context),
                                    icon: Icon(
                                      controller.isManualMode.value
                                          ? Icons.flag_rounded
                                          : Icons.av_timer,
                                      size: 28,
                                      color: controller.isManualMode.value
                                          ? Colors.blueAccent
                                          : null,
                                    ),
                                    tooltip: controller.isManualMode.value
                                        ? "跳转到学习位置"
                                        : null,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4.0),
                            child: IconButton(
                              onPressed: () => showWordListBottomSheet(context),
                              icon: const Icon(Icons.list, size: 28),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildWordContent(BuildContext context) {
    return Stack(
      children: [
        if (controller.autoRotating)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.only(bottom: 30),
              width: 300,
              height: 300,
              child: Image.asset("assets/img/chicken.png"),
            ),
          ),
        SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: controller.autoRotating ? 30 : 10,
              vertical: controller.autoRotating ? 30 : 10,
            ),
            child: Obx(() {
              return WordView(
                word: controller.word.value,
                showDetail:
                    controller.autoRotating || !controller.thinking.value,
                cycle: controller.wordStatus.value?.studyCycle ?? 0,
                hideDetails: controller.isManualMode.value &&
                    !controller.isRevealed.value,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget buildWordView(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (controller.isManualMode.value &&
                  !controller.isRevealed.value) {
                controller.manualReveal();
              }
            },
            onDoubleTap: () {
              controller.next();
            },
          ),
        ),
        if (controller.autoRotating)
          RotatingWidget(
            controller: RotatingWidgetsController(
              autoplayEnabled: controller.autoRotating,
            ),
            rotateZ: false,
            rotateX: false,
            rotateY: true,
            duration: const Duration(milliseconds: 5),
            child: buildWordContent(context),
          ),
        if (!controller.autoRotating) buildWordContent(context),

        if (controller.autoPass.value == false)
          Align(
            alignment: Alignment.bottomCenter,
            child: Obx(() {
              if (!controller.isManualMode.value &&
                  (controller.thinking.value == true ||
                      controller.playing.value == false)) {
                return const SizedBox();
              }
              if (controller.isManualMode.value &&
                  !controller.isRevealed.value) {
                return const SizedBox();
              }

              return _PassButton(isDark: isDark);
            }),
          ),

        if (controller.autoRotating == false)
          Align(
            alignment: Alignment.topRight,
            child: Obx(() {
              if (controller.isManualMode.value && !controller.isRevealed.value)
                return const SizedBox();

              return Container(
                  margin: const EdgeInsets.only(top: 20, right: 20),
                  width: 36,
                  height: 36,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                            blurStyle: BlurStyle.outer,
                            blurRadius: 10,
                            color: isDark
                                ? Colors.red.withOpacity(0.4)
                                : Colors.red.withOpacity(0.2)),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(100),
                      onTap: controller.controlEnable.value &&
                              controller.thinking.value == false
                          ? () => controller.delete()
                          : null,
                      child: Container(
                        alignment: Alignment.center,
                        child: const Icon(Icons.delete_outline_rounded,
                            color: Colors.red, size: 24),
                      ),
                    ),
                  ));
            }),
          ),

        Align(
          alignment: Alignment.bottomLeft,
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Obx(() {
              // 强制绑定依赖：只要 word.value（切词时）改变，Obx就会触发刷新，修复 improper use 异常
              final _ = controller.word.value;

              if (Get.parameters['mode'] == 'review') {
                int uniqueCount =
                    controller.playingWords.map((e) => e.wordId).toSet().length;
                int m = controller.playingWords.length;
                int n = controller.playingIndex + 1;
                int round = (controller.playingIndex ~/
                        (uniqueCount > 0 ? uniqueCount : 1)) +
                    1;
                // 改用 Wrap 代替 Row，修复文字超长导致的 RenderFlex overflow 溢出崩溃
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("今日复习: $uniqueCount  ",
                        style: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.withOpacity(0.8),
                            fontSize: 12)),
                    Text("第$round轮  ",
                        style: TextStyle(
                            color: isDark ? Colors.orangeAccent : Colors.orange,
                            fontSize: 12)),
                    Text("进度: $n/$m",
                        style: TextStyle(
                            color: isDark ? Colors.greenAccent : Colors.green,
                            fontSize: 12)),
                  ],
                );
              } else if (controller.isDifficultMode.value) {
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("🔥 顽固词汇: ",
                        style: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.withOpacity(0.8),
                            fontSize: 12)),
                    Text("${controller.playingWords.length}",
                        style: TextStyle(
                            color: isDark
                                ? Colors.greenAccent.withOpacity(0.8)
                                : Colors.green.withOpacity(0.8),
                            fontSize: 12)),
                  ],
                );
              } else {
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("已学习: ",
                        style: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.withOpacity(0.8),
                            fontSize: 12)),
                    Text("${controller.bookLearnedCount.value}  ",
                        style: TextStyle(
                            color: isDark
                                ? Colors.greenAccent.withOpacity(0.8)
                                : Colors.green.withOpacity(0.8),
                            fontSize: 12)),
                    Text("本书词汇: ",
                        style: TextStyle(
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.withOpacity(0.8),
                            fontSize: 12)),
                    Text("${controller.bookTotalCount.value}",
                        style: TextStyle(
                            color: isDark
                                ? Colors.redAccent.shade100
                                : Colors.redAccent.withOpacity(0.8),
                            fontSize: 12)),
                    if (controller.isManualMode.value)
                      Text(
                          "  位置: ${controller.playingIndex + 1}/${controller.playingWords.length}",
                          style: TextStyle(
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.withOpacity(0.6),
                              fontSize: 12)),
                  ],
                );
              }
            }),
          ),
        ),

        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("时长: ",
                    style: TextStyle(
                        color: isDark
                            ? Colors.white54
                            : Colors.grey.withOpacity(0.8),
                        fontSize: 12)),
                Obx(() => Text("${controller.studyTime.value}",
                    style: TextStyle(
                        color: isDark
                            ? Colors.white54
                            : Colors.grey.withOpacity(0.8),
                        fontSize: 12))),
              ],
            ),
          ),
        ),

        // 复习轮次过渡提示（全屏遮挡500ms）
        Obx(() {
          if (controller.reviewRoundInfo.value.isEmpty)
            return const SizedBox.shrink();
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              color: Colors.black.withOpacity(0.3),
              alignment: Alignment.center,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFF1E293B) : Colors.white)
                      .withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        blurRadius: 20, color: Colors.black.withOpacity(0.3))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(controller.reviewRoundInfo.value,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.orangeAccent
                                : Colors.deepOrangeAccent)),
                    const SizedBox(height: 6),
                    Text("继续加油！",
                        style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white54 : Colors.black54)),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget buildEndView(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    String mode = Get.parameters['mode'] ?? 'new';

    // 1. 顽固词汇完结
    if (controller.isDifficultMode.value) {
      return Container(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_fire_department_rounded,
                size: 80, color: Colors.orangeAccent),
            const SizedBox(height: 24),
            Text("太棒了！",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 12),
            Text("当前的顽固词汇已被你全部消灭",
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => controller.exitDifficultMode(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.white),
              child: const Text("返回继续主线学习"),
            ),
          ],
        ),
      );
    }

    // 2. 复习模式完结
    if (mode == 'review') {
      if (AiSettings.fromStorage().isConfigured) {
        // 文章在复习开始时后台预生成，结算页只负责展示当前批次结果。
        return _buildAiArticleEndScreen(isDark);
      } else {
        // 未配置 AI 时展示传统复习面板。
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_rounded,
                  size: 80,
                  color: isDark
                      ? const Color(0xFF818CF8)
                      : const Color(0xFF6366F1)),
              const SizedBox(height: 24),
              Text("复习任务已完成",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 12),
              Text("干得漂亮！建议休息一下，或者继续下一轮复习。",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black54,
                      height: 1.5)),
              const SizedBox(height: 40),
              _buildRestartBtn("再学一轮", 'REVIEW_NEXT', isDark),
              const SizedBox(height: 30),
              TextButton(
                  onPressed: () => Get.offAllNamed("/main"),
                  child: Text("回首页",
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 16)))
            ],
          ),
        );
      }
    }

    // 3. 主线学习模式完结（绝对保留原汁原味）
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_rounded,
              size: 80,
              color:
                  isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
          const SizedBox(height: 24),
          Text("本书已经学完",
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 12),
          Text(
            "恭喜您！这本书的所有单词都已学习完毕。\n您可以选择一种顺序重新学习本词书：",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black54,
                height: 1.5),
          ),
          const SizedBox(height: 40),
          _buildRestartBtn("正序重学 (A-Z)", 'ASC', isDark),
          const SizedBox(height: 12),
          _buildRestartBtn("倒序重学 (Z-A)", 'DESC', isDark),
          const SizedBox(height: 12),
          _buildRestartBtn("乱序重学 (随机)", 'RANDOM', isDark),
          const SizedBox(height: 30),
          TextButton(
            onPressed: () => Get.offAllNamed("/main"),
            child: Text("返回首页",
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 16)),
          )
        ],
      ),
    );
  }

  // --- 复习过程中的主动查阅弹窗 ---
  void _showArticleBottomSheet(BuildContext context) {
    if (controller.aiArticle.value.isEmpty &&
        !controller.isGeneratingArticle.value) {
      controller.generateArticle();
    }
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    Get.bottomSheet(
      Container(
        height: Get.height * 0.75,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                    const SizedBox(width: 8),
                    Text("AI 串记文章",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87)),
                  ],
                ),
                IconButton(
                    icon: const Icon(Icons.close), onPressed: () => Get.back())
              ],
            ),
            const Divider(),
            Expanded(child: _buildArticleContent(isDark)),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  // --- 复习完结时的独立文章结算屏幕 ---
  Widget _buildAiArticleEndScreen(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_rounded, color: Colors.green, size: 28),
              const SizedBox(width: 8),
              Text("本轮复习完成！来看看你的串记文章：",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
          const SizedBox(height: 15),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : Colors.grey.withOpacity(0.2)),
              ),
              child: _buildArticleContent(isDark),
            ),
          ),
          const SizedBox(height: 20),
          _buildRestartBtn("再学一轮", 'REVIEW_NEXT', isDark),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Get.offAllNamed("/main"),
            child: Text("回首页",
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 16)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- 文章内容：英文单词可点击查词 ---
  Widget _buildArticleContent(bool isDark) {
    return Obx(() {
      String text = controller.aiArticle.value;
      if (controller.isGeneratingArticle.value && text.isEmpty) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.purpleAccent),
            const SizedBox(height: 16),
            Text("AI 正在根据本轮单词撰写文章...",
                style:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                controller.cancelArticleGeneration();
              },
              child: Text("取消生成",
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 14)),
            ),
          ],
        );
      }

      if (text.isEmpty) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text("暂无内容",
                style:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => controller.regenerateArticle(),
              child: Text("重新生成",
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 14)),
            ),
          ],
        );
      }

      // 区分"文章生成失败"的错误文本和正常文章
      bool isError = text.startsWith("文章生成失败");
      if (isError) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.redAccent, fontSize: 14)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                controller.regenerateArticle();
              },
              child: Text("重新生成",
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 14)),
            ),
          ],
        );
      }

      var article = _ArticleTextWidget(text: text, isDark: isDark);
      if (!controller.isGeneratingArticle.value) return article;

      return Column(
        children: [
          const LinearProgressIndicator(color: Colors.purpleAccent),
          const SizedBox(height: 8),
          Expanded(child: article),
        ],
      );
    });
  }

  // 结算面板的按钮组件
  Widget _buildRestartBtn(String text, String action, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
          foregroundColor: isDark ? Colors.white : Colors.black87,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          if (action == 'REVIEW_AGAIN') {
            controller.reviewTodayAgain();
          } else if (action == 'REVIEW_NEXT') {
            controller.startNewReviewBatch();
          } else {
            controller.restartBook(action);
          }
        },
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Future<void> showOptions(BuildContext context) async {
    var playing = controller.playing.value;
    if (playing) {
      await controller.stopPlay();
    }
    var queueCount = controller.queueCount.value;
    var waitCount = controller.dailyWantCount.value;
    //设定：1 队列 2 思考间隔 3 学习间隔 4 日词汇量
    await showModalBottomSheet(
        context: context,
        // barrierColor: Colors.black.withOpacity(0.1),
        backgroundColor: Colors.transparent,
        builder: (context) {
          return buildOptionView(context);
        });
    if (queueCount != controller.queueCount.value ||
        waitCount != controller.dailyWantCount.value) {
      //重新取词
      var word = controller.word.value;
      await controller.fetchWords();
      if (word != null) {
        var words = controller.playingWords;
        for (var i = 0; i < words.length; i++) {
          var temp = words[i];
          if (word.word == temp.word) {
            controller.playingIndex = i;
            controller.word.value = word;
            controller.fetchWordStatus();
            break;
          }
        }
      } else {
        controller.startPlay();
      }
    }
    if (playing) {
      controller.startPlay();
    }
  }

  Widget buildOptionView(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurStyle: BlurStyle.outer,
            blurRadius: 10,
            color: Colors.green.withOpacity(0.1),
          )
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              child: Text(
                "播放设置",
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 20,
                ),
              ),
            ),
            Expanded(
              child: Container(
                child: Material(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        //每日学习
                        // InkWell(
                        //   onTap: () {
                        //     showWordPicker(context);
                        //   },
                        //   child: Container(
                        //     padding: EdgeInsets.only(
                        //       top: 20,
                        //       bottom: 20,
                        //       right: 20,
                        //     ),
                        //     margin: EdgeInsets.only(
                        //       left: 20,
                        //     ),
                        //     decoration: BoxDecoration(
                        //       border: Border(
                        //         bottom: BorderSide(
                        //           color: Colors.grey.withOpacity(0.1),
                        //           width: 1,
                        //         ),
                        //       ),
                        //     ),
                        //     child: Stack(
                        //       alignment: Alignment.center,
                        //       children: [
                        //         Align(
                        //           alignment: Alignment.centerLeft,
                        //           child: Container(
                        //             child: Row(
                        //               children: [
                        //                 Text(
                        //                   "每日词汇量(个)",
                        //                   style: TextStyle(
                        //                     color: Colors.black,
                        //                     fontSize: 18,
                        //                   ),
                        //                 ),
                        //                 // IconButton(
                        //                 //     splashRadius: 16,
                        //                 //     padding: EdgeInsets.symmetric(
                        //                 //       horizontal: 6,
                        //                 //     ),
                        //                 //     onPressed: () {},
                        //                 //     constraints: BoxConstraints(
                        //                 //       maxWidth: 40,
                        //                 //       maxHeight: 40,
                        //                 //     ),
                        //                 //     icon: Icon(
                        //                 //       Icons.help_outline,
                        //                 //       color: Colors.black54,
                        //                 //       size: 20,
                        //                 //     )),
                        //               ],
                        //             ),
                        //           ),
                        //         ),
                        //         Align(
                        //           alignment: Alignment.centerRight,
                        //           child: Container(
                        //             child: Row(
                        //               mainAxisSize: MainAxisSize.min,
                        //               children: [
                        //                 Container(
                        //                   child: Obx(
                        //                     () => Text(
                        //                       "${controller.dailyWantCount.value == -1 || controller.dailyWantCount.value == 1000000 ? "无限" : controller.dailyWantCount.value}",
                        //                       style: TextStyle(
                        //                         fontSize: 16,
                        //                         color: Colors.black54,
                        //                       ),
                        //                     ),
                        //                   ),
                        //                 ),
                        //                 Padding(
                        //                   padding:
                        //                       const EdgeInsets.only(left: 8.0),
                        //                   child: Icon(
                        //                     Icons.keyboard_arrow_right,
                        //                     color:
                        //                         Colors.black54.withOpacity(0.5),
                        //                     size: 24,
                        //                   ),
                        //                 ),
                        //               ],
                        //             ),
                        //           ),
                        //         ),
                        //       ],
                        //     ),
                        //   ),
                        // ),
                        //思考等待
                        InkWell(
                          onTap: () {
                            showThinkTimePicker(context);
                          },
                          child: Container(
                            padding: EdgeInsets.only(
                              top: 20,
                              bottom: 20,
                              right: 20,
                            ),
                            margin: EdgeInsets.only(
                              left: 20,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    child: Row(
                                      children: [
                                        Text(
                                          "思考等待(秒)",
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          child: Obx(
                                            () => Text(
                                              "${controller.thinkWaitTime.value}",
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8.0),
                                          child: Icon(
                                            Icons.keyboard_arrow_right,
                                            color:
                                                Colors.black54.withOpacity(0.5),
                                            size: 24,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        //播放等待
                        InkWell(
                          onTap: () {
                            showStudyTimePicker(context);
                          },
                          child: Container(
                            padding: EdgeInsets.only(
                              top: 20,
                              bottom: 20,
                              right: 20,
                            ),
                            margin: EdgeInsets.only(
                              left: 20,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    child: Row(
                                      children: [
                                        Text(
                                          "阅读等待(秒)",
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          child: Obx(
                                            () => Text(
                                              "${controller.readWaitTime.value}",
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8.0),
                                          child: Icon(
                                            Icons.keyboard_arrow_right,
                                            color:
                                                Colors.black54.withOpacity(0.5),
                                            size: 24,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        //循环队列
                        InkWell(
                          onTap: () {
                            showQueueCountPicker(context);
                          },
                          child: Container(
                            padding: EdgeInsets.only(
                              top: 20,
                              bottom: 20,
                              right: 20,
                            ),
                            margin: EdgeInsets.only(
                              left: 20,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    children: const [
                                      Text(
                                        "循环队列(个)",
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Obx(
                                        () => Text(
                                          "${controller.queueCount.value}",
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 8.0),
                                        child: Icon(
                                          Icons.keyboard_arrow_right,
                                          color:
                                              Colors.black54.withOpacity(0.5),
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        InkWell(
                          onTap: () {
                            // 弹出类似 showWordPicker 的 BottomPicker 选择数字 (10, 20, 50, 100...)
                            showReviewCountPicker(context);
                          },
                          child: _buildOptionTile(
                              "每日复习量", "${controller.reviewDailyCount.value}"),
                        ),

                        //自动 pass
                        InkWell(
                          onTap: () {
                            showAutoPassPicker(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.only(
                              top: 20,
                              bottom: 20,
                              right: 20,
                            ),
                            margin: const EdgeInsets.only(
                              left: 20,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    children: const [
                                      Text(
                                        "自动PASS",
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Obx(
                                        () {
                                          // 自动pass
                                          return Text(
                                            controller.autoPass.value
                                                ? "是"
                                                : "否",
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.black54,
                                            ),
                                          );
                                        },
                                      ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 8.0),
                                        child: Icon(
                                          Icons.keyboard_arrow_right,
                                          color:
                                              Colors.black54.withOpacity(0.5),
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

//   void showWordPicker(BuildContext context) {
//     var countList = [
//       10,
//       20,
//       30,
//       40,
//       50,
//       60,
//       70,
//       80,
//       90,
//       100,
//       150,
//       200,
//       300,
//       400,
//       500,
//       600,
//       700,
//       800,
//       900,
//       1000,
//       1000000
//     ];
//     var count = controller.dailyWantCount.value;
//     var index = countList.indexOf(count);
//     if (index == -1) {
//       index = countList.length - 1;
//     }
//     BottomPicker(
//       dismissable: true,
//       selectedItemIndex: index,
//       title: "请选择每日词汇量(个)",
//       onSubmit: (index) {
//         controller.dailyWantCount.value = countList[index];
//       },
//       items: [
//         for (var value in countList)
//           Text("${value == -1 || value > 1000 ? "无限" : value}")
//       ],
//       buttonText: "            确定            ",
//       displayButtonIcon: false,
//       displaySubmitButton: true,
//       buttonSingleColor: Colors.deepPurple,
//       buttonTextStyle: TextStyle(
//         color: Colors.white,
//       ),
//       pickerTextStyle: TextStyle(
//         height: 1.4,
//         fontSize: 24,
//         color: Colors.black,
//       ),
//       bottomPickerTheme: BottomPickerTheme.blue,
//       titleStyle: TextStyle(
//         height: 1.5,
//         fontSize: 16,
//       ),
//       displayCloseIcon: false,
//       itemExtent: 32,
//       height: 400,
//     ).show(context);
//     // ScrollView
//   }

  void showThinkTimePicker(BuildContext context) {
    BottomPicker(
      dismissable: true,
      selectedItemIndex: controller.thinkWaitTime.value,
      onSubmit: (index) {
        controller.thinkWaitTime.value = index;
      },
      title: "请选择思考等待(秒)",
      items: [
        for (var i = 0; i < 21; i++) Text("${i}"),
      ],
      buttonText: "            确定            ",
      displayButtonIcon: false,
      displaySubmitButton: true,
      buttonSingleColor: Colors.deepPurple,
      buttonTextStyle: TextStyle(
        color: Colors.white,
      ),
      pickerTextStyle: TextStyle(
        height: 1.4,
        fontSize: 24,
        color: Colors.black,
      ),
      bottomPickerTheme: BottomPickerTheme.blue,
      titleStyle: TextStyle(
        height: 1.5,
        fontSize: 16,
      ),
      displayCloseIcon: false,
      itemExtent: 32,
      height: 400,
    ).show(context);
  }

  void showStudyTimePicker(BuildContext context) {
    controller.dailyStudyCount;
    BottomPicker(
      dismissable: true,
      selectedItemIndex: controller.readWaitTime.value - 1,
      onSubmit: (index) {
        controller.readWaitTime.value = index + 1;
      },
      title: "请选择单词阅读等待(秒)",
      items: [
        for (var i = 0; i < 20; i++) Text("${i + 1}"),
      ],
      buttonText: "            确定            ",
      displayButtonIcon: false,
      displaySubmitButton: true,
      buttonSingleColor: Colors.deepPurple,
      buttonTextStyle: TextStyle(
        color: Colors.white,
      ),
      pickerTextStyle: TextStyle(
        height: 1.4,
        fontSize: 24,
        color: Colors.black,
      ),
      bottomPickerTheme: BottomPickerTheme.blue,
      titleStyle: TextStyle(
        height: 1.5,
        fontSize: 16,
      ),
      displayCloseIcon: false,
      itemExtent: 32,
      height: 400,
    ).show(context);
  }

  void showQueueCountPicker(BuildContext context) {
    BottomPicker(
      dismissable: true,
      selectedItemIndex: controller.queueCount.value - 1,
      onSubmit: (index) {
        controller.queueCount.value = index + 1;
      },
      title: "请选择单词循环队列词数(个)",
      items: [
        for (var i = 0; i < 20; i++) Text("${i + 1}"),
      ],
      buttonText: "            确定            ",
      displayButtonIcon: false,
      displaySubmitButton: true,
      buttonSingleColor: Colors.deepPurple,
      buttonTextStyle: TextStyle(
        color: Colors.white,
      ),
      pickerTextStyle: TextStyle(
        height: 1.4,
        fontSize: 24,
        color: Colors.black,
      ),
      bottomPickerTheme: BottomPickerTheme.blue,
      titleStyle: TextStyle(
        height: 1.5,
        fontSize: 16,
      ),
      displayCloseIcon: false,
      itemExtent: 32,
      height: 400,
    ).show(context);
  }

  void showAutoPassPicker(BuildContext context) {
    BottomPicker(
      dismissable: true,
      selectedItemIndex: controller.autoPass.value ? 0 : 1,
      onSubmit: (index) {
        controller.autoPass.value = index == 0;
      },
      title: "请选择是否自动PASS",
      items: [
        Text("是"),
        Text("否"),
      ],
      buttonText: "            确定            ",
      displayButtonIcon: false,
      displaySubmitButton: true,
      buttonSingleColor: Colors.deepPurple,
      buttonTextStyle: TextStyle(
        color: Colors.white,
      ),
      pickerTextStyle: TextStyle(
        height: 1.4,
        fontSize: 24,
        color: Colors.black,
      ),
      bottomPickerTheme: BottomPickerTheme.blue,
      titleStyle: TextStyle(
        height: 1.5,
        fontSize: 16,
      ),
      displayCloseIcon: false,
      itemExtent: 32,
      height: 400,
    ).show(context);
  }

  /// 下方弹出单词列表
  Future<void> showWordListBottomSheet(BuildContext context) async {
    var playing = controller.playing.value;
    if (playing) {
      await controller.stopPlay();
    }
    Get.put(WordListController());
    final selectedIndex = await showMaterialModalBottomSheet<int>(
        context: context,
        expand: true,
        bounce: false,
        closeProgressThreshold: 0.95,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        duration: const Duration(
          milliseconds: 300,
        ),
        builder: (context) {
          return buildWordListView(context);
        });

    Get.delete<WordListController>();

    if (selectedIndex != null) {
      await controller.jumpToWordAt(selectedIndex);
    }

    if (playing) {
      controller.startPlay();
    }
  }

  Widget buildWordListView(BuildContext context) {
    return WordListView();
  }
}

// --- PASS 按钮：短按 pass，长按弹出「设为熟词 / 顽固单词」 ---
class _PassButton extends StatefulWidget {
  final bool isDark;
  const _PassButton({required this.isDark});

  @override
  State<_PassButton> createState() => _PassButtonState();
}

class _PassButtonState extends State<_PassButton>
    with SingleTickerProviderStateMixin {
  bool _showActions = false;
  bool _pressing = false;
  late AnimationController _progressCtrl;
  OverlayEntry? _overlayEntry;
  final GlobalKey _circleKey0 = GlobalKey();
  final GlobalKey _circleKey1 = GlobalKey();

  Timer? _longPressTimer;
  int? _overlaySelectedIndex;
  bool _longPressHandled = false;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _cancelLongPress();
    _progressCtrl.dispose();
    super.dispose();
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _overlaySelectedIndex = null;
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pressing = true;
    _progressCtrl.forward(from: 0);
    setState(() {});

    _longPressTimer = Timer(const Duration(milliseconds: 400), () {
      if (_pressing && mounted) {
        _longPressHandled = true;
        _pressing = false;
        _showActionButtons();
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_showActions || _overlayEntry == null) return;
    // Listener always receives move events for a pointer that went down within it,
    // even after the overlay appears on top
    final hit = _hitTestOverlay(event.position);
    if (hit != _overlaySelectedIndex) {
      _overlaySelectedIndex = hit;
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    final wasShowingActions = _showActions;
    _cancelLongPress();
    _pressing = false;
    _longPressHandled = false;
    _progressCtrl.reverse();
    setState(() {});
    if (wasShowingActions && _overlayEntry != null) {
      // If overlay was showing, check if user released on a circle
      final hit = _hitTestOverlay(event.position);
      if (hit != null) {
        _executeAction(hit);
      }
      _dismiss();
    }
  }

  int? _hitTestOverlay(Offset globalPosition) {
    final keys = [_circleKey0, _circleKey1];
    for (int i = 0; i < keys.length; i++) {
      final renderBox =
          keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) continue;
      final topLeft = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final center = topLeft + Offset(size.width / 2, size.height / 2);
      if ((globalPosition - center).distance < 52) {
        return i;
      }
    }
    return null;
  }

  void _executeAction(int index) {
    final controller = Get.find<StudyController>();
    if (index == 0) {
      controller.delete();
    } else {
      controller.addToDifficult();
    }
  }

  void _showActionButtons() {
    if (_showActions || !mounted) return;
    _longPressHandled = true;
    _progressCtrl.reverse();
    setState(() => _showActions = true);

    final isDark = widget.isDark;

    _overlayEntry = OverlayEntry(builder: (context) {
      return _ActionOverlay(
        isDark: isDark,
        circleKey0: _circleKey0,
        circleKey1: _circleKey1,
        selectedIndex: _overlaySelectedIndex,
      );
    });

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _dismiss() {
    _removeOverlay();
    if (mounted) setState(() => _showActions = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<StudyController>();
    final isDark = widget.isDark;

    return Obx(() {
      final enabled = controller.controlEnable.value;

      return Container(
        margin: const EdgeInsets.only(bottom: 100.0, left: 50, right: 50),
        width: 100,
        height: 100,
        child: Listener(
          onPointerDown: enabled ? _onPointerDown : null,
          onPointerMove: enabled ? _onPointerMove : null,
          onPointerUp: enabled ? _onPointerUpOrCancel : null,
          onPointerCancel: enabled ? _onPointerUpOrCancel : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        blurStyle: BlurStyle.outer,
                        blurRadius: 10,
                        color: isDark
                            ? Colors.green.withOpacity(0.5)
                            : Colors.green.withOpacity(0.2),
                      )
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: enabled && !_longPressHandled
                        ? () => controller.pass()
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check,
                              color: isDark ? Colors.white54 : Colors.black12,
                              size: 50),
                          Text("PASS",
                              style: TextStyle(
                                  color:
                                      isDark ? Colors.white54 : Colors.black12,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_pressing)
                AnimatedBuilder(
                  animation: _progressCtrl,
                  builder: (context, child) {
                    return SizedBox(
                      width: 100,
                      height: 100,
                      child: CustomPaint(
                        painter: _ProgressPainter(
                          progress: _progressCtrl.value,
                          color: isDark ? Colors.greenAccent : Colors.green,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    });
  }
}

// 长按后上滑选择操作的面板
class _ActionOverlay extends StatelessWidget {
  final bool isDark;
  final GlobalKey circleKey0;
  final GlobalKey circleKey1;
  final int? selectedIndex;

  const _ActionOverlay({
    required this.isDark,
    required this.circleKey0,
    required this.circleKey1,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: Colors.black26),
        Positioned(
          left: 0,
          right: 0,
          bottom: 280,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionCircle(
                    key: circleKey0,
                    icon: Icons.check_circle_outline,
                    label: "熟词",
                    color: Colors.green,
                    isDark: isDark,
                    selected: selectedIndex == 0,
                  ),
                  const SizedBox(width: 56),
                  _ActionCircle(
                    key: circleKey1,
                    icon: Icons.local_fire_department_outlined,
                    label: "顽固",
                    color: Colors.orangeAccent,
                    isDark: isDark,
                    selected: selectedIndex == 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 长按进度环绘制
class _ProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  _ProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter old) =>
      old.progress != progress;
}

// 弹出的圆形操作按钮
class _ActionCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final bool selected;

  const _ActionCircle({
    Key? key,
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    this.selected = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: null,
            borderRadius: BorderRadius.circular(39),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              width: selected ? 78 : 72,
              height: selected ? 78 : 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? color.withOpacity(selected ? 0.35 : 0.2)
                    : color.withOpacity(selected ? 0.2 : 0.12),
                border: Border.all(
                  color: selected ? color : color.withOpacity(0.5),
                  width: selected ? 2.5 : 1.5,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12)]
                    : null,
              ),
              child: Icon(icon, color: color, size: selected ? 34 : 30),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

// --- 可点击单词的文章渲染组件 ---
class _ArticleTextWidget extends StatefulWidget {
  final String text;
  final bool isDark;
  const _ArticleTextWidget({required this.text, required this.isDark});

  @override
  State<_ArticleTextWidget> createState() => _ArticleTextWidgetState();
}

class _ArticleTextWidgetState extends State<_ArticleTextWidget> {
  @override
  Widget build(BuildContext context) {
    var spans = _buildSpans(widget.isDark);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: RichText(
        text: TextSpan(
            style: const TextStyle(fontSize: 16, height: 1.6), children: spans),
      ),
    );
  }

  List<TextSpan> _buildSpans(bool isDark) {
    var spans = <TextSpan>[];
    var parts = widget.text.split('**');
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 1) {
        spans.add(TextSpan(
          text: parts[i],
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.orangeAccent : Colors.deepOrangeAccent),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _lookupWord(parts[i].trim(), widget.isDark),
        ));
      } else {
        // 拆分出每个英文单词，使其可点击查词
        final tokenRe = RegExp(r"[a-zA-Z']+|[^a-zA-Z']+");
        for (var m in tokenRe.allMatches(parts[i])) {
          final t = m.group(0)!;
          if (RegExp(r"^[a-zA-Z']+$").hasMatch(t)) {
            spans.add(TextSpan(
              text: t,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _lookupWord(t, widget.isDark),
            ));
          } else {
            spans.add(TextSpan(
              text: t,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ));
          }
        }
      }
    }
    return spans;
  }

  void _lookupWord(String word, bool isDark) async {
    var appService = Get.find<AppService>();
    // 先查本地
    var local = appService.wordService.spellMap[word] ??
        appService.wordService.spellMap[word.toLowerCase()];
    if (local != null &&
        local.means != null &&
        local.means!.trim().isNotEmpty) {
      _showWordCard(local, isDark);
      return;
    }
    // 显示加载中
    Get.dialog(
      Center(
          child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3)),
      )),
      barrierDismissible: true,
      barrierColor: Colors.black26,
    );

    final fetched = await fetchWordDefinition(word);
    Get.back(); // 关闭 loading

    if (fetched != null &&
        fetched.means != null &&
        fetched.means!.trim().isNotEmpty) {
      appService.wordService.mergeFetchedWord(fetched);
      _showWordCard(appService.wordService.spellMap[word] ?? fetched, isDark);
    } else {
      Get.snackbar("未找到", "无法获取「$word」的释义",
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2));
    }
  }

  void _showWordCard(Word word, bool isDark) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            // 单词 + 音标
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(word.word ?? "",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFF818CF8)
                            : Colors.deepOrangeAccent)),
                if (word.usVoice != null && word.usVoice!.isNotEmpty)
                  _buildPhoneticChip("美", word.usVoice!, word.word, 1, isDark),
                if (word.ukVoice != null && word.ukVoice!.isNotEmpty)
                  _buildPhoneticChip("英", word.ukVoice!, word.word, 2, isDark),
              ],
            ),
            const SizedBox(height: 10),
            // 释义
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : Colors.grey.withOpacity(0.15)),
              ),
              child: Text(word.means ?? "",
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color:
                          isDark ? const Color(0xFFF1F5F9) : Colors.black87)),
            ),
            const SizedBox(height: 14),
            // 加入词书按钮
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: () {
                  Get.back();
                  _addFetchedWordToBook(word.word ?? "");
                },
                icon: Icon(Icons.add_circle_outline,
                    size: 18,
                    color: isDark
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF6366F1)),
                label: Text("加入词书",
                    style: TextStyle(
                        color: isDark
                            ? const Color(0xFF818CF8)
                            : const Color(0xFF6366F1),
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : Colors.grey.withOpacity(0.3)),
                ),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildPhoneticChip(
      String label, String phonetic, String? word, int voiceType, bool isDark) {
    return InkWell(
      onTap: () => playWordSound(word, voiceType),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.volume_up,
              size: 16, color: isDark ? Colors.white54 : Colors.black54),
          const SizedBox(width: 2),
          Text("$label $phonetic",
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54)),
        ]),
      ),
    );
  }

  void _addFetchedWordToBook(String spell) async {
    var appService = Get.find<AppService>();
    List<String> customBooks = appService.wordService.customBookNames;

    if (customBooks.isEmpty) {
      await _addWordToSpecificBook(spell, "我的生词本");
      return;
    }

    bool isDark = Get.isDarkMode;
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text("选择要加入的生词本",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 12),
            ...customBooks.map((name) => ListTile(
                  leading: Icon(Icons.library_books,
                      size: 22,
                      color: isDark
                          ? const Color(0xFF818CF8)
                          : const Color(0xFF6366F1)),
                  title: Text(name,
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15)),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  onTap: () async {
                    Get.back();
                    await _addWordToSpecificBook(spell, name);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addWordToSpecificBook(String spell, String bookName) async {
    var appService = Get.find<AppService>();

    // 确保释义已获取
    var existing = appService.wordService.spellMap[spell];
    if (existing == null ||
        existing.means == null ||
        existing.means!.trim().isEmpty) {
      final fetched = await fetchWordDefinition(spell);
      if (fetched != null) appService.wordService.mergeFetchedWord(fetched);
    }

    final added = await appService.addWordToCustomBook(bookName, spell);
    Get.snackbar(
      added ? "收藏成功" : "提示",
      added ? "《$spell》已加入《$bookName》" : "《$spell》已在《$bookName》中",
      duration: const Duration(seconds: 1),
    );
  }
}

class WordListView extends GetView<WordListController> {
  WordListView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: MediaQuery.of(context).size.height / 5,
          ),
          onTap: () {
            Get.back();
          },
        ),
        Expanded(
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  height: 50,
                  child: Stack(
                    children: [
                      Align(
                          alignment: Alignment.center,
                          child: Obx(() => Center(
                                child: Text(
                                  controller.title.value,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ))),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          child: IconButton(
                            onPressed: () {
                              Get.back();
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      PageView.builder(
                          itemCount: 4,
                          controller: controller.pageController,
                          onPageChanged: (index) {
                            controller.onPageChanged(index);
                          },
                          itemBuilder: (context, index) {
                            //1.播放列表
                            //2.已学习
                            //3.熟词(已删除)
                            //4.全部
                            if (index == 0) {
                              return buildPlayList(context);
                            }
                            if (index == 1) {
                              return buildPassList(context);
                            }
                            if (index == 2) {
                              return buildDeleteList(context);
                            }
                            if (index == 3) {
                              return buildAllList(context);
                            }
                            return ListView.builder(
                              itemCount: 100,
                              shrinkWrap: true,
                              padding: const EdgeInsets.only(bottom: 50),
                              itemBuilder: (ctx, index) {
                                return const ListTile(
                                  title: Text("bug"),
                                );
                              },
                              physics: const BouncingScrollPhysics(),
                            );
                          }),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Obx(
                          () => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < 4; i++)
                                GestureDetector(
                                  onTap: () {
                                    controller.pageController.jumpToPage(i);
                                  },
                                  behavior: HitTestBehavior.translucent,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    margin: EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 30,
                                    ),
                                    decoration: controller.pageIndex.value == i
                                        ? BoxDecoration(
                                            color: Colors.grey.withOpacity(0.8),
                                            borderRadius:
                                                BorderRadius.circular(100),
                                          )
                                        : BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey
                                                    .withOpacity(0.8)),
                                            borderRadius:
                                                BorderRadius.circular(100),
                                          ),
                                  ),
                                )
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildPlayList(BuildContext context) {
    return Obx(() {
      return ListView.builder(
        itemCount: controller.playingWords.length,
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 50),
        itemBuilder: (ctx, index) {
          var word = controller.playingWords[index];
          return buildWordTile(context, word,
              onTap: () => Navigator.of(ctx).pop(index),
              wordStatusUpdateCallback: () async {
                reFetchWordList(word: word);
              });
        },
        physics: const BouncingScrollPhysics(),
      );
    });
  }

  Widget buildPassList(BuildContext context) {
    return Obx(() {
      return ListView.builder(
        itemCount: controller.passList.value.length,
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: 50),
        itemBuilder: (ctx, index) {
          var word = controller.getWordVO(controller.passList.value[index]);
          return buildWordTile(context, word,
              onTap: _jumpToWordCallback(ctx, word),
              wordStatusUpdateCallback: () {
            reFetchWordList(word: word);
          });
        },
        physics: BouncingScrollPhysics(),
      );
    });
  }

  Widget buildDeleteList(BuildContext context) {
    return Obx(() {
      return ListView.builder(
        itemCount: controller.deleteList.value.length,
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 50),
        itemBuilder: (ctx, index) {
          var word = controller.getWordVO(controller.deleteList.value[index]);
          return buildWordTile(context, word, wordStatusUpdateCallback: () {
            reFetchWordList(word: word);
          });
        },
        physics: const BouncingScrollPhysics(),
      );
    });
  }

  Widget buildWordTile(BuildContext context, WordVO? word,
      {VoidCallback? onTap, VoidCallback? wordStatusUpdateCallback}) {
    return ListTile(
      onTap: onTap,
      title: Text(word?.word ?? ""),
      subtitle: Text(
        word?.means?.map((e) => e.toString()).join("\n") ?? "",
        style: const TextStyle(
          color: Colors.black54,
        ),
      ),
      trailing: IconButton(
          onPressed: () async {
            //显示bottom菜单：删除/恢复
            if (word == null) return;
            //读取单词状态：熟词？
            await controller.getDeleteStatus(word);
            var isDelete = word.isDelete.obs;
            await showModalBottomSheet(
                context: context,
                // barrierColor: Colors.black.withOpacity(0.1),
                backgroundColor: Colors.transparent,
                builder: (context) {
                  return Container(
                      height: MediaQuery.of(context).size.height * 4 / 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 50,
                            decoration: const BoxDecoration(
                                // border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                ),
                            child: Stack(
                              children: [
                                const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 20.0),
                                      child: Text(
                                        "单词详情",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    )),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    margin: EdgeInsets.only(right: 10),
                                    child: IconButton(
                                      onPressed: () {
                                        Get.back();
                                      },
                                      icon: Icon(Icons.close),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                              child: SingleChildScrollView(
                                  child: WordView(
                            word: word,
                          ))),
                          //删除恢复按钮
                          Container(
                            padding: EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            child: Obx(() {
                              return Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: isDelete.value == true
                                          ? () async {
                                              //重新学习：从删除数据库恢复单词
                                              await controller
                                                  .restoreWord(word);
                                              isDelete.value =
                                                  word.isDelete ?? false;
                                            }
                                          : null,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons
                                              .settings_backup_restore_outlined),
                                          Text("重新学习"),
                                        ],
                                      ),
                                      style: ButtonStyle(
                                        foregroundColor:
                                            MaterialStateProperty.all(
                                                isDelete.value == false ||
                                                        isDelete.value == null
                                                    ? Colors.grey
                                                    : Colors.black),
                                        padding: MaterialStateProperty.all(
                                            const EdgeInsets.symmetric(
                                          vertical: 10,
                                          horizontal: 20,
                                        )),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: isDelete.value == true
                                          ? null
                                          : () async {
                                              //删除单词：设为熟词
                                              await controller.deleteWord(word);
                                              isDelete.value =
                                                  word.isDelete ?? false;
                                            },
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.delete_outlined),
                                          Text("设为熟词"),
                                        ],
                                      ),
                                      style: ButtonStyle(
                                        foregroundColor:
                                            MaterialStateProperty.all(
                                                isDelete.value == true
                                                    ? Colors.grey
                                                    : Colors.red.shade400),
                                        padding: MaterialStateProperty.all(
                                            const EdgeInsets.symmetric(
                                          vertical: 10,
                                          horizontal: 20,
                                        )),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ],
                      ));
                });
            //刷新列表
            wordStatusUpdateCallback?.call();
          },
          icon: const Icon(
            Icons.more_horiz_outlined,
          )),
    );
  }

  Widget buildAllList(BuildContext context) {
    return Obx(() {
      //搜索单词
      var wordFilterList = controller.allList.value
          .where((element) =>
              element.word!
                  .toLowerCase()
                  .contains(controller.wordSearchText.toLowerCase()) ||
              controller.isContainsMeans(
                  element, controller.wordSearchText.value))
          .toList();
      return Column(
        children: [
          TextField(
            onChanged: (text) {
              controller.wordSearchText.value = text;
            },
          ),
          Expanded(
            child: ListView.builder(
              itemCount: wordFilterList.length,
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 50),
              itemBuilder: (ctx, index) {
                /// 1、点击单词显示详情：对话框？下拉？
                /// 2、点击菜单按钮，显示下拉删除单词、恢复单词按钮
                /// 3、单词释义显示
                var word = wordFilterList[index];
                return buildWordTile(context, word,
                    onTap: _jumpToWordCallback(ctx, word),
                    wordStatusUpdateCallback: () {
                  reFetchWordList(word: word);
                });
              },
              physics: const BouncingScrollPhysics(),
            ),
          ),
        ],
      );
    });
  }

  VoidCallback? _jumpToWordCallback(BuildContext context, WordVO? word) {
    final wordId = word?.wordId;
    if (wordId == null) return null;
    final index = controller.playingWords
        .indexWhere((playingWord) => playingWord.wordId == wordId);
    if (index < 0) return null;
    return () => Navigator.of(context).pop(index);
  }

  void reFetchWordList({
    WordVO? word,
  }) async {
    await controller.fetchWordList();
  }
}
