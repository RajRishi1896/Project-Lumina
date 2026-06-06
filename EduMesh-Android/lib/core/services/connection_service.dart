import 'dart:async';

import 'package:dio/dio.dart';
import '../network/api_client.dart';

/// A service that checks connectivity to the hub server by pinging the `/ping` endpoint.
class ConnectionService {
  /// Whether the server responds with a 2xx status code within the given [timeout].
  Future<bool> ping({Duration timeout = const Duration(seconds: 10)}) async {
    final cancelToken = CancelToken();
    try {
      final resp = await ApiClient.get('/ping', cancelToken: cancelToken).timeout(timeout);
      if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
        return true;
      }
      return false;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return false;
      return false;
    } on TimeoutException catch (_) {
      cancelToken.cancel('Timeout');
      return false;
    } catch (_) {
      return false;
    }
  }
}
