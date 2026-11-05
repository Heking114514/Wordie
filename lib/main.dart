// lib/main.dart
import 'dart:io';
import 'package:english/controller/app/app.dart';
import 'package:english/route/routes.dart';
import 'package:english/service/app/app.dart';
import 'package:english/service/word/word.dart';
import 'package:english/util/assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'dao/floor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await GetStorage.init();

  var databasesPath = await getDatabasesPath();
  String path = "$databasesPath/english15.db";
  var dbDir = Directory(databasesPath);
  if (!dbDir.existsSync()) {
    dbDir.createSync(recursive: true);
  }

  final databaseFile = File(path);
  final wasMissing = !databaseFile.existsSync();
  if (wasMissing || await databaseFile.length() < 100000) {
    await releaseAssetsToFile("assets/dict.db1", databaseFile);
  }

  var appDatabase =
      await $FloorAppDatabase.databaseBuilder("english15.db").build();
  Get.put(appDatabase);
  final db = appDatabase.database;

  // 自动迁移旧版进度数据（使用极其高效的 JOIN 查询，避免应用假死）
  try {
    var legacyRows = await db
        .rawQuery("SELECT id FROM word_status WHERE INSTR(word, '_') = 0");
    if (legacyRows.isNotEmpty) {
      await db.execute('''
        INSERT INTO word_status (word, status, studyCycle, nextReviewTime, createTime, updateTime)
        SELECT w.book || '_' || s.word, s.status, s.studyCycle,
               s.nextReviewTime, s.createTime, s.updateTime
        FROM word_status s
        INNER JOIN word w ON w.word = s.word
        WHERE INSTR(s.word, '_') = 0
          AND NOT EXISTS (
            SELECT 1 FROM word_status target
            WHERE target.word = w.book || '_' || s.word
          )
        GROUP BY s.id, w.book
      ''');
      await db.rawDelete('''
        DELETE FROM word_status
        WHERE INSTR(word, '_') = 0
          AND EXISTS (SELECT 1 FROM word w WHERE w.word = word_status.word)
      ''');
    }
  } catch (e) {
    print('Migration error: $e');
  }

  Get.put(appDatabase.wordDao);
  Get.put(WordService());
  Get.put(AppService());
  Get.put(AppController());

  runApp(const MyApp());
}

class NoBounceScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isDark = GetStorage().read('dark_mode') == true;

    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      getPages: pages,
      scrollBehavior: NoBounceScrollBehavior(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          backgroundColor: Color(0xFFF8FAFC),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
              color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle.light,
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
