import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sw_budget/data/remote/api_exception.dart';

void main() {
  group('ApiException RFC 7807 Parser Tests', () {
    test('correctly parses standard RFC 7807 Problem Details JSON payload', () {
      final requestOptions = RequestOptions(path: '/v1/auth/register');
      final response = Response(
        requestOptions: requestOptions,
        statusCode: 400,
        data: {
          'type': 'about:blank',
          'title': 'Validation Error',
          'status': 400,
          'detail': 'Password must be at least 8 characters, email is invalid',
          'instance': '/v1/auth/register',
          'timestamp': '2026-10-07T02:40:00.000Z',
        },
      );

      final dioException = DioException(
        requestOptions: requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );

      final apiException = ApiException.fromDioException(dioException);

      expect(apiException.status, 400);
      expect(apiException.title, 'Validation Error');
      expect(apiException.detail, 'Password must be at least 8 characters, email is invalid');
      expect(apiException.instance, '/v1/auth/register');
      expect(apiException.timestamp, '2026-10-07T02:40:00.000Z');
      expect(apiException.toString(), contains('Validation Error'));
    });

    test('handles connection timeouts with friendly message and 408 status', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/v1/me'),
        type: DioExceptionType.connectionTimeout,
      );

      final apiException = ApiException.fromDioException(dioException);

      expect(apiException.status, 408);
      expect(apiException.title, 'Connection Timeout');
      expect(apiException.detail, contains('took too long'));
    });

    test('handles unreachable backend connection error with 503 status', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/v1/accounts'),
        type: DioExceptionType.connectionError,
      );

      final apiException = ApiException.fromDioException(dioException);

      expect(apiException.status, 503);
      expect(apiException.title, 'Network Error');
      expect(apiException.detail, contains('Cannot reach the SW-budget server'));
    });
  });
}
