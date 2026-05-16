import 'package:dio/dio.dart';

class ApiClient {
  // Now using the official Mesh Domain we set up on Debian
  static const String _meshDomain = 'http://lumina.hub:8000';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _meshDomain,
    connectTimeout: const Duration(seconds: 10), // Increased for mesh stability
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    responseType: ResponseType.json,
  ))
    ..interceptors.add(LogInterceptor(requestBody: false, responseBody: false));

  static Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  static Future<Response<T>> post<T>(String path, {dynamic data}) {
    return _dio.post<T>(path, data: data);
  }
  
  static void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }
}
