import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:english/dao/word/word.dart';
import 'package:english/entity/word/po/word.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

class AccountBackup {
  static const int formatVersion = 1;
  static const String fileExtension = 'wordiebackup';
  static const String _platformChannel = 'com.wordie.english15.coexist/files';

  final WordDao wordDao;
  final GetStorage? storage;

  AccountBackup({required this.wordDao, this.storage});

  Future<Map<String, dynamic>> createSnapshot() async {
    final box = storage ?? GetStorage();
    final allKeys = box.getKeys<Iterable<String>>().toList()..sort();
    allKeys.removeWhere(
      (key) => key == 'calendar_event_id' || key.startsWith('daily_word_'),
    );
    final settings = <String, dynamic>{};
    for (final key in allKeys) {
      settings[key] = _jsonValue(box.read<dynamic>(key));
    }

    final words = await wordDao.queryAdapter.queryList(
      'SELECT id, book, word FROM word ORDER BY book, word',
      mapper: _mapWord,
    );
    final statuses = await wordDao.queryWordStatusList();
    final studyTimes = await wordDao.queryAllStudyTimeRecords();
    final wordStudyTimes = await wordDao.queryAllWordStudyTimeRecords();

    return <String, dynamic>{
      'format': 'wordie-account-backup',
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings,
      'tables': <String, dynamic>{
        'word': words.map(_wordToJson).toList(),
        'word_status': statuses.map(_statusToJson).toList(),
        'study_time_count': studyTimes.map(_studyTimeToJson).toList(),
        'word_study_time_count':
            wordStudyTimes.map(_wordStudyTimeToJson).toList(),
      },
    };
  }

  Future<String> encodeSnapshot(Map<String, dynamic> snapshot) async {
    final plainBytes = utf8.encode(jsonEncode(snapshot));
    final algorithm = Xchacha20.poly1305Aead();
    final secretKey = await algorithm.newSecretKey();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    final keyBytes = await secretKey.extractBytes();

    final envelope = <String, dynamic>{
      'format': 'wordie-account-backup',
      'version': formatVersion,
      'algorithm': 'xchacha20-poly1305',
      'key': base64Encode(keyBytes),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
    return jsonEncode(envelope);
  }

  Future<Map<String, dynamic>> decodeSnapshot(String encoded) async {
    dynamic raw;
    try {
      raw = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('备份文件不是有效 JSON');
    }
    if (raw is! Map) {
      throw const FormatException('备份文件结构不正确');
    }
    final envelope = Map<String, dynamic>.from(raw);
    if (envelope['format'] != 'wordie-account-backup') {
      throw const FormatException('不是 Wordie 账号备份');
    }
    if (envelope['version'] != formatVersion) {
      throw FormatException('不支持的备份版本：${envelope['version']}');
    }
    if (envelope['algorithm'] != 'xchacha20-poly1305') {
      throw const FormatException('不支持的备份加密算法');
    }

    try {
      final algorithm = Xchacha20.poly1305Aead();
      final secretKey = SecretKey(base64Decode(envelope['key'].toString()));
      final box = SecretBox(
        base64Decode(envelope['ciphertext'].toString()),
        nonce: base64Decode(envelope['nonce'].toString()),
        mac: Mac(base64Decode(envelope['mac'].toString())),
      );
      final plainBytes = await algorithm.decrypt(
        box,
        secretKey: secretKey,
      );
      final decoded = jsonDecode(utf8.decode(plainBytes));
      if (decoded is! Map) {
        throw const FormatException('备份内容结构不正确');
      }
      return Map<String, dynamic>.from(decoded);
    } on SecretBoxAuthenticationError {
      throw const FormatException('备份校验失败，文件可能已损坏');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份文件损坏或无法解密');
    }
  }

  Future<Map<String, dynamic>> restoreSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    if (snapshot['format'] != 'wordie-account-backup' ||
        snapshot['version'] != formatVersion) {
      throw const FormatException('备份格式或版本不受支持');
    }
    final tablesRaw = snapshot['tables'];
    final settingsRaw = snapshot['settings'];
    if (tablesRaw is! Map || settingsRaw is! Map) {
      throw const FormatException('备份缺少数据表或设置');
    }
    final tables = Map<String, dynamic>.from(tablesRaw);
    final settings = Map<String, dynamic>.from(settingsRaw);

    final words = _readRows(tables['word'], _wordFromJson);
    final statuses = _readRows(tables['word_status'], _statusFromJson);
    final studyTimes =
        _readRows(tables['study_time_count'], _studyTimeFromJson);
    final wordStudyTimes =
        _readRows(tables['word_study_time_count'], _wordStudyTimeFromJson);

    await wordDao.replaceBackupTables(
      words: words,
      statuses: statuses,
      studyTimes: studyTimes,
      wordStudyTimes: wordStudyTimes,
    );

    final box = storage ?? GetStorage();
    await box.erase();
    for (final entry in settings.entries) {
      await box.write(entry.key, _jsonValue(entry.value));
    }
    await box.save();

    return <String, dynamic>{
      'words': words.length,
      'statuses': statuses.length,
      'studyTimes': studyTimes.length,
      'wordStudyTimes': wordStudyTimes.length,
      'settings': settings.length,
    };
  }

  Future<String> exportToUserDirectory(String encoded) async {
    if (Platform.isAndroid) {
      final path = await _invokeFileMethod<String>(
        'saveText',
        <String, dynamic>{
          'fileName': _backupFileName(),
          'mimeType': 'application/octet-stream',
          'content': encoded,
        },
      );
      if (path == null || path.isEmpty) {
        throw const FileOperationCancelled();
      }
      return path;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}${Platform.pathSeparator}${_backupFileName()}';
    await File(path).writeAsString(encoded, flush: true);
    return path;
  }

  Future<String> exportToAppDirectory(String encoded) async {
    final directory = await getApplicationDocumentsDirectory();
    final backups = Directory(
      '${directory.path}${Platform.pathSeparator}WordieBackups',
    );
    if (!backups.existsSync()) {
      await backups.create(recursive: true);
    }
    final path = '${backups.path}${Platform.pathSeparator}${_backupFileName()}';
    await File(path).writeAsString(encoded, flush: true);
    return path;
  }

  Future<Map<String, dynamic>> summarizeSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    final tables = Map<String, dynamic>.from(snapshot['tables'] as Map);
    final settings = Map<String, dynamic>.from(snapshot['settings'] as Map);
    final words = tables['word'] is List ? tables['word'] as List : const [];
    final statuses = tables['word_status'] is List
        ? tables['word_status'] as List
        : const [];
    final customBooks = settings['custom_books'];
    return <String, dynamic>{
      'createdAt': snapshot['createdAt'],
      'words': words.length,
      'statuses': statuses.length,
      'customBooks': customBooks is Map ? customBooks.length : 0,
    };
  }

  Future<String> pickBackupText() async {
    if (Platform.isAndroid) {
      final text = await _invokeFileMethod<String>(
        'openText',
        <String, dynamic>{'mimeType': 'application/octet-stream'},
      );
      if (text == null) throw const FileOperationCancelled();
      return text;
    }

    final selected = await const MethodChannel(_platformChannel)
        .invokeMethod<String>('openText');
    if (selected == null || selected.isEmpty) {
      throw const FileOperationCancelled();
    }
    return File(selected).readAsString();
  }

  Future<T?> _invokeFileMethod<T>(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      return await const MethodChannel(_platformChannel).invokeMethod<T>(
        method,
        arguments,
      );
    } on MissingPluginException {
      throw const FormatException('当前安装包缺少文件选择组件，请更新后重试');
    } on PlatformException catch (error) {
      throw FormatException(
        error.message?.trim().isNotEmpty == true
            ? error.message!
            : '系统文件选择器调用失败 (${error.code})',
      );
    }
  }

  String _backupFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Wordie_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}.$fileExtension';
  }

  List<T> _readRows<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) mapper,
  ) {
    if (raw is! List) throw const FormatException('备份数据表格式不正确');
    return raw.map((row) {
      if (row is! Map) throw const FormatException('备份数据行格式不正确');
      return mapper(Map<String, dynamic>.from(row));
    }).toList();
  }

  dynamic _jsonValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) return value.map(_jsonValue).toList();
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonValue(item)),
      );
    }
    return value.toString();
  }

  WordPO _mapWord(Map<String, Object?> row) => WordPO(
        id: row['id'] as int?,
        book: row['book'] as String?,
        word: row['word'] as String?,
      );

  Map<String, dynamic> _wordToJson(WordPO word) => <String, dynamic>{
        'id': word.id,
        'book': word.book,
        'word': word.word,
      };

  Map<String, dynamic> _statusToJson(WordStatusPO status) => <String, dynamic>{
        'id': status.id,
        'word': status.word,
        'status': status.status,
        'studyCycle': status.studyCycle,
        'nextReviewTime': status.nextReviewTime,
        'createTime': status.createTime,
        'updateTime': status.updateTime,
      };

  Map<String, dynamic> _studyTimeToJson(StudyTimeCountPO item) =>
      <String, dynamic>{
        'id': item.id,
        'startTime': item.startTime,
        'endTime': item.endTime,
      };

  Map<String, dynamic> _wordStudyTimeToJson(WordStudyTimeCountPO item) =>
      <String, dynamic>{
        'id': item.id,
        'word': item.word,
        'startTime': item.startTime,
        'endTime': item.endTime,
        'studyCycle': item.studyCycle,
        'playComplete': item.playComplete,
      };

  WordPO _wordFromJson(Map<String, dynamic> map) => WordPO(
        id: _asInt(map['id']),
        book: map['book']?.toString(),
        word: map['word']?.toString(),
      );

  WordStatusPO _statusFromJson(Map<String, dynamic> map) => WordStatusPO(
        id: _asInt(map['id']),
        word: map['word']?.toString(),
        status: _asInt(map['status']),
        studyCycle: _asInt(map['studyCycle']),
        nextReviewTime: _asInt(map['nextReviewTime']),
        createTime: _asInt(map['createTime']),
        updateTime: _asInt(map['updateTime']),
      );

  StudyTimeCountPO _studyTimeFromJson(Map<String, dynamic> map) =>
      StudyTimeCountPO(
        id: _asInt(map['id']),
        startTime: _asInt(map['startTime']),
        endTime: _asInt(map['endTime']),
      );

  WordStudyTimeCountPO _wordStudyTimeFromJson(Map<String, dynamic> map) =>
      WordStudyTimeCountPO(
        id: _asInt(map['id']),
        word: map['word']?.toString(),
        startTime: _asInt(map['startTime']),
        endTime: _asInt(map['endTime']),
        studyCycle: _asInt(map['studyCycle']),
        playComplete: _asInt(map['playComplete']),
      );

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}

class FileOperationCancelled implements Exception {
  const FileOperationCancelled();

  @override
  String toString() => '操作已取消';
}
