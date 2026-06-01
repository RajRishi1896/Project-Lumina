import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/network/api_client.dart';

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

  /// Runs on startup to delete any abandoned .part files from crashed downloads
  Future<void> cleanUpPartialDownloads() async {
    try {
      final baseDir = await _localPath;
      final dir = Directory(baseDir);
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        for (var entity in entities) {
          if (entity is File && entity.path.endsWith('.part')) {
            await entity.delete();
            debugPrint('Garbage Collector: Deleted abandoned file ${entity.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('Garbage Collector Error: $e');
    }
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

  Future<bool> isFileDownloaded(String fileName) async {
    final baseDir = await _localPath;
    final file = File('$baseDir/$fileName');
    return await file.exists();
  }

  Future<String> getFilePath(String fileName) async {
    final baseDir = await _localPath;
    return '$baseDir/$fileName';
  }
}
