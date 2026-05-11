import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String? _bgImagePath;
  bool _assetsLoaded = false;

  @override
  void initState() {
    super.initState();
    _initSplash();
  }

  void _initSplash() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      final loadingPics = manifestMap.keys.where((path) => path.startsWith('assets/loading_pic/')).toList();

      if (loadingPics.isNotEmpty) {
        final random = Random();
        setState(() {
          _bgImagePath = loadingPics[random.nextInt(loadingPics.length)];
        });
      }
    } catch (e) {
      // 图片加载失败不阻塞
    }

    setState(() {
      _assetsLoaded = true;
    });

    await Future.delayed(const Duration(seconds: 3));

    Get.offAllNamed('/main');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_bgImagePath != null)
            Image.asset(_bgImagePath!, fit: BoxFit.cover),

          Container(color: Colors.black.withOpacity(0.6)),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1800),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 15 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: const Text(
                    "Wordie,",
                    style: TextStyle(
                      fontFamily: 'EnglishCursive',
                      fontSize: 90,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.white30, blurRadius: 20)],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 2000),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    double opacity = (value - 0.3) / 0.7;
                    if (opacity < 0) opacity = 0;
                    return Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: Offset(0, 15 * (1 - opacity)),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      const Text(
                        "坚持，",
                        style: TextStyle(
                          fontFamily: 'CalligraphyFont',
                          fontSize: 34,
                          color: Colors.white,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "自见曙光！",
                        style: TextStyle(
                          fontFamily: 'CalligraphyFont',
                          fontSize: 44,
                          color: const Color(0xFFE67E22),
                          letterSpacing: 10,
                          shadows: [
                            const Shadow(color: Colors.black, offset: Offset(2, 2)),
                            Shadow(color: const Color(0xFFE67E22).withOpacity(0.5), blurRadius: 25),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_assetsLoaded)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Container(width: 60, height: 1, color: Colors.white24, margin: const EdgeInsets.only(bottom: 10)),
                  const Text(
                    "STAY SHARP · WORDIE",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white30,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
