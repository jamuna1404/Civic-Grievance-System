import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown when the API returns a non-2xx response. [message] is safe to show
/// to the user (it prefers the backend's `detail` field).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin JSON HTTP client for the CivicRoute FastAPI backend.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _defaultBaseUrl();

  final http.Client _client;
  final String baseUrl;

  /// Resolves the backend base URL per platform for local development.
  ///
  /// Android emulators reach the host machine at 10.0.2.2, not localhost.
  /// TODO: replace with a build-time / env-configured URL before release.
  static String _defaultBaseUrl() {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) =>
      _send('POST', path, body, token);

  /// GET a JSON array endpoint.
  Future<List<dynamic>> getJsonList(String path, {String? token}) async =>
      await _get(path, token) as List<dynamic>? ?? <dynamic>[];

  /// GET a JSON object endpoint.
  Future<Map<String, dynamic>> getJsonObject(
    String path, {
    String? token,
  }) async =>
      (await _get(path, token) as Map<String, dynamic>?) ?? <String, dynamic>{};

  Future<dynamic> _get(String path, String? token) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      if (token != null) 'Authorization': 'Bearer $token',
    };
    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? null : jsonDecode(response.body);
    }

    Object? detail;
    try {
      detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'];
    } catch (_) {
      detail = null;
    }
    throw ApiException(
      detail is String ? detail : 'Something went wrong. Please try again.',
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) =>
      _send('PUT', path, body, token);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic> body,
    String? token,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    late final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(
            const Duration(seconds: 20),
          );
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw ApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final detail = decoded['detail'];
    throw ApiException(
      detail is String ? detail : 'Something went wrong. Please try again.',
      statusCode: response.statusCode,
    );
  }

  void dispose() => _client.close();
}
