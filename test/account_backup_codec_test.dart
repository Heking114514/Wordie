import 'dart:convert';

import 'package:english/dao/word/word.dart';
import 'package:english/service/backup/account_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account snapshot survives encryption round trip', () async {
    final backup = AccountBackup(wordDao: _FakeWordDao());
    final snapshot = <String, dynamic>{
      'format': 'wordie-account-backup',
      'version': 1,
      'createdAt': '2026-11-05T00:00:00Z',
      'settings': <String, dynamic>{
        'profile_name': '跨设备用户',
        'custom_books': <String, dynamic>{
          '核心词库': <String>['accessory', 'accord'],
        },
        'dark_mode': true,
      },
      'tables': <String, dynamic>{
        'word': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'book': '9001', 'word': 'accessory'},
        ],
        'word_status': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'word': '9001_accessory',
            'status': 1,
            'studyCycle': 2,
          },
        ],
        'study_time_count': <Map<String, dynamic>>[],
        'word_study_time_count': <Map<String, dynamic>>[],
      },
    };

    final encoded = await backup.encodeSnapshot(snapshot);
    final envelope = jsonDecode(encoded) as Map<String, dynamic>;
    expect(envelope['format'], 'wordie-account-backup');
    expect(envelope.containsKey('ciphertext'), isTrue);
    expect(encoded.contains('跨设备用户'), isFalse);

    final decoded = await backup.decodeSnapshot(encoded);
    expect(decoded, snapshot);
  });

  test('tampered ciphertext fails authentication', () async {
    final backup = AccountBackup(wordDao: _FakeWordDao());
    final encoded = await backup.encodeSnapshot(<String, dynamic>{
      'format': 'wordie-account-backup',
      'version': 1,
      'settings': <String, dynamic>{},
      'tables': <String, dynamic>{},
    });
    final envelope = jsonDecode(encoded) as Map<String, dynamic>;
    final ciphertext = base64Decode(envelope['ciphertext'] as String);
    ciphertext[0] ^= 1;
    envelope['ciphertext'] = base64Encode(ciphertext);

    expect(
      () => backup.decodeSnapshot(jsonEncode(envelope)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('校验失败'),
        ),
      ),
    );
  });

  test('wrong backup format is rejected before decryption', () async {
    final backup = AccountBackup(wordDao: _FakeWordDao());
    expect(
      () => backup.decodeSnapshot('{"format":"other","version":1}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('xchacha nonce is unique per export', () async {
    final backup = AccountBackup(wordDao: _FakeWordDao());
    final snapshot = <String, dynamic>{
      'format': 'wordie-account-backup',
      'version': 1,
      'settings': <String, dynamic>{},
      'tables': <String, dynamic>{},
    };
    final first = jsonDecode(await backup.encodeSnapshot(snapshot)) as Map;
    final second = jsonDecode(await backup.encodeSnapshot(snapshot)) as Map;
    expect(first['nonce'], isNot(second['nonce']));
    expect(first['key'], isNot(second['key']));
  });
}

class _FakeWordDao implements WordDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
