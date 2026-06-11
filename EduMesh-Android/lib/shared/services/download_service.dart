import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/db_helper.dart';

/// Service that manages file downloads from the Lumina hub to local storage.
///
/// Provides download-to-file with progress callbacks, resume-safe `.part` file
/// handling, local database tracking, and an offline-aware pending-download
/// queue. All downloaded files are stored under `LuminaResources/` within the
/// app's documents directory.
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

  /// Downloads a file. Throws an exception if storage is full.
  Future<File?> downloadFile(String url, String fileName, {Function(int, int)? onProgress}) async {
    String? savePath;
    String? partPath;
    try {
      await WakelockPlus.enable(); // EDGE CASE: Prevent Pocket Sleep WiFi Drops
      
      await ApiClient.ensureInitialized();
      
      final baseDir = await _localPath;
      savePath = '$baseDir/$fileName';
      partPath = '$savePath.part';
      
      await ApiClient.dio.download(
        url,
        partPath, // Download to the temporary .part file
        onReceiveProgress: onProgress,
      );
      
      // If successful, rename the .part file to the actual file name
      final downloadedPart = File(partPath);
      if (await downloadedPart.exists()) {
        await downloadedPart.rename(savePath);
      }
      
      return File(savePath);
    } on DioException catch (e) {
      // Clean up the .part file on failure
      if (partPath != null) {
        final partialFile = File(partPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      }
      
      if (e.error is FileSystemException || e.message?.contains('No space left on device') == true) {
        throw Exception("STORAGE_FULL");
      }
      debugPrint('Download network error: $e');
      throw Exception("NETWORK_ERROR");
    } catch (e) {
      if (partPath != null) {
        final partialFile = File(partPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      }
      debugPrint('Unexpected download error: $e');
      throw Exception("UNKNOWN_ERROR");
    } finally {
      await WakelockPlus.disable(); // Release wake lock
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
        return file.path;
      }
      return null;
    } catch (e) {
      debugPrint("DownloadService: downloadAndTrack failed: $e");
      return null;
    }
  }

  /// Check if a resource has been downloaded.
  Future<bool> isDownloaded(String resourceId) async {
    final downloaded = await DBHelper().getDownloadedIds();
    return downloaded.contains(resourceId);
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
      debugPrint("DownloadService: deleteDownload failed: $e");
    }
  }

  /// Get all downloaded resource IDs.
  Future<Set<String>> getAllDownloadedIds() async {
    return await DBHelper().getDownloadedIds();
  }

  /// Add a resource to the persisted pending-download queue (offline-safe).
  Future<void> addPendingDownload(String resourceId, String url, String fileName, {
    String title = '',
    String subject = '',
    String grade = '',
    String type = '',
    double mtime = 0,
  }) async {
    await DBHelper().addPendingDownload(resourceId, url, fileName,
      title: title, subject: subject, grade: grade, type: type, mtime: mtime);
  }

  /// Get all pending (offline-queued) downloads.
  Future<List<Map<String, dynamic>>> getAllPendingDownloads() async {
    return await DBHelper().getAllPendingDownloads();
  }

  /// Get set of pending download IDs.
  Future<Set<String>> getAllPendingIds() async {
    return await DBHelper().getPendingIds();
  }

  /// Clear all pending downloads from the persisted queue.
  Future<void> clearAllPendingDownloads() async {
    await DBHelper().clearAllPendingDownloads();
  }

  /// Remove a single pending download.
  Future<void> removePendingDownload(String resourceId) async {
    await DBHelper().removePendingDownload(resourceId);
  }

  /// Check if a resource has been downloaded OR is pending.
  Future<bool> isDownloadedOrPending(String resourceId) async {
    final downloaded = await DBHelper().getDownloadedIds();
    if (downloaded.contains(resourceId)) return true;
    final pending = await DBHelper().getPendingIds();
    return pending.contains(resourceId);
  }
}
