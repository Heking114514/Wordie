// lib/view/home/home_v2.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controller/home/home_v2.dart';
import '../../util/audio.dart';

class HomeViewV2 extends GetView<HomeControllerV2> {
  const HomeViewV2({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    SystemChrome.setSystemUIOverlayStyle(
      isDark ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
             : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent)
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              _buildHeader(isDark),
              _buildProgressCard(isDark),
              _buildActionGrid(isDark),
              _buildDailyWordHeader(isDark),
              _buildDailyWordCard(isDark),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children:[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Obx(() => Text(
                  "${controller.greeting}, ${controller.username} 👋",
                  style: TextStyle(fontSize: 16, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                )),
                const SizedBox(height: 6),
                Obx(() => Text(
                  controller.currentQuote.value,
                  style: TextStyle(
                    fontSize: 14, 
                    fontStyle: FontStyle.italic, 
                    color: isDark ? Colors.white70 : const Color(0xFF475569)
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors:[Color(0xFFFF9D00), Color(0xFFFF5E00)]),
              borderRadius: BorderRadius.circular(20),
              boxShadow:[BoxShadow(color: const Color(0xFFFF5E00).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Obx(() => Row(
              children:[
                const Icon(Icons.local_fire_department, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text("${controller.streakDays.value} 天", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(bool isDark) {
    return GestureDetector(
      onTap: () {
        if (!controller.isBookValid.value) {
          Get.toNamed('/selectBook');
        } else {
          Get.toNamed('/review_library')?.then((_) => controller.fetchInfo());
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow:[BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Row(
          children:[
            SizedBox(
              width: 70, height: 70,
              child: Stack(
                fit: StackFit.expand,
                children:[
                  Obx(() => CircularProgressIndicator(
                    value: controller.progressPercent.value,
                    strokeWidth: 8,
                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
                  )),
                  Center(
                    child: Obx(() => Text(
                      "${(controller.progressPercent.value * 100).toInt()}%",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : const Color(0xFF1E293B)),
                    )),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  // ==== 修复：修改产生歧义的文案 ====
                  Text("词书学习总进度", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B))),
                  const SizedBox(height: 6),
                  Obx(() => Text(
                    controller.isBookValid.value
                        ? "《${controller.wordBook.value}》: 已学 ${controller.progress.value} 词\n点击进入复习库"
                        : "当前词书已被删除或失效\n快去选一本书去学吧！",
                    style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        children:[
          GestureDetector(
            onTap: () => controller.toStudyNew(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: isDark ?[const Color(0xFF4F46E5), const Color(0xFF9333EA)] :[const Color(0xFF6366F1), const Color(0xFFA855F7)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow:[BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text("学习新词", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Obx(() => Text(
                          controller.isBookValid.value
                              ? "当前正在学习：《${controller.wordBook.value}》"
                              : "快去选一本书去学吧",
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)
                        )),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: const[
                        Text("GO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children:[
              Expanded(
                child: GestureDetector(
                  onTap: () => controller.showReviewSettingsDialog(), 
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF2563EB) : const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const[
                        Icon(Icons.history_edu, color: Colors.white, size: 32),
                        SizedBox(height: 12),
                        Text("复习旧词", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    var bookName = await Get.toNamed('/selectBook');
                    if (bookName != null) {
                      controller.appService.selectBook(bookName);
                      controller.fetchInfo();
                      controller.fetchDailyWord();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF059669) : const Color(0xFF10B981), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const[
                        Icon(Icons.menu_book, color: Colors.white, size: 32),
                        SizedBox(height: 12),
                        Text("我的词库", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyWordHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children:[
          Text("每日一词", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
          GestureDetector(
            onTap: () => controller.refreshDailyWord(),
            child: Row(
              children:[
                Text("换一个", style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1))),
                const SizedBox(width: 4),
                Icon(Icons.sync, size: 14, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDailyWordCard(bool isDark) {
    return Obx(() {
      final word = controller.dailyWord.value;
      if (word == null) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow:[BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: ClipRRect( 
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight( 
            child: Row(
              children:[
                Container(width: 5, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children:[
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children:[
                                  Text(word.word ?? "", 
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1))),
                                  const SizedBox(width: 8),
                                  Text("/${word.ukVoice ?? ""}/", 
                                    style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 12)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => playWordSound(word.word, 1),
                              child: Icon(Icons.volume_up, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1), size: 20),
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          word.means?.join("；") ?? "暂无释义", 
                          style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1E293B), fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (word.sentence != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            word.sentence!.replaceAll("<b>", "").replaceAll("</b>", ""),
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}