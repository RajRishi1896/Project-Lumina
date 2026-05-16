import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class DownloadService {
  final Dio _dio = Dio();

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
    try {
      final baseDir = await _localPath;
      final savePath = '$baseDir/$fileName';
      
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
      );
      
      return File(savePath);
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
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
