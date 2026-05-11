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
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown
  ]);

  await GetStorage.init();

  var databasesPath = await getDatabasesPath();
  String path = "$databasesPath/english.db";
  var dbDir = Directory(databasesPath);
  if (!dbDir.existsSync()) {
    dbDir.createSync(recursive: true);
  }

  if (!File(path).existsSync() || await File(path).length() < 100000) {
    await releaseAssetsToFile("assets/dict.db1", File(path));
  }

  var appDatabase = await $FloorAppDatabase.databaseBuilder("english.db").build();

  Get.put(appDatabase);
  Get.put(appDatabase.wordDao);
  Get.put(WordService());
  Get.put(AppService());
  Get.put(AppController());

  runApp(const MyApp());
}

class NoBounceScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
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
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
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
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
