import 'dart:io';

import 'package:english/service/update/update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compares release tags with current Android versions', () {
    expect(UpdateService.compareVersions('v2.2.0', '2.1.1'), greaterThan(0));
    expect(UpdateService.compareVersions('2.2.0', 'v2.2.0'), 0);
    expect(UpdateService.compareVersions('v2.1.9', '2.2.0'), lessThan(0));
    expect(UpdateService.isVersionValid('2.2.0+23'), isTrue);
  });

  test('parses APK asset from GitHub release response', () {
    final release = UpdateRelease.fromGitHubJson(<String, dynamic>{
      'tag_name': 'v2.2.0',
      'body': 'update notes',
      'assets': <dynamic>[
        <String, dynamic>{
          'name': 'notes.txt',
          'browser_download_url':
              'https://github.com/Heking114514/Wordie/releases/download/v2.2.0/notes.txt',
          'size': 12,
        },
        <String, dynamic>{
          'name': 'Wordie-2.2.0-release.apk',
          'browser_download_url':
              'https://github.com/Heking114514/Wordie/releases/download/v2.2.0/Wordie-2.2.0-release.apk',
          'size': 123456,
          'digest':
              'sha256:d9c0fc72f958c7353d10de2ec03997f8753ef1e69e229c6258ca3026c8c36d7b',
        },
      ],
    });

    expect(release.tagName, 'v2.2.0');
    expect(release.apkAssetName, 'Wordie-2.2.0-release.apk');
    expect(release.apkSize, 123456);
    expect(release.apkSha256,
        'd9c0fc72f958c7353d10de2ec03997f8753ef1e69e229c6258ca3026c8c36d7b');
    expect(release.apkUrl, endsWith('.apk'));
  });

  test('rejects release without an APK asset', () {
    expect(
      () => UpdateRelease.fromGitHubJson(<String, dynamic>{
        'tag_name': 'v2.2.0',
        'assets': <dynamic>[],
      }),
      throwsA(isA<UpdateException>()),
    );
  });

  testWidgets('installApk sends the absolute path to Android', (tester) async {
    const channel = MethodChannel(UpdateService.updateChannelName);
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final apk = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}updates'
      '${Platform.pathSeparator}Wordie-update-v2.2.0.apk',
    );
    await UpdateService(channel: channel).installApk(apk);

    expect(received?.method, 'installApk');
    expect(
      (received?.arguments as Map<dynamic, dynamic>)['path'],
      apk.absolute.path,
    );
  });
}
