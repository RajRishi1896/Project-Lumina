import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../storage/db_helper.dart';
import '../../shared/services/connectivity_service.dart';

/// A singleton queue that persists server mutations for offline resilience.
///
/// When online, mutations are executed immediately via [ApiClient]. When
/// offline, they are persisted to the `pending_mutations` SQLite table and
/// flushed automatically once connectivity is restored via [flush].
class MutationQueue {
  static final MutationQueue _instance = MutationQueue._internal();
  factory MutationQueue() => _instance;
  MutationQueue._internal();

  /// Retry cap for every queued mutation. Quiz results must survive long
  /// outages, so the cap is the old high-priority tier's value for all.
  static const int _maxRetries = 10;

  /// Enqueues a mutation to be sent to the server.
  ///
  /// If online, executes immediately via [ApiClient] and returns the
  /// response data (or null when the method produces no body). On network
  /// failure or offline, persists to the `pending_mutations` table for
  /// later retry and returns null: the server's result is not known yet.
  Future<dynamic> enqueue(String endpoint, {required String method, required Map<String, dynamic> body}) async {
    if (ConnectivityService().isOnline) {
      try {
        return await _executeMutation(endpoint, method, body);
      } on DioException {
        // Network error: persist for retry
      }
    }
    final db = await DBHelper().database;
    await db.insert('pending_mutations', {
      'endpoint': endpoint,
      'method': method,
      'body': jsonEncode(body),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'retries': 0,
    });
    return null;
  }

  bool _flushing = false;

  /// Flushes all pending mutations from the database.
  ///
  /// Reads mutations ordered by [id] ASC and executes them sequentially to
  /// avoid overwhelming the server. Successful mutations are removed from the
  /// DB. Mutations that have exceeded [_maxRetries] are dropped and logged.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _flushOnce();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushOnce() async {
    final db = await DBHelper().database;
    final rows = await db.query('pending_mutations', orderBy: 'id ASC');
    final gen = ApiClient.sessionGeneration;
    for (final row in rows) {
      // Profile switched mid-flush: the remaining rows belong to the new
      // profile's account and must not execute under this flush. Stop; the
      // next flush (under the right token) picks them up.
      if (ApiClient.sessionGeneration != gen) return;
      final id = row['id'] as int;
      final endpoint = row['endpoint'] as String;
      final method = row['method'] as String;
      try {
        final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
        await _executeMutation(endpoint, method, body);
        await db.delete('pending_mutations', where: 'id = ?', whereArgs: [id]);
      } on DioException catch (e) {
        // Hub unreachable: leave this row and the tail for the next flush
        // instead of burning a timeout per remaining row out of order.
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError) {
          return;
        }
        // Permanent rejection (4xx bad response): retrying can never
        // succeed. Drop immediately.
        final status = e.response?.statusCode ?? 0;
        if (e.type == DioExceptionType.badResponse && status >= 400 && status < 500) {
          debugPrint('MutationQueue: dropping mutation $id ($endpoint): HTTP $status rejected permanently');
          await db.delete('pending_mutations', where: 'id = ?', whereArgs: [id]);
          continue;
        }
        final retries = (row['retries'] as int) + 1;
        if (retries >= _maxRetries) {
          debugPrint('MutationQueue: dropping mutation $id ($endpoint) after $_maxRetries retries');
          await db.delete('pending_mutations', where: 'id = ?', whereArgs: [id]);
        } else {
          await db.update('pending_mutations', {'retries': retries}, where: 'id = ?', whereArgs: [id]);
        }
      } catch (e) {
        debugPrint('MutationQueue: unexpected error flushing mutation $id ($endpoint): $e');
        // Non-Dio errors are permanent (e.g. bad JSON, missing field). Remove
        // to prevent infinite retry loop.
        await db.delete('pending_mutations', where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  /// Executes one mutation and returns the response data for body-bearing
  /// methods, or null when the method has no response body to consume.
  Future<dynamic> _executeMutation(String endpoint, String method, Map<String, dynamic> body) async {
    switch (method.toUpperCase()) {
      case 'POST':
        final response = await ApiClient.post(endpoint, data: body);
        return response.data;
      case 'PUT':
        await ApiClient.ensureInitialized();
        await ApiClient.dio.put(endpoint, data: body);
        return null;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }
}
