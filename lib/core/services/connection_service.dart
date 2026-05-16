import 'dart:async';

import 'package:dio/dio.dart';
import '../network/api_client.dart';

class ConnectionService {
  /// Attempts to ping the local node at /ping. Returns true on 2xx response.
  Future<bool> ping({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final resp = await ApiClient.get('/ping').timeout(timeout);
      if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
        return true;
      }
      return false;
    } on DioException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
