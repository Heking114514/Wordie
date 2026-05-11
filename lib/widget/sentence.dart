import 'package:flutter/material.dart';

class WordSentence extends StatelessWidget {
  final String? sentence;
  final bool? showVoice;

  const WordSentence({
    Key? key,
    this.sentence,
    this.showVoice,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 动态获取当前主题
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // 根据主题动态配置颜色（拒绝硬编码）
    final Color normalTextColor = isDark ? Colors.white70 : Colors.black54;
    final Color highlightTextColor = isDark ? Colors.white : Colors.black;
    final Color iconColor = isDark ? const Color(0xFF818CF8) : Colors.grey;

    var example = sentence ?? "";
    var spans = <InlineSpan>[];

    // 处理发音图标逻辑
    if (showVoice == true) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Icon(
            Icons.volume_up_rounded,
            size: 22,
            color: iconColor,
          ),
        ),
      ));
    }

    var pos = 0;
    // 使用循环精准拆分 <b> 标签
    for (;;) {
      var wordStart = example.indexOf("<b>", pos);
      if (wordStart == -1) break;
      var wordEnd = example.indexOf("</b>", wordStart);
      if (wordEnd == -1) break;

      // 添加普通文本部分
      if (wordStart > pos) {
        spans.add(TextSpan(
          text: example.substring(pos, wordStart),
          style: TextStyle(
            color: normalTextColor,
            fontSize: 16,
            height: 1.5,
          ),
        ));
      }

      // 添加 <b> 加粗高亮部分
      var wordStr = example.substring(wordStart + 3, wordEnd);
      spans.add(TextSpan(
        text: wordStr,
        style: TextStyle(
          color: highlightTextColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          height: 1.5,
          // 黑暗模式下稍微加一点外发光或者下划线增加辨识度 (可选)
          decoration: isDark ? TextDecoration.underline : TextDecoration.none,
          decorationColor: _getSecondaryAccent(isDark).withOpacity(0.5),
        ),
      ));

      pos = wordEnd + 4;
    }

    // 添加剩余的文本部分
    if (pos < example.length) {
      spans.add(TextSpan(
        text: example.substring(pos),
        style: TextStyle(
          color: normalTextColor,
          fontSize: 16,
          height: 1.5,
        ),
      ));
    }

    // 返回布局
    return Container(
      width: double.infinity,
      child: RichText(
        text: TextSpan(
          children: spans,
        ),
      ),
    );
  }

  // 内部辅助颜色获取
  Color _getSecondaryAccent(bool isDark) => isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
}