import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/entities/ai_models.dart';
import 'api_endpoints.dart';
import 'api_client.dart';

/// Service responsible for consuming Server-Sent Events (SSE) from the Fastify AI gateway
class AiStreamService {
  final Dio _dio;

  AiStreamService({required Dio dio}) : _dio = dio;

  /// Streams token chunks and proposal payloads for a user prompt
  Stream<AiStreamEvent> streamMessage({
    required String threadId,
    required String content,
  }) async* {
    final url = ApiEndpoints.aiThreadMessages(threadId);

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        url,
        data: {'content': content},
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
        ),
      );
    } catch (e) {
      yield AiStreamEvent(
        type: AiStreamEventType.error,
        error: 'Failed to connect to AI gateway: $e',
      );
      return;
    }

    final responseBody = response.data;
    if (responseBody == null) {
      yield const AiStreamEvent(
        type: AiStreamEventType.error,
        error: 'Received empty response body from server',
      );
      return;
    }

    String buffer = '';

    await for (final List<int> bytes in responseBody.stream) {
      final chunk = utf8.decode(bytes, allowMalformed: true);
      buffer += chunk;

      final lines = buffer.split('\n');
      // Keep trailing incomplete line in buffer
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.startsWith('data:')) {
          final jsonStr = trimmed.substring(5).trim();
          if (jsonStr.isEmpty) continue;

          try {
            final eventMap = jsonDecode(jsonStr) as Map<String, dynamic>;
            final eventType = eventMap['type'] as String? ?? '';

            if (eventType == 'token') {
              yield AiStreamEvent(
                type: AiStreamEventType.token,
                token: eventMap['content'] as String? ?? '',
              );
            } else if (eventType == 'proposal') {
              final propMap = eventMap['proposal'] as Map<String, dynamic>? ?? {};
              yield AiStreamEvent(
                type: AiStreamEventType.proposal,
                proposal: AiProposal.fromMap(propMap),
              );
            } else if (eventType == 'done') {
              yield AiStreamEvent(
                type: AiStreamEventType.done,
                usage: eventMap['usage'] as Map<String, dynamic>?,
              );
            }
          } catch (e) {
            // Malformed JSON chunk: skip
          }
        }
      }
    }

    // Flush any remaining content in buffer
    if (buffer.trim().startsWith('data:')) {
      final jsonStr = buffer.trim().substring(5).trim();
      try {
        final eventMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (eventMap['type'] == 'token') {
          yield AiStreamEvent(
            type: AiStreamEventType.token,
            token: eventMap['content'] as String? ?? '',
          );
        }
      } catch (_) {}
    }
  }
}
