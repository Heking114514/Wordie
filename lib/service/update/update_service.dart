import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum UpdateFailureType {
  network,
  rateLimited,
  invalidRelease,
  platform,
  download,
  install,
}

class UpdateException implements Exception {
  final UpdateFailureType type;
  final String message;

  const UpdateException(this.type, this.message);

  @override
  String toString() => message;
}

class UpdateRelease {
  final String tagName;
  final String body;
  final String apkUrl;
  final String apkAssetName;
  final int apkSize;
  final String apkSha256;

  const UpdateRelease({
    required this.tagName,
    required this.body,
    required this.apkUrl,
    required this.apkAssetName,
    required this.apkSize,
    this.apkSha256 = '',
  });

  factory UpdateRelease.fromGitHubJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] ?? '').toString().trim();
    if (tagName.isEmpty) {
      throw const UpdateException(
        UpdateFailureType.invalidRelease,
        'GitHub Release 缺少版本标签。',
      );
    }

    final assets = json['assets'];
    if (assets is! List) {
      throw const UpdateException(
        UpdateFailureType.invalidRelease,
        'GitHub Release 缺少附件列表。',
      );
    }

    Map<String, dynamic>? apkAsset;
    for (final rawAsset in assets) {
      if (rawAsset is! Map) continue;
      final asset = Map<String, dynamic>.from(rawAsset);
      final assetName = (asset['name'] ?? '').toString();
      final downloadUrl =
          (asset['browser_download_url'] ?? '').toString().trim();
      final pathWithoutQuery =
          Uri.tryParse(downloadUrl)?.path.toLowerCase() ?? '';
      if (assetName.toLowerCase().endsWith('.apk') ||
          pathWithoutQuery.endsWith('.apk')) {
        apkAsset = asset;
        break;
      }
    }

    if (apkAsset == null) {
      throw const UpdateException(
        UpdateFailureType.invalidRelease,
        '最新版本中没有可下载的 APK 文件。',
      );
    }

    final apkUrl = (apkAsset['browser_download_url'] ?? '').toString().trim();
    final apkAssetName =
        (apkAsset['name'] ?? 'Wordie-update.apk').toString().trim();
    if (apkUrl.isEmpty) {
      throw const UpdateException(
        UpdateFailureType.invalidRelease,
        'APK 下载地址为空。',
      );
    }

    final rawSize = apkAsset['size'];
    final apkSize =
        rawSize is num ? rawSize.toInt() : int.tryParse('$rawSize') ?? 0;
    final rawDigest = (apkAsset['digest'] ?? '').toString().trim();
    final apkSha256 = rawDigest.toLowerCase().startsWith('sha256:')
        ? rawDigest.substring(7).toLowerCase()
        : '';

    return UpdateRelease(
      tagName: tagName,
      body: (json['body'] ?? '').toString().trim(),
      apkUrl: apkUrl,
      apkAssetName: apkAssetName.isEmpty ? 'Wordie-update.apk' : apkAssetName,
      apkSize: apkSize,
      apkSha256: RegExp(r'^[a-f0-9]{64}$').hasMatch(apkSha256) ? apkSha256 : '',
    );
  }
}

class UpdateCheckResult {
  final String currentVersion;
  final UpdateRelease latestRelease;
  final bool hasUpdate;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestRelease,
    required this.hasUpdate,
  });
}

typedef UpdateDownloadProgress = void Function(
  int received,
  int total,
  double progress,
);

class UpdateService {
  static const String updateChannelName = 'com.wordie.english15.coexist/update';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/Heking114514/Wordie/releases/latest';
  static const String userAgent = 'Wordie-Android';

  final Dio _dio;
  final MethodChannel _channel;

  UpdateService({Dio? dio, MethodChannel? channel})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: 15000,
                sendTimeout: 15000,
                receiveTimeout: 60000,
                headers: const <String, dynamic>{
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': userAgent,
                },
              ),
            ),
        _channel = channel ?? const MethodChannel(updateChannelName);

  Future<String> getCurrentVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getVersionName');
      final normalized = version?.trim() ?? '';
      if (normalized.isEmpty) {
        throw const UpdateException(
          UpdateFailureType.platform,
          'Android 未返回当前版本号。',
        );
      }
      return normalized;
    } on PlatformException catch (error) {
      throw UpdateException(
        UpdateFailureType.platform,
        error.message ?? '读取当前版本失败。',
      );
    } on MissingPluginException {
      throw const UpdateException(
        UpdateFailureType.platform,
        '当前平台未接入 Android 更新通道。',
      );
    }
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    final currentVersion = await getCurrentVersion();
    if (!isVersionValid(currentVersion)) {
      throw UpdateException(
        UpdateFailureType.platform,
        '当前版本号格式无效：$currentVersion',
      );
    }

    final release = await fetchLatestRelease();
    if (!isVersionValid(release.tagName)) {
      throw UpdateException(
        UpdateFailureType.invalidRelease,
        '最新版本标签格式无效：${release.tagName}',
      );
    }

    return UpdateCheckResult(
      currentVersion: currentVersion,
      latestRelease: release,
      hasUpdate: compareVersions(release.tagName, currentVersion) > 0,
    );
  }

  Future<UpdateRelease> fetchLatestRelease() async {
    try {
      final response = await _dio.get<dynamic>(
        latestReleaseUrl,
        options: Options(
          headers: const <String, dynamic>{
            'Accept': 'application/vnd.github+json',
            'User-Agent': userAgent,
          },
        ),
      );
      final data = response.data;
      if (data is! Map) {
        throw const UpdateException(
          UpdateFailureType.invalidRelease,
          'GitHub 返回了无法识别的版本信息。',
        );
      }
      return UpdateRelease.fromGitHubJson(
        Map<String, dynamic>.from(data),
      );
    } on DioError catch (error) {
      throw _mapDioError(error);
    }
  }

  Future<File> downloadRelease(
    UpdateRelease release, {
    UpdateDownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final updatesDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}updates',
    );
    if (!await updatesDirectory.exists()) {
      await updatesDirectory.create(recursive: true);
    }

    final safeTag = release.tagName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = File(
      '${updatesDirectory.path}${Platform.pathSeparator}'
      'Wordie-update-$safeTag.apk',
    );
    if (await target.exists()) {
      await target.delete();
    }

    try {
      await _dio.download(
        release.apkUrl,
        target.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        options: Options(
          headers: const <String, dynamic>{
            'Accept': 'application/octet-stream',
            'User-Agent': userAgent,
          },
        ),
        onReceiveProgress: (received, total) {
          final expectedTotal = total > 0 ? total : release.apkSize;
          final progress = expectedTotal > 0
              ? (received / expectedTotal).clamp(0.0, 1.0).toDouble()
              : 0.0;
          onProgress?.call(received, expectedTotal, progress);
        },
      );
    } on DioError catch (error) {
      throw _mapDioError(error, downloading: true);
    }

    if (!await target.exists()) {
      throw const UpdateException(
        UpdateFailureType.download,
        'APK 下载完成后未找到文件。',
      );
    }

    final downloadedSize = await target.length();
    if (downloadedSize <= 0) {
      await target.delete();
      throw const UpdateException(
        UpdateFailureType.download,
        'APK 文件为空，请重试。',
      );
    }
    if (release.apkSize > 0 && downloadedSize != release.apkSize) {
      await target.delete();
      throw UpdateException(
        UpdateFailureType.download,
        'APK 文件大小校验失败：预期 ${release.apkSize} 字节，'
        '实际 $downloadedSize 字节。',
      );
    }
    if (release.apkSha256.isNotEmpty) {
      final actualDigest =
          (await sha256.bind(target.openRead()).first).toString();
      if (actualDigest != release.apkSha256) {
        await target.delete();
        throw const UpdateException(
          UpdateFailureType.download,
          'APK 安全摘要校验失败，请重新下载。',
        );
      }
    }

    return target;
  }

  Future<void> installApk(File apk) async {
    try {
      final launched = await _channel.invokeMethod<bool>(
        'installApk',
        <String, dynamic>{'path': apk.absolute.path},
      );
      if (launched != true) {
        throw const UpdateException(
          UpdateFailureType.install,
          'Android 安装器未能启动。',
        );
      }
    } on PlatformException catch (error) {
      throw UpdateException(
        UpdateFailureType.install,
        error.message ?? 'Android 安装器启动失败。',
      );
    } on MissingPluginException {
      throw const UpdateException(
        UpdateFailureType.platform,
        '当前平台未接入 Android 更新通道。',
      );
    }
  }

  static bool isVersionValid(String version) {
    return _parseVersion(version)?.core.any((part) => part > 0) ?? false;
  }

  /// Returns a positive value when [left] is newer than [right].
  static int compareVersions(String left, String right) {
    final leftVersion = _parseVersion(left);
    final rightVersion = _parseVersion(right);
    if (leftVersion == null || rightVersion == null) {
      throw const FormatException('版本号格式无效');
    }

    final maxCoreLength = leftVersion.core.length > rightVersion.core.length
        ? leftVersion.core.length
        : rightVersion.core.length;
    for (var index = 0; index < maxCoreLength; index++) {
      final leftPart =
          index < leftVersion.core.length ? leftVersion.core[index] : 0;
      final rightPart =
          index < rightVersion.core.length ? rightVersion.core[index] : 0;
      if (leftPart != rightPart) return leftPart.compareTo(rightPart);
    }

    final leftPreRelease = leftVersion.preRelease;
    final rightPreRelease = rightVersion.preRelease;
    if (leftPreRelease.isEmpty && rightPreRelease.isEmpty) return 0;
    if (leftPreRelease.isEmpty) return 1;
    if (rightPreRelease.isEmpty) return -1;

    final maxPreReleaseLength = leftPreRelease.length > rightPreRelease.length
        ? leftPreRelease.length
        : rightPreRelease.length;
    for (var index = 0; index < maxPreReleaseLength; index++) {
      if (index >= leftPreRelease.length) return -1;
      if (index >= rightPreRelease.length) return 1;
      final leftIdentifier = leftPreRelease[index];
      final rightIdentifier = rightPreRelease[index];
      final leftNumber = int.tryParse(leftIdentifier);
      final rightNumber = int.tryParse(rightIdentifier);
      if (leftNumber != null && rightNumber != null) {
        final comparison = leftNumber.compareTo(rightNumber);
        if (comparison != 0) return comparison;
      } else if (leftNumber != null) {
        return -1;
      } else if (rightNumber != null) {
        return 1;
      } else {
        final comparison = leftIdentifier.compareTo(rightIdentifier);
        if (comparison != 0) return comparison;
      }
    }
    return 0;
  }

  static _ParsedVersion? _parseVersion(String version) {
    var normalized = version.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    normalized = normalized.split('+').first;
    final separatorIndex = normalized.indexOf('-');
    final coreText = separatorIndex >= 0
        ? normalized.substring(0, separatorIndex)
        : normalized;
    final preReleaseText =
        separatorIndex >= 0 ? normalized.substring(separatorIndex + 1) : '';
    if (coreText.isEmpty) return null;

    final core = <int>[];
    for (final segment in coreText.split('.')) {
      final match = RegExp(r'^\d+').firstMatch(segment);
      if (match == null) return null;
      core.add(int.parse(match.group(0)!));
    }
    final preRelease = preReleaseText.isEmpty
        ? const <String>[]
        : preReleaseText.split('.').where((part) => part.isNotEmpty).toList();
    return _ParsedVersion(core, preRelease);
  }

  UpdateException _mapDioError(DioError error, {bool downloading = false}) {
    final response = error.response;
    final statusCode = response?.statusCode;
    final remaining = response?.headers.value('x-ratelimit-remaining')?.trim();
    if (statusCode == 403 ||
        statusCode == 429 ||
        (remaining != null && int.tryParse(remaining) == 0)) {
      return const UpdateException(
        UpdateFailureType.rateLimited,
        'GitHub API 请求次数已达上限，请稍后再试。',
      );
    }
    if (statusCode == 404) {
      return const UpdateException(
        UpdateFailureType.invalidRelease,
        '未找到 GitHub 最新版本发布信息。',
      );
    }
    if (downloading && statusCode != null) {
      return UpdateException(
        UpdateFailureType.download,
        'APK 下载失败（HTTP $statusCode）。',
      );
    }
    if (statusCode != null) {
      return UpdateException(
        UpdateFailureType.network,
        'GitHub 请求失败（HTTP $statusCode）。',
      );
    }
    return UpdateException(
      downloading ? UpdateFailureType.download : UpdateFailureType.network,
      downloading ? 'APK 下载失败，请检查网络后重试。' : '检查更新失败，请检查网络后重试。',
    );
  }
}

class _ParsedVersion {
  final List<int> core;
  final List<String> preRelease;

  const _ParsedVersion(this.core, this.preRelease);
}
