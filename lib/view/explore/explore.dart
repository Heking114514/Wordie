import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/explore/explore.dart';

class ExplorePage extends GetView<ExploreController> {
  const ExplorePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 25, bottom: 20),
              child: Text("探索新知", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B))),
            ),
            _buildSearchBar(isDark),
            Expanded(
              child: Obx(() {
                if (controller.searchResult.isEmpty && controller.searchInput.text.isEmpty) {
                  return _buildSystemBooksGrid(isDark);
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 15, offset: const Offset(0, 4))]
      ),
      child: TextField(
        controller: controller.searchInput,
        onChanged: controller.search,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          icon: Icon(Icons.search, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8)), 
          hintText: "搜索英文单词以加入生词本...", 
          hintStyle: TextStyle(color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8), fontSize: 15),
          border: InputBorder.none
        ),
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
          child: Text("热门系统词书", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B))),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.15),
            itemCount: books.length,
            itemBuilder: (context, index) => _buildCategoryCard(books[index], isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(String name, bool isDark) {
    IconData iconData = Icons.menu_book;
    if (name.contains("小学") || name.contains("初中") || name.contains("高中")) iconData = Icons.school;
    else if (name.contains("四级") || name.contains("六级") || name.contains("考")) iconData = Icons.workspace_premium;
    else if (name.contains("雅思") || name.contains("托福") || name.contains("GRE")) iconData = Icons.public;
    else if (name.contains("MBA") || name.contains("BEC") || name.contains("职场")) iconData = Icons.work;

    var wordCount = controller.appService.wordService.bookMap[name]?.words?.length ?? 0;

    return InkWell(
      onTap: () => controller.selectSystemBook(name), 
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white, 
          borderRadius: BorderRadius.circular(24), 
          border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.black.withOpacity(0.03)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.02), blurRadius: 12, offset: const Offset(0, 4))]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50, height: 50, 
              decoration: BoxDecoration(color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(15)), 
              child: Icon(iconData, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1), size: 28)
            ),
            const SizedBox(height: 12),
            Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text("$wordCount 词汇", style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
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
      separatorBuilder: (context, index) => Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9), indent: 20, endIndent: 20),
      itemBuilder: (context, index) {
        var word = controller.searchResult[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(word.word ?? "", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : const Color(0xFF1E293B))),
          subtitle: Text(
            word.means?.join("；") ?? "", 
            maxLines: 1, 
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 13),
          ),
          trailing: IconButton(
            icon: Icon(Icons.add_circle, color: isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1)),
            onPressed: () => controller.addToCustomLibrary(word),
            tooltip: "加入生词本",
          ),
          onLongPress: () => controller.addToCustomLibrary(word),
        );
      },
    );
  }
}