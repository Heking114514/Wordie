import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:english/service/ai/openai_responses.dart';
import 'package:flutter_test/flutter_test.dart';

class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter(this.chunks);

  final List<String> chunks;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final controller = StreamController<Uint8List>();
    for (final chunk in chunks) {
      controller.add(Uint8List.fromList(utf8.encode(chunk)));
      await Future<void>.delayed(Duration.zero);
    }
    unawaited(controller.close());
    return ResponseBody(
      controller.stream,
      200,
      headers: <String, List<String>>{
        'content-type': <String>['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _HangingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final controller = StreamController<Uint8List>();
    cancelFuture?.whenComplete(controller.close);
    return ResponseBody(
      controller.stream,
      200,
      headers: <String, List<String>>{
        'content-type': <String>['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('OpenAiSseDecoder', () {
    test('parses multiline data only at blank-line boundary', () {
      final decoder = OpenAiSseDecoder();
      expect(decoder.addLine('event: response.output_text.delta'), isEmpty);
      expect(decoder.addLine('data: {"type":'), isEmpty);
      expect(decoder.addLine('data: "response.output_text.delta"}'), isEmpty);
      final events = decoder.addLine('');
      expect(events, hasLength(1));
      expect(events.single.event, 'response.output_text.delta');
      expect(
        jsonDecode(events.single.data),
        <String, dynamic>{'type': 'response.output_text.delta'},
      );
    });

    test('ignores comments and dispatches close without trailing blank line',
        () {
      final decoder = OpenAiSseDecoder();
      decoder.addLine(': keepalive');
      decoder.addLine('data: {"type":"response.completed"}');
      final events = decoder.close();
      expect(events, hasLength(1));
      expect(events.single.data, '{"type":"response.completed"}');
    });
  });

  group('AiSettings endpoint', () {
    test('uses /responses for a root site URL', () {
      const settings = AiSettings(
        apiKey: 'key',
        baseUrl: 'https://example.test/',
        model: 'model',
      );
      expect(settings.endpoint, 'https://example.test/responses');
    });

    test('appends responses to a versioned base URL', () {
      const settings = AiSettings(
        apiKey: 'key',
        baseUrl: 'https://example.test/v1/',
        model: 'model',
      );
      expect(settings.endpoint, 'https://example.test/v1/responses');
    });

    test('accepts a complete responses URL', () {
      const settings = AiSettings(
        apiKey: 'key',
        baseUrl: 'https://example.test/openai/v1/responses',
        model: 'model',
      );
      expect(settings.endpoint, 'https://example.test/openai/v1/responses');
    });
  });

  test('streams output_text deltas and sends Responses payload', () async {
    final adapter = _StreamAdapter(<String>[
      'event: response.created\r\n',
      'data: {"type":"response.created"}\r\n\r\n',
      ': keepalive\r\n\r\n',
      'event: response.output_text.delta\r\n',
      'data: {"type":"response.output_text.delta","delta":"Hello "}\r\n\r\n',
      'event: response.output_text.delta\r\n',
      'data: {"type":"response.output_text.delta","delta":"world"}\r\n\r\n',
      'event: response.completed\r\n',
      'data: {"type":"response.completed","response":{"output":[]}}\r\n\r\n',
    ]);
    final dio = Dio();
    dio.httpClientAdapter = adapter;

    final snapshots = <String>[];
    final result = await OpenAiResponsesClient(dio: dio).streamText(
      settings: const AiSettings(
        apiKey: 'test-key',
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
      ),
      instructions: 'write',
      input: 'word',
      cancelToken: CancelToken(),
      onDelta: snapshots.add,
    );

    expect(result, 'Hello world');
    expect(snapshots, <String>['Hello ', 'world']);
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://example.test/v1/responses');
    expect(request.headers['Authorization'], 'Bearer test-key');
    expect(request.data['model'], 'test-model');
    expect(request.data['stream'], isTrue);
    expect(request.data['instructions'], 'write');
    expect(request.data['input'], 'word');
  });

  test('fails promptly on an SSE error event', () async {
    final adapter = _StreamAdapter(<String>[
      'event: error\r\n',
      'data: {"type":"error","error":{"message":"bad model"}}\r\n\r\n',
    ]);
    final dio = Dio();
    dio.httpClientAdapter = adapter;

    await expectLater(
      OpenAiResponsesClient(dio: dio).streamText(
        settings: const AiSettings(
          apiKey: 'test-key',
          baseUrl: 'https://example.test/v1',
          model: 'bad',
        ),
        instructions: 'write',
        input: 'word',
        cancelToken: CancelToken(),
        onDelta: (_) {},
      ),
      throwsA(
        isA<AiRequestException>().having(
          (error) => error.message,
          'message',
          contains('bad model'),
        ),
      ),
    );
  });

  test('fails on EOF without completion instead of hanging', () async {
    final adapter = _StreamAdapter(<String>[
      'event: response.created\r\n',
      'data: {"type":"response.created"}\r\n\r\n',
      ': keepalive\r\n\r\n',
    ]);
    final dio = Dio();
    dio.httpClientAdapter = adapter;

    await expectLater(
      OpenAiResponsesClient(dio: dio).streamText(
        settings: const AiSettings(
          apiKey: 'test-key',
          baseUrl: 'https://example.test/v1',
          model: 'test',
        ),
        instructions: 'write',
        input: 'word',
        cancelToken: CancelToken(),
        onDelta: (_) {},
      ),
      throwsA(
        isA<AiRequestException>().having(
          (error) => error.message,
          'message',
          contains('提前结束'),
        ),
      ),
    );
  });

  test('cancels and fails within total timeout', () async {
    final adapter = _HangingAdapter();
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final cancelToken = CancelToken();

    await expectLater(
      OpenAiResponsesClient(dio: dio).streamText(
        settings: const AiSettings(
          apiKey: 'test-key',
          baseUrl: 'https://example.test/v1',
          model: 'test',
        ),
        instructions: 'write',
        input: 'word',
        cancelToken: cancelToken,
        totalTimeout: const Duration(milliseconds: 20),
        onDelta: (_) {},
      ),
      throwsA(anything),
    );
    expect(cancelToken.isCancelled, isTrue);
  });
}
