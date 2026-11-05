import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';

class AiSettings {
  static const String defaultBaseUrl = 'https://self.zlapi.asia';
  static const String defaultModel = 'deepseek-v4.1-flash';

  final String apiKey;
  final String baseUrl;
  final String model;

  const AiSettings({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  factory AiSettings.fromStorage([GetStorage? storage]) {
    final box = storage ?? GetStorage();
    return AiSettings(
      apiKey: (box.read('api_key') ?? '').toString().trim(),
      baseUrl: _readSetting(box, 'ai_base_url', defaultBaseUrl),
      model: _readSetting(box, 'ai_model', defaultModel),
    );
  }

  bool get isConfigured => apiKey.isNotEmpty && model.isNotEmpty;

  String get endpoint {
    final raw = baseUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('API 站点地址格式不正确');
    }

    var path = uri.path.trim();
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/responses')) {
      return uri.replace(path: path).toString();
    }
    if (path.isEmpty) {
      path = '/responses';
    } else {
      path = '$path/responses';
    }
    return uri.replace(path: path).toString();
  }

  static String _readSetting(GetStorage storage, String key, String fallback) {
    final value = (storage.read(key) ?? '').toString().trim();
    return value.isEmpty ? fallback : value;
  }
}

class AiRequestException implements Exception {
  final String message;

  const AiRequestException(this.message);

  @override
  String toString() => message;
}

class OpenAiSseEvent {
  final String event;
  final String data;

  const OpenAiSseEvent(this.event, this.data);

  String get payload => data;
}

/// Incremental SSE decoder. It preserves multi-line data fields and only emits
/// an event on the blank-line delimiter required by the SSE specification.
class OpenAiSseDecoder {
  String _event = '';
  final List<String> _dataLines = <String>[];

  List<OpenAiSseEvent> addLine(String line) {
    if (line.isEmpty) return _dispatch();

    if (line.startsWith(':')) return const <OpenAiSseEvent>[];

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    if (field == 'event') {
      _event = value;
    } else if (field == 'data') {
      _dataLines.add(value);
    }
    return const <OpenAiSseEvent>[];
  }

  List<OpenAiSseEvent> close() {
    if (_dataLines.isEmpty) {
      _event = '';
      return const <OpenAiSseEvent>[];
    }
    return _dispatch();
  }

  List<OpenAiSseEvent> _dispatch() {
    if (_dataLines.isEmpty) {
      _event = '';
      return const <OpenAiSseEvent>[];
    }
    final event = OpenAiSseEvent(_event, _dataLines.join('\n'));
    _event = '';
    _dataLines.clear();
    return <OpenAiSseEvent>[event];
  }
}

class OpenAiResponsesClient {
  final Dio _dio;

  OpenAiResponsesClient({Dio? dio}) : _dio = dio ?? _defaultDio();

  static Dio _defaultDio() {
    return Dio(
      BaseOptions(
        connectTimeout: 15000,
        sendTimeout: 15000,
        receiveTimeout: 180000,
        headers: const <String, String>{
          'Accept': 'text/event-stream',
          'Content-Type': 'application/json; charset=utf-8',
        },
      ),
    );
  }

  Future<String> streamText({
    required AiSettings settings,
    required String instructions,
    required String input,
    required CancelToken cancelToken,
    required void Function(String delta) onDelta,
    int maxOutputTokens = 900,
    Duration idleTimeout = const Duration(seconds: 90),
    Duration totalTimeout = const Duration(minutes: 4),
  }) async {
    if (!settings.isConfigured) {
      throw const AiRequestException('请先配置 API Key 和模型');
    }

    final timeoutCompleter = Completer<void>();
    final watchdog = Timer(totalTimeout, () {
      cancelToken.cancel('AI request timed out');
      if (!timeoutCompleter.isCompleted) {
        timeoutCompleter.completeError(
          TimeoutException('AI 请求总时长超过限制', totalTimeout),
        );
      }
    });

    try {
      final consume = _consumeStream(
        settings: settings,
        instructions: instructions,
        input: input,
        cancelToken: cancelToken,
        onDelta: onDelta,
        maxOutputTokens: maxOutputTokens,
        idleTimeout: idleTimeout,
      );
      return await Future.any<String>(<Future<String>>[
        consume,
        timeoutCompleter.future.then<String>(
          (_) => throw TimeoutException('AI 请求总时长超过限制', totalTimeout),
        ),
      ]);
    } finally {
      watchdog.cancel();
    }
  }

  Future<String> _consumeStream({
    required AiSettings settings,
    required String instructions,
    required String input,
    required CancelToken cancelToken,
    required void Function(String delta) onDelta,
    required int maxOutputTokens,
    required Duration idleTimeout,
  }) async {
    final response = await _dio.post<ResponseBody>(
      settings.endpoint,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: <String, String>{
          'Authorization': 'Bearer ${settings.apiKey}',
        },
      ),
      data: <String, dynamic>{
        'model': settings.model,
        'stream': true,
        'instructions': instructions,
        'input': input,
        'max_output_tokens': maxOutputTokens,
      },
    );

    final body = response.data;
    if (body == null) {
      throw const AiRequestException('AI 服务返回了空响应');
    }

    final article = StringBuffer();
    final rawBody = StringBuffer();
    final decoder = OpenAiSseDecoder();
    var streamFinished = false;

    void consumeEvent(OpenAiSseEvent sseEvent) {
      final payload = sseEvent.payload.trim();
      if (payload.isEmpty) return;
      if (payload == '[DONE]') {
        streamFinished = true;
        return;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        throw AiRequestException('AI 流式响应不是有效 JSON');
      }
      if (decoded is! Map) return;
      final event = Map<String, dynamic>.from(decoded);

      final type = (event['type'] ?? sseEvent.event ?? '').toString();
      if (type == 'response.output_text.delta') {
        final delta = event['delta'];
        if (delta is String && delta.isNotEmpty) {
          article.write(delta);
          onDelta(delta);
        }
        return;
      }

      if (type == 'response.output_text.done') {
        if (event['text'] is String && article.isEmpty) {
          final text = event['text'] as String;
          article.write(text);
          if (text.isNotEmpty) onDelta(text);
        }
        return;
      }

      if (type == 'response.refusal.delta') {
        final delta = event['delta'];
        throw AiRequestException(
          delta is String && delta.isNotEmpty ? delta : '模型拒绝了本次请求',
        );
      }

      if (type == 'response.failed' || type == 'response.incomplete') {
        final responseData = event['response'];
        final error =
            responseData is Map ? responseData['error'] : event['error'];
        throw AiRequestException(_errorMessage(error, 'AI 生成失败'));
      }

      if (type == 'error' || event['error'] != null) {
        throw AiRequestException(
          _errorMessage(event['error'], 'AI 服务返回错误'),
        );
      }

      if (type == 'response.completed') {
        streamFinished = true;
        if (article.isEmpty) {
          final text = _extractResponseText(event['response']);
          if (text.isNotEmpty) {
            article.write(text);
            onDelta(text);
          }
        }
        return;
      }

      // A few compatible stations still wrap a Responses payload in choices.
      final choices = event['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final choice = Map<String, dynamic>.from(choices.first as Map);
        final message = choice['delta'] ?? choice['message'];
        if (message is Map && message['content'] is String) {
          final delta = message['content'] as String;
          if (delta.isNotEmpty) {
            article.write(delta);
            onDelta(delta);
          }
        }
      }
    }

    final lineStream = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(idleTimeout);

    await for (final line in lineStream) {
      if (cancelToken.isCancelled) {
        throw const AiRequestException('AI 请求已取消');
      }
      rawBody.writeln(line);
      for (final event in decoder.addLine(line)) {
        consumeEvent(event);
      }
    }
    for (final event in decoder.close()) {
      consumeEvent(event);
    }

    if (article.isEmpty) {
      final fallback = _tryExtractJsonResponse(rawBody.toString());
      if (fallback.isNotEmpty) {
        article.write(fallback);
        onDelta(fallback);
      }
    }

    if (article.isEmpty) {
      if (streamFinished || cancelToken.isCancelled) {
        throw const AiRequestException('AI 完成了响应，但没有返回文章内容');
      }
      throw const AiRequestException('AI 流式响应提前结束，没有返回文章内容');
    }
    return article.toString();
  }

  String _tryExtractJsonResponse(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['error'] != null) {
        throw AiRequestException(
          _errorMessage(decoded['error'], 'AI 服务返回错误'),
        );
      }
      return _extractResponseText(decoded);
    } on FormatException {
      return '';
    }
  }

  String _extractResponseText(dynamic value) {
    if (value is! Map) return '';
    final response = Map<String, dynamic>.from(value);
    if (response['output_text'] is String) {
      return response['output_text'] as String;
    }

    final output = response['output'];
    final buffer = StringBuffer();
    if (output is List) {
      for (final item in output) {
        if (item is! Map) continue;
        final content = item['content'];
        if (content is! List) continue;
        for (final part in content) {
          if (part is! Map) continue;
          if (part['text'] is String) buffer.write(part['text']);
        }
      }
    }
    return buffer.toString();
  }

  String _errorMessage(dynamic error, String fallback) {
    if (error is Map) {
      final message = error['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    if (error is String && error.trim().isNotEmpty) return error;
    return fallback;
  }
}

Uint8List? aiResponseBytes(List<int>? bytes) {
  if (bytes == null) return null;
  return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}
