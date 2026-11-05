// lib/util/dictionary.dart
import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import '../dicts/reader.dart';

int _nextId = -1;

Future<Word?> fetchWordDefinition(String spell) async {
  // 优先查本地缓存
  try {
    final storage = GetStorage();
    Map<String, dynamic> cache = storage.read('fetched_words') != null
        ? Map<String, dynamic>.from(storage.read('fetched_words'))
        : {};
    var cached = cache[spell.toLowerCase()];
    if (cached != null) {
      var word = Word.fromMap(Map<String, dynamic>.from(cached));
      if (word.means != null && word.means!.trim().isNotEmpty) return word;
    }
  } catch (_) {}

  // 路径1: 有道桌面版 HTML
  final htmlResult = await _tryHtmlFetch('https://dict.youdao.com/w/$spell', spell);
  if (htmlResult != null) return htmlResult;

  // 路径2: 有道移动版 HTML
  final mobileResult = await _tryHtmlFetch('https://m.youdao.com/dict?le=eng&q=$spell', spell, mobile: true);
  if (mobileResult != null) return mobileResult;

  // 路径3: 有道 jsonapi
  final jsonResult = await _tryJsonApiFetch(spell);
  if (jsonResult != null) return jsonResult;

  // 路径4: dictionaryapi.dev
  final freeResult = await _tryFreeDictApi(spell);
  if (freeResult != null) return freeResult;

  return null;
}

Future<Word?> _tryHtmlFetch(String url, String spell, {bool mobile = false}) async {
  try {
    final headers = <String, String>{
      'Accept-Language': 'zh-CN,zh;q=0.9',
    };
    if (mobile) {
      headers['User-Agent'] = 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)';
    } else {
      headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    }

    final response = await Dio().get(url,
      options: Options(receiveTimeout: 6000, headers: headers));
    if (response.statusCode != 200) return null;

    final html = response.data as String;
    final means = _parseMeans(html);
    if (means.isEmpty) return null;

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
    return null;
  }
}

Future<Word?> _tryJsonApiFetch(String spell) async {
  try {
    final url = 'https://dict.youdao.com/jsonapi?q=$spell&le=eng';
    final response = await Dio().get(url,
      options: Options(receiveTimeout: 5000));
    if (response.statusCode != 200 || response.data == null) return null;

    final data = response.data as Map<String, dynamic>;
    String? usVoice, ukVoice;
    String means = '';

    final ec = data['ec'] as Map<String, dynamic>?;
    if (ec != null) {
      final wordList = ec['word'] as List<dynamic>?;
      if (wordList != null && wordList.isNotEmpty) {
        final wordEntry = wordList[0] as Map<String, dynamic>;
        usVoice = wordEntry['usphone'] as String?;
        ukVoice = wordEntry['ukphone'] as String?;
        means = _extractMeansFromTrs(wordEntry['trs'] as List<dynamic>?);
      }
    }

    // web_trans 兜底（实际 key 可能是 "trans" 或 "web-translation"）
    if (means.trim().isEmpty) {
      final webTrans = data['web_trans'] as Map<String, dynamic>?;
      final transList = (webTrans?['web-translation'] ?? webTrans?['trans']) as List<dynamic>?;
      if (transList != null && transList.isNotEmpty) {
        final buf = StringBuffer();
        for (var item in transList.take(5)) {
          if (item is! Map) continue;
          // value 可能直接在 item 上，也可能嵌套在 item.trans[n].value
          String tran = (item['tran'] as String?) ?? (item['value'] as String?) ?? '';
          if (tran.trim().isEmpty) {
            final innerTrans = item['trans'] as List<dynamic>?;
            if (innerTrans != null) {
              final innerVals = innerTrans
                  .whereType<Map>()
                  .map((t) => (t['value'] as String?) ?? '')
                  .where((v) => v.trim().isNotEmpty)
                  .take(3);
              tran = innerVals.join('; ');
            }
          }
          if (tran.trim().isNotEmpty) buf.writeln(tran.trim());
        }
        means = buf.toString().trim();
      }
    }

    if (means.trim().isEmpty) return null;

    final id = (_nextId--).toString();
    final word = Word(
      id: id, word: spell,
      usVoice: usVoice, ukVoice: ukVoice,
      means: means,
    );
    _saveToCache(word);
    return word;
  } catch (e) {
    return null;
  }
}

Future<Word?> _tryFreeDictApi(String spell) async {
  try {
    final url = 'https://api.dictionaryapi.dev/api/v2/entries/en/$spell';
    final response = await Dio().get(url, options: Options(receiveTimeout: 5000));
    if (response.statusCode != 200 || response.data == null) return null;

    final data = response.data as List<dynamic>;
    if (data.isEmpty) return null;

    final entry = data[0] as Map<String, dynamic>;
    final meanings = entry['meanings'] as List<dynamic>?;
    if (meanings == null || meanings.isEmpty) return null;

    final buf = StringBuffer();
    for (var meaning in meanings) {
      if (meaning is! Map) continue;
      final pos = meaning['partOfSpeech'] as String? ?? '';
      final definitions = meaning['definitions'] as List<dynamic>? ?? [];
      for (var def in definitions.take(3)) {
        if (def is Map) {
          final text = def['definition'] as String? ?? '';
          if (text.isNotEmpty) {
            buf.writeln('${pos.isNotEmpty ? "$pos " : ""}$text');
          }
        }
      }
    }

    final means = buf.toString().trim();
    if (means.isEmpty) return null;

    final id = (_nextId--).toString();
    final word = Word(id: id, word: spell, means: means);
    _saveToCache(word);
    return word;
  } catch (e) {
    return null;
  }
}

List<String> _parseMeans(String html) {
  final means = <String>[];

  final startIdx = html.indexOf('trans-container');
  if (startIdx < 0) return means;

  final afterStart = html.substring(startIdx);
  final ulMatch = RegExp(r'<ul>(.*?)</ul>', dotAll: true).firstMatch(afterStart);
  if (ulMatch != null) {
    final lis = RegExp(r'<li>(.*?)</li>', dotAll: true).allMatches(ulMatch.group(1)!);
    for (var li in lis) {
      final text = li.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (text.isNotEmpty) means.add(text);
    }
    if (means.isNotEmpty) return means;
  }

  // 兜底
  final matches = RegExp(r'<div\s+class="trans-container"[^>]*>(.*?)</div>', dotAll: true).allMatches(html);
  for (var m in matches) {
    final block = m.group(1) ?? '';
    final lis = RegExp(r'<li>(.*?)</li>', dotAll: true).allMatches(block);
    if (lis.isNotEmpty) {
      for (var li in lis) {
        final text = li.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (text.isNotEmpty) means.add(text);
      }
      return means;
    }
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
    if (t is! Map) continue;

    if (t.containsKey('tr')) {
      final trList = t['tr'] as List<dynamic>?;
      if (trList != null && trList.isNotEmpty) {
        for (var trItem in trList) {
          if (trItem is Map && trItem.containsKey('l')) {
            final l = trItem['l'] as Map?;
            if (l != null && l.containsKey('i')) {
              final iVal = l['i'];
              if (iVal is List) {
                buf.writeln(iVal.join(' '));
              } else if (iVal is String && iVal.trim().isNotEmpty) {
                buf.writeln(iVal);
              }
            }
          }
        }
        if (buf.isNotEmpty) continue;
      }
    }

    final pos = t['pos'] as String? ?? '';
    final tran = t['tran'] as String? ?? '';
    if (pos.isNotEmpty || tran.isNotEmpty) {
      buf.writeln('$pos $tran'.trim());
    }
  }

  if (buf.isEmpty && trs.isNotEmpty) {
    final found = _deepExtractStrings(trs);
    if (found.isNotEmpty) {
      buf.writeln(found.join('\n'));
    }
  }
  return buf.toString().trim();
}

List<String> _deepExtractStrings(dynamic obj) {
  final result = <String>[];
  if (obj is String) {
    final trimmed = obj.trim();
    if (trimmed.isNotEmpty) result.add(trimmed);
  } else if (obj is List) {
    for (var item in obj) {
      result.addAll(_deepExtractStrings(item));
    }
  } else if (obj is Map) {
    for (var val in obj.values) {
      result.addAll(_deepExtractStrings(val));
    }
  }
  return result;
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
}

void loadFetchedWordsCache(Map<String, Word> wordMap, Map<String, Word> spellMap) {
  final storage = GetStorage();
  final cache = storage.read('fetched_words');
  if (cache == null) return;

  final Map<String, dynamic> data = Map<String, dynamic>.from(cache);
  int minId = 0;
  for (var entry in data.entries) {
    try {
      final fetched = Word.fromMap(entry.value as Map<String, dynamic>);
      final id = int.tryParse(fetched.id ?? '') ?? 0;
      if (id < minId) minId = id;

      if (fetched.means != null && fetched.means!.trim().isNotEmpty) {
        var spell = fetched.word;
        if (spell != null) {
          // 找到已有的 Word（按拼写），就地更新
          var existing = spellMap[spell];
          if (existing != null) {
            existing.means = fetched.means;
            if (fetched.usVoice != null && fetched.usVoice!.isNotEmpty) existing.usVoice = fetched.usVoice;
            if (fetched.ukVoice != null && fetched.ukVoice!.isNotEmpty) existing.ukVoice = fetched.ukVoice;
            if (fetched.sentences != null && fetched.sentences!.isNotEmpty) existing.sentences = fetched.sentences;
          } else {
            // 字典里没有这个词，直接加入索引
            wordMap[fetched.id!] = fetched;
            spellMap[spell] = fetched;
          }
        }
      }
    } catch (_) {}
  }
  _nextId = minId - 1;
}
