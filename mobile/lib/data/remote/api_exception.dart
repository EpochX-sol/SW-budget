import 'package:dio/dio.dart';

/// Representation of an RFC 7807 Problem Details error returned by the backend
class ApiException implements Exception {
  final String type;
  final String title;
  final int status;
  final String detail;
  final String? instance;
  final String? timestamp;
  final dynamic rawData;

  const ApiException({
    this.type = 'about:blank',
    required this.title,
    required this.status,
    required this.detail,
    this.instance,
    this.timestamp,
    this.rawData,
  });

  factory ApiException.fromDioException(DioException e) {
    if (e.response != null && e.response?.data is Map<String, dynamic>) {
      final map = e.response!.data as Map<String, dynamic>;
      return ApiException(
        type: map['type'] as String? ?? 'about:blank',
        title: map['title'] as String? ?? 'Request Error',
        status: (map['status'] as num?)?.toInt() ?? e.response?.statusCode ?? 500,
        detail: map['detail'] as String? ?? e.message ?? 'Unknown server error',
        instance: map['instance'] as String?,
        timestamp: map['timestamp'] as String?,
        rawData: map,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiException(
        title: 'Connection Timeout',
        status: 408,
        detail: 'The request took too long to complete. Please check your network connection.',
        rawData: e.error,
      );
    }

    if (e.type == DioExceptionType.connectionError) {
      return ApiException(
        title: 'Network Error',
        status: 503,
        detail: 'Cannot reach the SW-budget server. Please ensure the backend is running.',
        rawData: e.error,
      );
    }

    return ApiException(
      title: 'HTTP Error',
      status: e.response?.statusCode ?? 500,
      detail: e.response?.statusMessage ?? e.message ?? 'An unexpected network error occurred.',
      rawData: e.response?.data,
    );
  }

  @override
  String toString() {
    return 'ApiException(status: $status, title: "$title", detail: "$detail")';
  }
}
