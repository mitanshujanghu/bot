import 'dart:convert';
import 'dart:io';

class BotApiException implements Exception {
  BotApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BotRunResponse {
  const BotRunResponse({required this.success, required this.logs});
  final bool success;
  final List<String> logs;
}

class BotApi {
  BotApi(this.baseUrl);
  final String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(_uri(path)).timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode(body ?? const {}));
      final response = await request.close().timeout(const Duration(seconds: 120));
      final text = await utf8.decoder.bind(response).join();
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BotApiException(data['error'] as String? ?? 'Server error (${response.statusCode})');
      }
      return data;
    } on SocketException {
      throw BotApiException('Could not reach the bot service. Check the server URL and connection.');
    } on HttpException {
      throw BotApiException('The bot service returned an invalid response.');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> signIn(String password) async {
    final response = await _post('/v1/auth/login', body: {'password': password});
    final token = response['token'];
    if (token is! String || token.isEmpty) throw BotApiException('The server did not return a session token.');
    return token;
  }

  Future<BotRunResponse> run(String token) async {
    final response = await _post('/v1/bot/run', token: token);
    return BotRunResponse(
      success: response['success'] == true,
      logs: (response['logs'] as List<dynamic>? ?? const []).map((line) => line.toString()).toList(),
    );
  }
}
