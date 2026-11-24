import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/explore/explore.dart';
import '../../dicts/reader.dart';
import '../../entity/word/vo/word.dart';
import '../../util/audio.dart';
import '../../util/html_text.dart';
import '../../widget/sentence.dart';

class ExplorePage extends GetView<ExploreController> {
  const ExplorePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 25, bottom: 20),
              child: Text("探索新知",
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B))),
            ),
            _buildSearchBar(isDark),
            Expanded(
              child: Obx(() {
                if (controller.searchResult.isEmpty &&
                    controller.searchInput.text.isEmpty) {
                  return _buildSystemBooksGrid(isDark);
                }
                if (controller.searchResult.isEmpty &&
                    controller.isSearchingApi.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildSearchResults(isDark);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                blurRadius: 15,
                offset: const Offset(0, 4))
          ]),
      child: TextField(
        controller: controller.searchInput,
        onChanged: controller.search,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
            icon: Icon(Icons.search,
                color:
                    isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8)),
            hintText: "搜索英文单词以加入生词本...",
            hintStyle: TextStyle(
                color:
                    isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                fontSize: 15),
            border: InputBorder.none),
      ),
    );
  }

  Widget _buildSystemBooksGrid(bool isDark) {
    var books = controller.appService.wordService.systemBookNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Text("热门系统词书",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E293B))),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 1.15),
            itemCount: books.length,
            itemBuilder: (context, index) =>
                _buildCategoryCard(books[index], isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(String name, bool isDark) {
    IconData iconData = Icons.menu_book;
    if (name.contains("小学") || name.contains("初中") || name.contains("高中")) {
      iconData = Icons.school;
    } else if (name.contains("四级") ||
        name.contains("六级") ||
        name.contains("考")) {
      iconData = Icons.workspace_premium;
    } else if (name.contains("雅思") ||
        name.contains("托福") ||
        name.contains("GRE")) {
      iconData = Icons.public;
    } else if (name.contains("MBA") ||
        name.contains("BEC") ||
        name.contains("职场")) {
      iconData = Icons.work;
    }

    var wordCount =
        controller.appService.wordService.bookMap[name]?.words?.length ?? 0;

    return InkWell(
      onTap: () => controller.selectSystemBook(name),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : Colors.black.withOpacity(0.03)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.02),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(15)),
                child: Icon(iconData,
                    color: isDark
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF6366F1),
                    size: 28)),
            const SizedBox(height: 12),
            Text(name,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Obx(() => Text(
                  "${controller.validWordCounts[name] ?? wordCount} 词汇",
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 15, bottom: 30),
      physics: const BouncingScrollPhysics(),
      itemCount: controller.searchResult.length,
      separatorBuilder: (context, index) => Divider(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
          indent: 20,
          endIndent: 20),
      itemBuilder: (context, index) {
        var word = controller.searchResult[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(word.word ?? "",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isDark ? Colors.white : const Color(0xFF1E293B))),
          subtitle: Text(
            word.means?.join("；") ?? "",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color:
                    isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontSize: 13),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.add_circle,
                    color: isDark
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF6366F1)),
                onPressed: () => controller.addToCustomLibrary(word),
                tooltip: "加入生词本",
              ),
              Icon(
                Icons.chevron_right_rounded,
                color:
                    isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
              ),
            ],
          ),
          onTap: () => _showWordDetail(context, word),
          onLongPress: () => controller.addToCustomLibrary(word),
        );
      },
    );
  }

  void _showWordDetail(BuildContext context, WordVO word) {
    Get.bottomSheet(
      _ExploreWordDetailSheet(
        controller: controller,
        initialWord: word,
      ),
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
    );
  }
}

class _ExploreWordDetailSheet extends StatelessWidget {
  final ExploreController controller;
  final WordVO initialWord;

  const _ExploreWordDetailSheet({
    required this.controller,
    required this.initialWord,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);
    final accentColor =
        isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final titleColor =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final bodyColor =
        isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);
    final mutedColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final panelColor =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: borderColor),
        ),
        child: Obx(() {
          final currentWord = _latestWord(controller.searchResult, initialWord);
          final detail = controller.resolveWordDetail(currentWord);
          final meanings = _resolveMeans(detail, currentWord);
          final examples = _resolveExamples(detail, currentWord);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: mutedColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          onPressed: Get.back,
                          icon: Icon(Icons.close_rounded, color: mutedColor),
                          tooltip: "关闭详情",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.word ?? currentWord.word ?? "",
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_hasPronunciation(detail)) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (_voiceText(detail.ukVoice).isNotEmpty)
                              _PronunciationButton(
                                label: "英",
                                phonetic: _voiceText(detail.ukVoice),
                                iconColor: accentColor,
                                panelColor: panelColor,
                                borderColor: borderColor,
                                textColor: bodyColor,
                                onTap: () => playWordSound(detail.word, 1),
                              ),
                            if (_voiceText(detail.usVoice).isNotEmpty)
                              _PronunciationButton(
                                label: "美",
                                phonetic: _voiceText(detail.usVoice),
                                iconColor: accentColor,
                                panelColor: panelColor,
                                borderColor: borderColor,
                                textColor: bodyColor,
                                onTap: () => playWordSound(detail.word, 2),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      _SectionTitle(
                        icon: Icons.menu_book_rounded,
                        title: "释义",
                        color: accentColor,
                        textColor: titleColor,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: panelColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: meanings.isEmpty
                            ? Text(
                                "暂无释义",
                                style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 15,
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: meanings
                                    .map(
                                      (meaning) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              margin:
                                                  const EdgeInsets.only(top: 8),
                                              decoration: BoxDecoration(
                                                color: accentColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                meaning,
                                                style: TextStyle(
                                                  color: bodyColor,
                                                  fontSize: 16,
                                                  height: 1.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        icon: Icons.format_quote_rounded,
                        title: "例句",
                        color: accentColor,
                        textColor: titleColor,
                      ),
                      const SizedBox(height: 10),
                      if (examples.isEmpty)
                        Text(
                          "暂无例句",
                          style: TextStyle(color: mutedColor, fontSize: 15),
                        )
                      else
                        ...examples.map(
                          (example) => _ExampleCard(
                            example: example,
                            panelColor: panelColor,
                            borderColor: borderColor,
                            mutedColor: mutedColor,
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              controller.addToCustomLibrary(currentWord),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text("加入生词本"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Color textColor;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _PronunciationButton extends StatelessWidget {
  final String label;
  final String phonetic;
  final Color iconColor;
  final Color panelColor;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onTap;

  const _PronunciationButton({
    required this.label,
    required this.phonetic,
    required this.iconColor,
    required this.panelColor,
    required this.borderColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.volume_up_rounded, color: iconColor, size: 20),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                phonetic,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  final Sentence example;
  final Color panelColor;
  final Color borderColor;
  final Color mutedColor;

  const _ExampleCard({
    required this.example,
    required this.panelColor,
    required this.borderColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final sentence = cleanHtmlText(example.sentence ?? "", preserveBold: true);
    final translation = cleanHtmlText(example.sentenceCn ?? "");

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WordSentence(sentence: sentence),
          if (translation.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              translation,
              style: TextStyle(
                color: mutedColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

WordVO _latestWord(List<WordVO> words, WordVO initialWord) {
  for (final word in words) {
    if (word.word == initialWord.word) return word;
  }
  return initialWord;
}

List<String> _resolveMeans(Word detail, WordVO word) {
  final rawMeans = (detail.means != null && detail.means!.trim().isNotEmpty)
      ? detail.means
      : word.means?.join('\n');

  return (rawMeans ?? "")
      .split(RegExp(r'\r?\n'))
      .map((meaning) => cleanHtmlText(meaning).trim())
      .where((meaning) => meaning.isNotEmpty)
      .toList();
}

List<Sentence> _resolveExamples(Word detail, WordVO word) {
  final examples = (detail.sentences ?? [])
      .where(
        (example) =>
            (example.sentence?.trim().isNotEmpty ?? false) ||
            (example.sentenceCn?.trim().isNotEmpty ?? false),
      )
      .toList();

  if (examples.isEmpty &&
      ((word.sentence?.trim().isNotEmpty ?? false) ||
          (word.sentenceMeans?.trim().isNotEmpty ?? false))) {
    examples.add(
      Sentence(
        sentence: word.sentence,
        sentenceCn: word.sentenceMeans,
      ),
    );
  }
  return examples;
}

bool _hasPronunciation(Word word) {
  return _voiceText(word.ukVoice).isNotEmpty ||
      _voiceText(word.usVoice).isNotEmpty;
}

String _voiceText(String? voice) {
  final text = voice?.trim() ?? "";
  if (text.isEmpty) return "";
  if (text.startsWith('/') || text.startsWith('[')) return text;
  return '/$text/';
}
