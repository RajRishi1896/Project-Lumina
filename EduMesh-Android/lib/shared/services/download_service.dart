import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/db_helper.dart';
import 'share_server.dart';

class DownloadService {

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/LuminaResources';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  Future<File?> downloadFile(String url, String fileName, {Function(int, int)? onProgress}) async {
    String? savePath;
    String? partPath;
    try {
      await ApiClient.ensureInitialized();
      
      final baseDir = await _localPath;
      savePath = '$baseDir/$fileName';
      partPath = '$savePath.part';
      
      int startByte = 0;
      final partFile = File(partPath);
      if (await partFile.exists()) {
        final len = await partFile.length();
        if (len > 0) {
          final modified = (await partFile.stat()).modified;
          if (DateTime.now().difference(modified) >= const Duration(seconds: 5)) {
            startByte = len;
          }
        }
        if (startByte == 0) {
          await partFile.delete();
        }
      }
      
      // Stream the response to disk chunk-by-chunk: buffering the whole file
      // in RAM (ResponseType.bytes) OOM-crashes low-end devices on videos.
      // Range header + FileMode.append keeps .part resume working.
      final response = await ApiClient.dio.get<ResponseBody>(
        url,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.stream,
          headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
        ),
      );

      // Server ignored Range header — .part file is corrupt, restart
      if (startByte > 0 && response.statusCode == 200) {
        await partFile.delete();
        throw Exception('RANGE_NOT_SUPPORTED');
      }

      final sink = partFile.openWrite(mode: FileMode.append);
      try {
        // ponytail: IOSink is a StreamConsumer<List<int>>; cast to the
        // Uint8List-typed consumer pipe() expects. No buffer, no copy.
        await response.data!.stream
            .pipe(sink as StreamConsumer<Uint8List>);
      } finally {
        await sink.close();
      }

      if (await partFile.length() == 0) {
        await partFile.delete();
        throw Exception('EMPTY_RESPONSE');
      }

      if (await partFile.exists()) {
        await partFile.rename(savePath);
      }
      
      return File(savePath);
    } on DioException catch (e) {
      // .part file remains for resume on next attempt
      if (e.error is FileSystemException || e.message?.contains('No space left on device') == true) {
        throw Exception('STORAGE_FULL');
      }
      debugPrint('Download network error: $e');
      throw Exception('NETWORK_ERROR');
    } catch (e) {
      // .part file remains for resume on next attempt
      debugPrint('Unexpected download error: $e');
      throw Exception('UNKNOWN_ERROR');
    }
  }

  /// Download a file and record it in the local DB.
  /// Returns the local file path on success, null on failure.
  Future<String?> downloadAndTrack(
    String resourceId,
    String url,
    String fileName, {
    String title = '',
    String subject = '',
    String grade = '',
    String type = '',
    double mtime = 0,
    Function(int, int)? onProgress,
  }) async {
    try {
      final file = await downloadFile(url, fileName, onProgress: onProgress);
      if (file != null) {
        await DBHelper().insertDownload(resourceId, file.path, title, subject, grade, type, mtime: mtime);
        // A new shareable file exists — the ShareServer index must reflect it.
        ShareServer().markIndexDirty();
        return file.path;
      }
      return null;
    } catch (e) {
      debugPrint('DownloadService: downloadAndTrack failed: $e');
      if (e is Exception && e.toString().contains('STORAGE_FULL')) rethrow;
      return null;
    }
  }

  /// Delete a downloaded file and its DB record.
  Future<void> deleteDownload(String resourceId) async {
    try {
      final db = DBHelper();
      final downloads = await db.getDownloadedResources();
      final match = downloads.where((d) => d['resource_id'] == resourceId);
      if (match.isNotEmpty) {
        final localPath = match.first['local_path'] as String?;
        if (localPath != null) {
          final file = File(localPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      await db.removeDownload(resourceId);
    } catch (e) {
      debugPrint('DownloadService: deleteDownload failed: $e');
    }
  }

  static Future<void> cleanStaleParts(Duration maxAge) async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${baseDir.path}/LuminaResources');
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity.path.endsWith('.part')) {
          final stat = await entity.stat();
          if (DateTime.now().difference(stat.modified) > maxAge) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }
}
