import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/entities/ai_models.dart';
import 'api_endpoints.dart';

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
    String currentEvent = '';

    await for (final List<int> bytes in responseBody.stream) {
      final chunk = utf8.decode(bytes, allowMalformed: true);
      buffer += chunk;

      final lines = buffer.split('\n');
      // Keep trailing incomplete line in buffer
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          currentEvent = '';
          continue;
        }

        if (trimmed.startsWith('event:')) {
          currentEvent = trimmed.substring(6).trim();
          continue;
        }

        if (trimmed.startsWith('data:')) {
          final jsonStr = trimmed.substring(5).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;

          try {
            final eventMap = jsonDecode(jsonStr) as Map<String, dynamic>;
            final eventType = eventMap['type'] as String? ?? currentEvent;

            if (eventType == 'token' || eventType == 'delta' || eventMap.containsKey('text') || eventMap.containsKey('content')) {
              final token = (eventMap['content'] ?? eventMap['text']) as String?;
              if (token != null && token.isNotEmpty) {
                yield AiStreamEvent(
                  type: AiStreamEventType.token,
                  token: token,
                );
              }
            } else if (eventType == 'proposal' || eventMap.containsKey('proposal')) {
              final propMap = eventMap['proposal'] as Map<String, dynamic>? ?? eventMap;
              yield AiStreamEvent(
                type: AiStreamEventType.proposal,
                proposal: AiProposal.fromMap(propMap),
              );
            } else if (eventType == 'done') {
              yield AiStreamEvent(
                type: AiStreamEventType.done,
                usage: eventMap['usage'] as Map<String, dynamic>?,
              );
            } else if (eventType == 'error' || eventMap.containsKey('error') || eventMap.containsKey('detail')) {
              final err = (eventMap['error'] ?? eventMap['detail'] ?? 'AI error occurred') as String;
              yield AiStreamEvent(
                type: AiStreamEventType.error,
                error: err,
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
        final token = (eventMap['content'] ?? eventMap['text']) as String?;
        if (token != null && token.isNotEmpty) {
          yield AiStreamEvent(
            type: AiStreamEventType.token,
            token: token,
          );
        }
      } catch (_) {}
    }
  }
}
