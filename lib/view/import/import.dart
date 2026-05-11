// lib/view/import/import.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/import/import.dart';

class ImportPage extends GetView<ImportController> {
  const ImportPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text("导入新词", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFF407BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _buildManualCard(),
                _buildFileCard(),
                _buildPreviewCard(),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: _buildSubmitBtn(),
          )
        ],
      ),
    );
  }

  Widget _buildManualCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("手动添加单词", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1D2129))),
          const SizedBox(height: 18),
          const Text("英文单词", style: TextStyle(fontSize: 14, color: Color(0xFF6E7681))),
          const SizedBox(height: 8),
          TextField(
            controller: controller.textController,
            decoration: InputDecoration(
              hintText: "请输入英文单词",
              hintStyle: const TextStyle(color: Color(0xFFC9CDD4), fontSize: 15),
              fillColor: const Color(0xFFF9FAFD),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E6EB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF407BFF))),
            ),
            onSubmitted: (_) => controller.addSingleWord(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: controller.addSingleWord,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF0F4FF),
              foregroundColor: const Color(0xFF407BFF),
              elevation: 0,
              minimumSize: const Size(double.infinity, 45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("添加至列表", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          )
        ],
      ),
    );
  }

  Widget _buildFileCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("批量导入文本文件", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1D2129))),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: controller.pickAndReadTxt,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FF),
                borderRadius: BorderRadius.circular(14),
                // 使用实线，由于未要求引入新依赖这里用标准写法
                border: Border.all(color: const Color(0xFF407BFF), width: 1.5),
              ),
              child: Column(
                children: const [
                  Icon(Icons.description, size: 38, color: Color(0xFF407BFF)),
                  SizedBox(height: 10),
                  Text("点击上传 TXT 文件", style: TextStyle(fontSize: 15, color: Color(0xFF272E3B))),
                  SizedBox(height: 6),
                  Text("每行单个英文单词", style: TextStyle(fontSize: 12, color: Color(0xFF86909C))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Obx(() => controller.pendingWords.isEmpty 
      ? const SizedBox() 
      : Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))
            ]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("待导入列表 (${controller.pendingWords.length})", style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D2129))),
                  GestureDetector(
                    onTap: () => controller.pendingWords.clear(),
                    child: const Text("清空", style: TextStyle(fontSize: 13, color: Colors.redAccent)),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: controller.pendingWords.map((w) => Chip(
                  label: Text(w, style: const TextStyle(color: Color(0xFF407BFF))),
                  backgroundColor: const Color(0xFFF0F4FF),
                  side: BorderSide.none,
                )).toList(),
              ),
            ],
          ),
        ));
  }

  Widget _buildSubmitBtn() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF407BFF), Color(0xFF598BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF407BFF).withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          )
        ]
      ),
      child: ElevatedButton(
        onPressed: controller.confirmImport,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        child: const Text("确认导入词库", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
      ),
    );
  }
}