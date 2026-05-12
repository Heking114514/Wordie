import 'package:english/entity/word/vo/word.dart';
import 'package:english/widget/max_width_text.dart';
import 'package:flutter/material.dart';

import '../../util/audio.dart';
import '../../widget/sentence.dart';

class WordView extends StatelessWidget {
  final WordVO? word;
  final bool ukVoice;
  final bool showDetail;
  final int cycle;
  final bool hideDetails;

  const WordView({
    Key? key,
    this.word,
    this.ukVoice = true,
    this.showDetail = true,
    this.cycle = 0,
    this.hideDetails = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. 核心：通过 context 获取当前系统是否处于黑暗模式
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 2. 动态色彩定义（解耦：不写死颜色）
    final Color mainAccentColor = isDark ? const Color(0xFF818CF8) : Colors.deepOrangeAccent;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final Color cardBackgroundColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color meaningTextColor = isDark ? const Color(0xFFF1F5F9) : Colors.black87;
    final Color borderColor = isDark ? const Color(0xFF334155) : Colors.grey.withOpacity(0.1);

    return Container(
      // 移除硬编码边距，使用流式布局
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 单词名称与复习标签 ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "${word?.word}",
                style: TextStyle(
                  fontSize: 34,
                  color: mainAccentColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              if (cycle > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  margin: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(isDark ? 0.4 : 0.6),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    "复习 $cycle",
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // --- 音标播放区域 (hidden in manual pre-reveal) ---
          if (!hideDetails) _buildPhoneticSection(context, secondaryTextColor),

          // --- 手动模式下未揭晓时的提示 ---
          if (hideDetails)
            Container(
              margin: const EdgeInsets.only(top: 50),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.touch_app, size: 48, color: Colors.grey.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text("点击屏幕任意位置显示释义发音", style: TextStyle(color: Colors.grey.withOpacity(0.8), fontSize: 16, letterSpacing: 1.2)),
                ],
              ),
            ),

          // --- 单词释义卡片 ---
          if (showDetail && !hideDetails)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBackgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 1.5),
                // 移除廉价的阴影，改用细腻的描边，符合现代黑暗模式审美
              ),
              child: Text(
                word?.means?.join("\n") ?? "",
                style: TextStyle(
                  color: meaningTextColor,
                  fontSize: 17,
                  height: 1.6,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),

          // --- 例句展示区域 ---
          if (showDetail && !hideDetails)
            Container(
              margin: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => playSentenceSound(
                      word?.sentence ?? "",
                      cacheName: word?.wordId ?? word?.word,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: WordSentence(
                        sentence: word?.sentence,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  WordSentence(
                    sentence: word?.sentenceMeans,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 构建音标行的私有组件
  Widget _buildPhoneticSection(BuildContext context, Color textColor) {
    return InkWell(
      onTap: () => playWordSound(word?.word, ukVoice ? 1 : 2),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.volume_up_rounded,
              color: textColor,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              ukVoice ? "英 " : "美 ",
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            MaxWidthText(
              text: "[${ukVoice ? word?.ukVoice : word?.usaVoice}]",
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                color: textColor,
                fontFamily: 'monospace', // 使用等宽字体显示音标更专业
              ),
              maxWidth: 250,
            ),
          ],
        ),
      ),
    );
  }
}