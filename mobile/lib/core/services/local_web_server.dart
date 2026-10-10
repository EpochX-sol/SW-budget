import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class LocalWebServer {
  HttpServer? _server;
  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Starts the embedded Wi-Fi web server on local port [port].
  Future<String> start({
    int port = 8080,
    List<Map<String, dynamic>> initialTransactions = const [],
  }) async {
    if (_server != null) {
      await stop();
    }

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler((Request request) async {
      final path = request.url.path;

      if (path == 'api/status') {
        return Response.ok(
          jsonEncode({
            'status': 'online',
            'server': 'SW-budget Local Wi-Fi Web Server',
            'version': '2.0.0',
            'timestamp': DateTime.now().toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (path == 'api/transactions') {
        return Response.ok(
          jsonEncode({
            'count': initialTransactions.length,
            'transactions': initialTransactions,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Root single-page HTML5 dashboard
      const htmlContent = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>SW-budget Local Wi-Fi Ledger</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0F172A; color: #F8FAFC; margin: 0; padding: 32px; }
    .card { background: #1E293B; border-radius: 12px; padding: 24px; max-width: 800px; margin: 0 auto; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
    h1 { color: #10B981; margin-top: 0; }
    .badge { background: rgba(16,185,129,0.2); color: #10B981; padding: 4px 10px; border-radius: 6px; font-size: 13px; font-weight: bold; }
  </style>
</head>
<body>
  <div class="card">
    <div style="display:flex; justify-content:space-between; align-items:center;">
      <h1>SW-budget Local Ledger</h1>
      <span class="badge">Wi-Fi Connected</span>
    </div>
    <p style="color:#94A3B8;">Secure on-device local web inspection. No data leaves your home network.</p>
  </div>
</body>
</html>
''';

      return Response.ok(htmlContent, headers: {'content-type': 'text/html'});
    });

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    return 'http://${_server!.address.host}:${_server!.port}';
  }

  /// Stops the local Wi-Fi server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
