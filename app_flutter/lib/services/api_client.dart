import 'dart:convert';
import 'package:http/http.dart' as http;
import 'supabase_client.dart';

class ApiClient {
  final String baseUrl = 'http://localhost:8000'; // Dev URL of FastAPI backend
  final SupabaseService _supabaseService = SupabaseService();

  Future<Map<String, String>> _getHeaders() async {
    final token = _supabaseService.accessToken;
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> get(String path) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = await _getHeaders();
    return http.get(url, headers: headers);
  }

  Future<http.Response> post(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = await _getHeaders();
    return http.post(url, headers: headers, body: jsonEncode(body));
  }

  Future<http.Response> patch(String path, [Map<String, dynamic>? body]) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = await _getHeaders();
    return http.patch(url, headers: headers, body: body != null ? jsonEncode(body) : null);
  }


  /// Sends multipart complaints request (FR-1.1 - FR-1.4)
  Future<http.StreamedResponse> postMultipart({
    required String path,
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final request = http.MultipartRequest('POST', url);

    // Set authorization header using Supabase JWT
    final token = _supabaseService.accessToken;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Add string form fields
    request.fields.addAll(fields);

    // Add file attachments (image, audio)
    for (var file in files) {
      request.files.add(file);
    }

    return request.send();
  }
}
