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

  static int _maxRetries(String priority) => priority == 'high' ? 10 : 3;

  /// Enqueues a mutation to be sent to the server.
  ///
  /// If online, executes immediately via [ApiClient]. On success, returns
  /// without persisting. On network failure, persists to the
  /// `pending_mutations` table for later retry. If offline, persists
  /// immediately.
  Future<void> enqueue(String endpoint, {required String method, required Map<String, dynamic> body, String priority = 'normal'}) async {
    if (ConnectivityService().isOnline) {
      try {
        await _executeMutation(endpoint, method, body);
        return;
      } on DioException {
        // Network error -- persist for retry
      }
    }
    final db = await DBHelper().database;
    await db.insert('pending_mutations', {
      'endpoint': endpoint,
      'method': method,
      'body': jsonEncode(body),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'retries': 0,
      'priority': priority,
    });
  }

  /// Flushes all pending mutations from the database.
  ///
  /// Reads mutations ordered by [id] ASC and executes them sequentially to
  /// avoid overwhelming the server. Successful mutations are removed from the
  /// DB. Mutations that have exceeded [_maxRetries] are dropped and logged.
  Future<void> flush() async {
    final db = await DBHelper().database;
    final rows = await db.query('pending_mutations', orderBy: 'id ASC');
    for (final row in rows) {
      final id = row['id'] as int;
      final endpoint = row['endpoint'] as String;
      final method = row['method'] as String;
      final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
      final priority = (row['priority'] as String?) ?? 'normal';
      final maxRetries = _maxRetries(priority);
      try {
        await _executeMutation(endpoint, method, body);
        await db.delete('pending_mutations', where: 'id = ?', whereArgs: [id]);
      } on DioException {
        final retries = (row['retries'] as int) + 1;
        if (retries >= maxRetries) {
          if (priority == 'high') {
            debugPrint('MutationQueue: DROPPED HIGH-PRIORITY mutation $id -- quiz result may never sync');
          }
          debugPrint('MutationQueue: dropping mutation $id ($endpoint) after $maxRetries retries');
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

  Future<void> _executeMutation(String endpoint, String method, Map<String, dynamic> body) async {
    switch (method.toUpperCase()) {
      case 'POST':
        await ApiClient.post(endpoint, data: body);
        break;
      case 'PUT':
        await ApiClient.ensureInitialized();
        await ApiClient.dio.put(endpoint, data: body);
        break;
      case 'DELETE':
        await ApiClient.ensureInitialized();
        await ApiClient.dio.delete(endpoint, data: body);
        break;
      case 'PATCH':
        await ApiClient.ensureInitialized();
        await ApiClient.dio.patch(endpoint, data: body);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }
}
