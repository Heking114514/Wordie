// 【文件路径】: lib/util/quotes.dart
import 'dart:math';

final List<String> motivationalQuotes =[
  "坚持就是胜利！",
  "每天进步一点点。",
  "不积跬步，无以至千里。",
  "越努力，越幸运。",
  "Action speaks louder than words.",
  "Where there is a will, there is a way.",
  "既然选择了远方，便只顾风雨兼程。",
  "星光不问赶路人，时光不负有心人。",
  "宝剑锋从磨砺出，梅花香自苦寒来。",
  "种一棵树最好的时间是十年前，其次是现在。"
];

String getRandomQuote() {
  final random = Random();
  return motivationalQuotes[random.nextInt(motivationalQuotes.length)];
}