// lib/util/dictionary.dart
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import '../dicts/reader.dart';

int _nextId = -1;

Future<Word?> fetchWordDefinition(String spell) async {
  print('[DICT] >>> fetch "$spell"');

  final htmlResult = await _tryHtmlFetch(spell);
  if (htmlResult != null) {
    print('[DICT] HTML OK means="${htmlResult.means}" sentences=${htmlResult.sentences?.length ?? 0}');
    return htmlResult;
  }
  print('[DICT] HTML failed, trying jsonapi...');

  final jsonResult = await _tryJsonApiFetch(spell);
  if (jsonResult != null) {
    print('[DICT] jsonapi OK means="${jsonResult.means}"');
    return jsonResult;
  }
  print('[DICT] BOTH FAILED for "$spell"');
  return null;
}

Future<Word?> _tryHtmlFetch(String spell) async {
  try {
    final url = 'https://dict.youdao.com/w/$spell';
    final response = await Dio().get(url,
      options: Options(
        receiveTimeout: 6000,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      ));
    if (response.statusCode != 200) {
      print('[DICT] HTML status=${response.statusCode}');
      return null;
    }

    final html = response.data as String;
    print('[DICT] HTML response length=${html.length}');
    final means = _parseMeans(html);
    if (means.isEmpty) {
      print('[DICT] HTML _parseMeans returned empty');
      return null;
    }

    final sentences = _parseExamples(html);
    final usVoice = _parsePhonetic(html, '美');
    final ukVoice = _parsePhonetic(html, '英');

    final id = (_nextId--).toString();
    final word = Word(
      id: id, word: spell,
      usVoice: usVoice, ukVoice: ukVoice,
      means: means.join('\n'),
      sentences: sentences.isNotEmpty ? sentences : null,
    );
    _saveToCache(word);
    return word;
  } catch (e) {
    print('[DICT] HTML fetch exception: $e');
    return null;
  }
}

Future<Word?> _tryJsonApiFetch(String spell) async {
  try {
    final url = 'https://dict.youdao.com/jsonapi?q=$spell&le=eng';
    print('[DICT] jsonapi calling $url');
    final response = await Dio().get(url,
      options: Options(receiveTimeout: 5000));
    print('[DICT] jsonapi response status=${response.statusCode}');
    if (response.statusCode != 200 || response.data == null) return null;

    print('[DICT] jsonapi raw data type=${response.data.runtimeType}');
    final data = response.data as Map<String, dynamic>;
    print('[DICT] jsonapi top-level keys=${data.keys.toList()}');
    final ec = data['ec'] as Map<String, dynamic>?;
    if (ec == null) {
      print('[DICT] jsonapi "ec" is null');
      return null;
    }
    print('[DICT] jsonapi ec keys=${ec.keys.toList()}');
    final wordList = ec['word'] as List<dynamic>?;
    if (wordList == null || wordList.isEmpty) {
      print('[DICT] jsonapi wordList is null or empty');
      return null;
    }

    final wordEntry = wordList[0] as Map<String, dynamic>;
    print('[DICT] jsonapi wordEntry keys=${wordEntry.keys.toList()}');
    final trs = wordEntry['trs'] as List<dynamic>?;
    print('[DICT] jsonapi trs=${trs != null ? "list(${trs.length})" : "NULL"}');
    final usVoice = wordEntry['usphone'] as String?;
    final ukVoice = wordEntry['ukphone'] as String?;

    final means = _extractMeansFromTrs(wordEntry['trs'] as List<dynamic>?);
    if (means.isEmpty) return null;

    final id = (_nextId--).toString();
    final word = Word(
      id: id, word: spell,
      usVoice: usVoice, ukVoice: ukVoice,
      means: means,
    );
    _saveToCache(word);
    return word;
  } catch (e) {
    print('[DICT] jsonapi exception: $e');
    return null;
  }
}

List<String> _parseMeans(String html) {
  final means = <String>[];
  final m = RegExp(
    r'<div\s+class="trans-container"[^>]*>(.*?)</div>\s*<!--\s*trans-container',
    dotAll: true,
  ).firstMatch(html) ?? RegExp(
    r'<div\s+class="trans-container"[^>]*>(.*?)</div>',
    dotAll: true,
  ).firstMatch(html);
  final block = m?.group(1) ?? '';
  if (block.isEmpty) return means;

  final lis = RegExp(r'<li>(.*?)</li>', dotAll: true).allMatches(block);
  for (var li in lis) {
    final text = li.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (text.isNotEmpty) means.add(text);
  }
  return means;
}

String _parsePhonetic(String html, String label) {
  final m = RegExp(
    '$label\\s*<span[^>]*>.*?\\[(.*?)\\]',
    dotAll: true,
  ).firstMatch(html);
  return m != null ? '/${m.group(1)}/' : '';
}

String _extractMeansFromTrs(List<dynamic>? trs) {
  if (trs == null) return '';
  final buf = StringBuffer();
  for (var t in trs) {
    final pos = t['pos'] as String? ?? '';
    final tran = t['tran'] as String? ?? '';
    if (pos.isNotEmpty && tran.isNotEmpty) {
      buf.writeln('$pos $tran');
    } else if (tran.isNotEmpty) {
      buf.writeln(tran);
    }
  }
  return buf.toString().trim();
}

List<Sentence> _parseExamples(String html) {
  final sentences = <Sentence>[];
  final m = RegExp(
    r'<div\s+class="examples"[^>]*>(.*?)</div>\s*<!--\s*examples',
    dotAll: true,
  ).firstMatch(html) ?? RegExp(
    r'<div\s+class="examples"[^>]*>(.*?)</div>',
    dotAll: true,
  ).firstMatch(html);
  final block = m?.group(1) ?? '';
  if (block.isEmpty) return sentences;

  final pairs = RegExp(r'<p>(.*?)</p>\s*<p>(.*?)</p>', dotAll: true).allMatches(block);
  for (var p in pairs) {
    final en = p.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final cn = p.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (en.isNotEmpty && cn.isNotEmpty && en.length > 3) {
      sentences.add(Sentence(sentence: en, sentenceCn: cn));
    }
  }
  return sentences;
}

void _saveToCache(Word word) {
  final storage = GetStorage();
  Map<String, dynamic> cache = storage.read('fetched_words') != null
      ? Map<String, dynamic>.from(storage.read('fetched_words'))
      : {};
  cache[word.word!.toLowerCase()] = word.toMap();
  storage.write('fetched_words', cache);
  print('[DICT] saved to cache: key="${word.word!.toLowerCase()}" id=${word.id} cacheSize=${cache.length}');
}

void loadFetchedWordsCache(Map<String, Word> wordMap) {
  final storage = GetStorage();
  final cache = storage.read('fetched_words');
  if (cache == null) {
    print('[DICT] loadCache: cache is null (no fetched_words in storage)');
    return;
  }

  final Map<String, dynamic> data = Map<String, dynamic>.from(cache);
  print('[DICT] loadCache: loading ${data.length} cached words');
  int minId = 0;
  for (var entry in data.entries) {
    try {
      final word = Word.fromMap(entry.value as Map<String, dynamic>);
      wordMap[word.id!] = word;
      final id = int.tryParse(word.id ?? '') ?? 0;
      if (id < minId) minId = id;
    } catch (e) {
      print('[DICT] loadCache ERROR for key="${entry.key}": $e');
    }
  }
  _nextId = minId - 1;
  print('[DICT] loadCache done: ${data.length} words loaded, _nextId=$_nextId');
}
