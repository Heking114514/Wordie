import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../service/update/update_service.dart';

class UpdateController extends GetxController {
  static const String autoCheckStorageKey = 'auto_check_update';
  static const Duration startupCheckDelay = Duration(seconds: 4);

  final UpdateService updateService;
  final GetStorage _storage;

  final RxBool autoCheckUpdate = true.obs;
  final RxBool isChecking = false.obs;
  final RxBool isDownloading = false.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxString currentVersion = ''.obs;
  final RxString checkStatus = '尚未检查'.obs;
  final Rxn<UpdateRelease> availableRelease = Rxn<UpdateRelease>();

  bool _startupCheckScheduled = false;

  UpdateController({
    UpdateService? updateService,
    GetStorage? storage,
  })  : updateService = updateService ?? UpdateService(),
        _storage = storage ?? GetStorage();

  @override
  void onInit() {
    super.onInit();
    final storedValue = _storage.read(autoCheckStorageKey);
    autoCheckUpdate.value = storedValue is bool ? storedValue : true;
    unawaited(refreshCurrentVersion());
  }

  String get currentVersionLabel {
    if (currentVersion.value.isEmpty) return '正在读取当前版本';
    final version = currentVersion.value.trim();
    return version.toLowerCase().startsWith('v')
        ? '当前 $version'
        : '当前 v$version';
  }

  Future<void> setAutoCheckUpdate(bool enabled) async {
    autoCheckUpdate.value = enabled;
    await _storage.write(autoCheckStorageKey, enabled);
  }

  Future<void> refreshCurrentVersion() async {
    try {
      currentVersion.value = await updateService.getCurrentVersion();
      if (checkStatus.value == '尚未检查') {
        checkStatus.value = '可手动检查';
      }
    } catch (error) {
      if (currentVersion.value.isEmpty) {
        checkStatus.value = '当前版本读取失败';
      }
    }
  }

  /// Called once by the app bootstrap. Failures stay silent in this mode.
  Future<void> checkOnStartup() async {
    if (_startupCheckScheduled) return;
    _startupCheckScheduled = true;
    await Future<void>.delayed(startupCheckDelay);
    if (!autoCheckUpdate.value) return;
    await _checkForUpdate(manual: false);
  }

  /// Manual checks always run, even when automatic checking is disabled.
  Future<void> checkAndPrompt() => _checkForUpdate(manual: true);

  Future<void> _checkForUpdate({required bool manual}) async {
    if (isChecking.value || isDownloading.value) {
      if (manual) {
        Get.snackbar(
          '请稍候',
          isDownloading.value ? '当前正在准备安装包。' : '正在检查更新。',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return;
    }

    isChecking.value = true;
    checkStatus.value = manual ? '正在检查更新...' : '后台检查更新中...';
    try {
      final result = await updateService.checkForUpdate();
      currentVersion.value = result.currentVersion;
      if (!result.hasUpdate) {
        availableRelease.value = null;
        checkStatus.value = '已是最新版本';
        if (manual) {
          Get.snackbar(
            '已是最新版本',
            '当前版本 ${result.currentVersion}',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return;
      }

      availableRelease.value = result.latestRelease;
      checkStatus.value = '发现新版本 ${result.latestRelease.tagName}';
      await _showUpdateDialog(result);
    } on UpdateException catch (error) {
      checkStatus.value = _failureStatus(error);
      if (manual) {
        Get.snackbar(
          _failureTitle(error),
          error.message,
          duration: const Duration(seconds: 6),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (_) {
      checkStatus.value = '检查更新失败';
      if (manual) {
        Get.snackbar(
          '检查更新失败',
          '检查更新时发生异常，请稍后重试。',
          duration: const Duration(seconds: 6),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> _showUpdateDialog(UpdateCheckResult result) async {
    final release = result.latestRelease;
    final shouldDownload = await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text('发现新版本 ${release.tagName}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前版本：${result.currentVersion}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  '版本说明',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  release.body.isEmpty ? '该版本暂无更新说明。' : release.body,
                  style: const TextStyle(fontSize: 14, height: 1.55),
                ),
                if (release.apkSize > 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    '安装包大小：${_formatBytes(release.apkSize)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('下载并安装'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (shouldDownload == true) {
      await downloadAndInstall(release);
    }
  }

  Future<void> downloadAndInstall(UpdateRelease release) async {
    if (isDownloading.value) return;

    isDownloading.value = true;
    downloadProgress.value = 0;
    checkStatus.value = '正在下载 ${release.tagName}...';
    var progressDialogOpen = false;
    try {
      Get.dialog<void>(
        WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text('正在下载 ${release.tagName}'),
            content: Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: downloadProgress.value,
                    minHeight: 7,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${(downloadProgress.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        barrierDismissible: false,
      );
      progressDialogOpen = true;

      final apk = await updateService.downloadRelease(
        release,
        onProgress: (received, total, progress) {
          downloadProgress.value = progress;
        },
      );
      downloadProgress.value = 1;
      checkStatus.value = '下载完成，正在打开安装器...';

      if (progressDialogOpen && Get.isDialogOpen == true) {
        Get.back();
        progressDialogOpen = false;
      }

      await updateService.installApk(apk);
      checkStatus.value = '已打开系统安装器';
      Get.snackbar(
        '准备安装',
        '请在系统安装界面确认更新。',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on UpdateException catch (error) {
      if (progressDialogOpen && Get.isDialogOpen == true) {
        Get.back();
      }
      checkStatus.value = _failureStatus(error);
      Get.snackbar(
        _failureTitle(error),
        error.message,
        duration: const Duration(seconds: 7),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (progressDialogOpen && Get.isDialogOpen == true) {
        Get.back();
      }
      checkStatus.value = '下载或安装准备失败';
      Get.snackbar(
        '更新失败',
        '下载或安装准备过程中发生异常，请稍后重试。',
        duration: const Duration(seconds: 7),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isDownloading.value = false;
    }
  }

  String _failureStatus(UpdateException error) {
    switch (error.type) {
      case UpdateFailureType.rateLimited:
        return 'GitHub 请求受限';
      case UpdateFailureType.network:
        return '网络连接失败';
      case UpdateFailureType.invalidRelease:
        return '版本信息无效';
      case UpdateFailureType.platform:
        return '版本读取失败';
      case UpdateFailureType.download:
        return 'APK 下载失败';
      case UpdateFailureType.install:
        return '安装器启动失败';
    }
  }

  String _failureTitle(UpdateException error) {
    switch (error.type) {
      case UpdateFailureType.rateLimited:
        return '请求受限';
      case UpdateFailureType.network:
        return '网络错误';
      case UpdateFailureType.invalidRelease:
        return '版本信息异常';
      case UpdateFailureType.platform:
        return '平台错误';
      case UpdateFailureType.download:
        return '下载失败';
      case UpdateFailureType.install:
        return '安装失败';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
