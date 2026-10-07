import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/domain/entities/ai_models.dart';

void main() {
  group('AI Stream SSE Parsing & Model Tests', () {
    test('reassembles fragmented SSE data stream into complete tokens', () async {
      final sseStreamController = StreamController<List<int>>();

      // Simulate fragmented chunks from HTTP connection
      final chunk1 = 'data: {"type":"token","content":"Based on your food ' ;
      final chunk2 = 'budget of 10,000 ETB, you have spent 7,850 ETB."}\n\n';
      final chunk3 = 'data: {"type":"done","usage":{"totalTokens":42}}\n\n';

      final events = <AiStreamEvent>[];

      // Parser logic identical to AiStreamService
      String buffer = '';
      final subscription = sseStreamController.stream.listen((bytes) {
        final chunk = utf8.decode(bytes);
        buffer += chunk;

        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('data:')) {
            final jsonStr = trimmed.substring(5).trim();
            if (jsonStr.isNotEmpty) {
              final map = jsonDecode(jsonStr) as Map<String, dynamic>;
              if (map['type'] == 'token') {
                events.add(AiStreamEvent(type: AiStreamEventType.token, token: map['content'] as String?));
              } else if (map['type'] == 'done') {
                events.add(AiStreamEvent(type: AiStreamEventType.done, usage: map['usage'] as Map<String, dynamic>?));
              }
            }
          }
        }
      });

      // Push fragmented chunks
      sseStreamController.add(utf8.encode(chunk1));
      sseStreamController.add(utf8.encode(chunk2));
      sseStreamController.add(utf8.encode(chunk3));

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      await sseStreamController.close();

      expect(events.length, 2);
      expect(events[0].type, AiStreamEventType.token);
      expect(events[0].token, 'Based on your food budget of 10,000 ETB, you have spent 7,850 ETB.');
      expect(events[1].type, AiStreamEventType.done);
      expect(events[1].usage?['totalTokens'], 42);
    });

    test('AiProposal correctly reports status and allows copyWith updates', () {
      final proposal = AiProposal(
        id: 'prop_001',
        tool: 'create_limit',
        payload: {'category': 'Food', 'amount': 12000},
      );

      expect(proposal.isPending, isTrue);
      expect(proposal.isAccepted, isFalse);

      final accepted = proposal.copyWith(status: 'accepted');
      expect(accepted.isAccepted, isTrue);
      expect(accepted.isPending, isFalse);

      final rejected = proposal.copyWith(status: 'rejected');
      expect(rejected.isRejected, isTrue);
    });
  });
}
