from pathlib import Path
import re

ROOT = Path('.')

def r(path):
    return (ROOT / path).read_text(encoding='utf-8-sig')

def w(path, text):
    (ROOT / path).write_text(text, encoding='utf-8')

def rep(path, old, new):
    text = r(path)
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'Missing pattern in {path}: {old[:80]!r}')
    w(path, text.replace(old, new, 1))

# Auth/profile switching: the DB is already profile-specific on current main.
p = 'EduMesh-Android/lib/features/auth/data/auth_service.dart'
rep(p, "import '../../../core/network/api_client.dart';", "import '../../../core/network/api_client.dart';\nimport '../../../core/storage/db_helper.dart';")
rep(p, 'await _purgeIfSwitching(username);\n\n      await _rememberUser(', 'await _activateProfile(hubGeneratedId);\n\n      await _rememberUser(')
rep(p, 'await _purgeIfSwitching(username);\n            await _secureStorage.write(key: _sessionTokenKey, value: token);', 'await _activateProfile(scholarId);\n            await _secureStorage.write(key: _sessionTokenKey, value: token);')
rep(p, 'await _purgeIfSwitching(username);\n        ApiClient.setAuth(storedToken);', 'await _activateProfile(userId);\n        ApiClient.setAuth(storedToken);')
rep(p, """    // The profile picker switches without going through logout: purge the
    // outgoing student's pending state BEFORE activating the target so it
    // can never flush under the new profile's token.
    await _purgeActiveProfileData();""", '    await _activateProfile(userId);')
text = r(p)
start = text.find('  Future<void> _purgeActiveProfileData() async {')
end = text.find('  /// Logs out locally without any network call', start)
if start >= 0 and end >= 0:
    helper = """  Future<void> _activateProfile(String profileId) async {
    final current = await _secureStorage.read(key: _userIdKey);
    if (current != profileId) {
      _sessionGeneration++;
      DownloadQueue().invalidateSession();
      ActivityTracker().resetSessionState();
      MiniPlayerController().stop();
    }
    await DBHelper().switchProfile(profileId);
  }

"""
    w(p, text[:start] + helper + text[end:])
rep(p, '  Future<void> _removeActiveProfile() async {\n    await _purgeActiveProfileData();', """  Future<void> _removeActiveProfile() async {
    _sessionGeneration++;
    DownloadQueue().invalidateSession();
    ActivityTracker().resetSessionState();
    MiniPlayerController().stop();""")

# Startup must select the active profile DB before background services run.
p = 'EduMesh-Android/lib/main.dart'
rep(p, "import 'package:edumesh_android/core/network/api_client.dart';", "import 'package:edumesh_android/core/network/api_client.dart';\nimport 'package:edumesh_android/core/storage/db_helper.dart';")
rep(p, '  bool isLoggedIn = userId != null;', '  bool isLoggedIn = userId != null;\n  await DBHelper().switchProfile(userId);')

# Activity / recent resource state must survive profile switching independently.
p = 'EduMesh-Android/lib/core/services/activity_tracker.dart'
rep(p, "import '../../shared/services/connectivity_service.dart';", "import '../../shared/services/connectivity_service.dart';\nimport '../storage/db_helper.dart';")
rep(p, """  static const String _localEventsKey = 'local_events';
  static const String _activeStudySessionKey = 'active_study_session';
  static const String _cachedAnalyticsKey = 'cached_analytics';""", """  String get _localEventsKey => 'local_events_${DBHelper().activeProfileId}';
  String get _activeStudySessionKey => 'active_study_session_${DBHelper().activeProfileId}';
  String get _cachedAnalyticsKey => 'cached_analytics_${DBHelper().activeProfileId}';""")
rep(p, '    final cutoff = DateTime.now().subtract(const Duration(days: 7));', """    final today = DateTime.now();
    final weekStart = DateTime(today.year, today.month, today.day).subtract(Duration(days: today.weekday - 1));
    final cutoff = weekStart;""")
p = 'EduMesh-Android/lib/core/services/recent_resources.dart'
rep(p, "import 'package:shared_preferences/shared_preferences.dart';", "import 'package:shared_preferences/shared_preferences.dart';\nimport '../storage/db_helper.dart';")
rep(p, "  static const _key = 'recent_resources_v1';", "  static String get _key => 'recent_resources_v1_${DBHelper().activeProfileId}';")

# Download safety: profile directory, safe filename, and fallback when Range is ignored.
p = 'EduMesh-Android/lib/shared/services/download_service.dart'
rep(p, "    final path = '${directory.path}/LuminaResources';", "    final path = '${directory.path}/LuminaResources/${DBHelper().activeProfileId}';")
rep(p, "      final baseDir = await _localPath;\n      savePath = '$baseDir/$fileName';", """      final baseDir = await _localPath;
      fileName = _safeFileName(fileName);
      savePath = '$baseDir/$fileName';""")
rep(p, """      if (startByte > 0 && response.statusCode == 200) {
        await partFile.delete();
        throw DownloadError(DownloadErrorCode.rangeNotSupported);
      }""", """      if (startByte > 0 && response.statusCode == 200) {
        await partFile.delete();
        return downloadFile(url, fileName, onProgress: onProgress);
      }""")
rep(p, '  /// Delete a downloaded file and its DB record.', """  static String _safeFileName(String value) {
    final name = value.split('/').last.split('\\\\').last;
    final safe = name.replaceAll(RegExp(r'[\\\\/:*?"<>|\\r\\n]'), '_').replaceAll('..', '_').trim();
    return safe.isEmpty ? 'download.bin' : safe;
  }

  /// Delete a downloaded file and its DB record.""")

# Mutation queue: only transport errors and 5xx are retryable.
p = 'EduMesh-Android/lib/core/services/mutation_queue.dart'
rep(p, """      } on DioException {
        // Network error: persist for retry
      }""", """      } on DioException catch (e) {
        if (!_isRetryable(e)) rethrow;
      }""")
rep(p, '  /// Executes one mutation', """  bool _isRetryable(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return status >= 500;
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout;
  }

  /// Executes one mutation""")

# Download queue generation: invalidate old tasks without spawning a second processor.
p = 'EduMesh-Android/lib/shared/services/download_queue.dart'
text = r(p)
if 'final int generation;' not in text:
    text = text.replace('  final double mtime;\n', '  final double mtime;\n  final int generation;\n', 1)
    text = text.replace("  _QueuedDownload(this.resourceId, this.url, this.fileName, {\n    this.title = '',", "  _QueuedDownload(this.resourceId, this.url, this.fileName, {\n    required this.generation,\n    this.title = '',", 1)
    text = text.replace('  bool _processing = false;\n', '  bool _processing = false;\n  int _generation = 0;\n', 1)
    text = text.replace("  void clear() {\n    _queue.clear();\n    _processing = false;", """  void invalidateSession() {
    _generation++;
    _queue.clear();
    notifyListeners();
  }

  void clear() {
    invalidateSession();""", 1)
    text = text.replace("      _queue.add(_QueuedDownload(resourceId, url, fileName,\n        title: title,", "      _queue.add(_QueuedDownload(resourceId, url, fileName,\n        generation: _generation,\n        title: title,", 1)
    text = text.replace('    _processing = true;\n    final service = FlutterBackgroundService();', '    _processing = true;\n    final processorGeneration = _generation;\n    final service = FlutterBackgroundService();', 1)
    text = text.replace('      final task = _queue.first;\n      String? path;', '      final task = _queue.first;\n      if (processorGeneration != _generation || task.generation != processorGeneration) return;\n      String? path;', 1)
    text = text.replace('        if (file != null) {\n          await DBHelper().insertDownload', '        if (file != null) {\n          if (processorGeneration != _generation || task.generation != processorGeneration) { try { await file.delete(); } catch (_) {} return; }\n          await DBHelper().insertDownload', 1)
    text = text.replace('    _processing = false;\n    notifyListeners();', '    _processing = false;\n    notifyListeners();\n    if (_queue.isNotEmpty) unawaited(_processNext());', 1)
    w(p, text)

# Search: stable filenames and preserve user-selected filters.
p = 'EduMesh-Android/lib/features/dashboard/presentation/search_page.dart'
text = r(p)
text = text.replace("final fileName = '${original.title}$ext';", "final fileName = '$resourceId$ext';", 1)
text = re.sub(r"\n\s*if \(_filteredResults\.isEmpty && _hasActiveFilters\) \{.*?\n\s*\}\n", '\n', text, count=1, flags=re.S)
w(p, text)

# Course download should not report a queued resource as a completed resource.
p = 'EduMesh-Android/lib/features/dashboard/presentation/course_player_page.dart'
text = r(p)
text = text.replace('''        } else {
          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.coursePlayerDownloadFailed)),
          );
        }''', '''        } else {
          setState(() => _isDownloading = false);
          await _loadProgress();
        }''', 1)
w(p, text)

# Untimed quiz timing; client waits for authoritative server grading when no key.
p = 'EduMesh-Android/lib/features/dashboard/presentation/quiz_player_page.dart'
text = r(p)
if 'final Stopwatch _elapsed' not in text:
    text = text.replace('  late final String _startedAt;\n', '  late final String _startedAt;\n  final Stopwatch _elapsed = Stopwatch();\n', 1)
    text = text.replace('    _startTimer();', '    _elapsed.start();\n    _startTimer();', 1)
    text = text.replace("      'time_taken_seconds': _totalTimeSeconds - _secondsRemaining,", "      'time_taken_seconds': _elapsed.elapsed.inSeconds,", 1)
    text = text.replace('    if (answerKey != null) _answerKey = answerKey;\n    _injectAnswerKey(questions);', '', 1)
    text = text.replace("_applyQuiz(Quiz.fromJson(widget.quizData!), answerKey: widget.quizData!['_answer_key'] != null ? Map<String, dynamic>.from(widget.quizData!['_answer_key']) : null);", '_applyQuiz(Quiz.fromJson(widget.quizData!));', 1)
    text = text.replace("_applyQuiz(Quiz.fromJson(quizData), answerKey: quizData['_answer_key'] != null ? Map<String, dynamic>.from(quizData['_answer_key']) : null);", '_applyQuiz(Quiz.fromJson(quizData));', 1)
    text = text.replace("_applyQuiz(Quiz.fromJson(cached), answerKey: cached['_answer_key'] != null ? Map<String, dynamic>.from(cached['_answer_key']) : null);", '_applyQuiz(Quiz.fromJson(cached));', 1)
    text = text.replace('    int correct = 0;\n    for (int i = 0; i < _questions.length; i++) {', '    int correct = 0;\n    final canGradeLocally = !_quizLacksAnswerKey();\n    for (int i = 0; i < _questions.length && canGradeLocally; i++) {', 1)
w(p, text)

# ZIM archive-aware file identity.
p = 'EduMesh-Android/lib/shared/services/zim_download_helper.dart'
text = r(p)
if '../../core/storage/db_helper.dart' not in text:
    text = text.replace("import '../../core/network/api_client.dart';", "import '../../core/network/api_client.dart';\nimport '../../core/storage/db_helper.dart;", 1)
text = text.replace('static Future<String> _articleDir(String articleId) async {', 'static Future<String> _articleDir(String articleId, String archiveId) async {', 1)
text = text.replace("return '${dir.path}/$_dirPrefix$articleId';", "final a = archiveId.isEmpty ? 'default' : archiveId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');\n    final i = articleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');\n    return '${dir.path}/zim_${DBHelper().activeProfileId}_${a}_$i';", 1)
text = text.replace('findSavedArticle(String articleId) async {', "findSavedArticle(String articleId, {String archiveId = ''}) async {", 1)
text = text.replace('final adir = await _articleDir(articleId);', 'final adir = await _articleDir(articleId, archiveId);')
text = text.replace("'article_id': articleId,\n    }).timeout", "'article_id': articleId,\n      'archive_id': archiveId,\n    }).timeout", 1)
w(p, text)

p = 'EduMesh-Android/lib/shared/services/zim_sync_service.dart'
text = r(p)
text = text.replace("  Future<void> markDownloaded(String articleId, {String title = ''}) async {\n    await DBHelper().markZimArticleDownloaded(articleId, title: title);\n    _downloadedIds.add(articleId);\n  }", """  Future<void> markDownloaded(String articleId, {String title = '', String archiveId = ''}) async {
    await DBHelper().markZimArticleDownloaded(articleId, title: title, archiveId: archiveId);
    _downloadedIds.add(archiveId.isEmpty ? articleId : '$archiveId::$articleId');
  }""", 1)
w(p, text)

# Flashcard subject metadata.
p = 'EduMesh-Android/lib/core/services/flashcard_service.dart'
text = r(p)
text = text.replace("              'title': title,\n              'source': 'hub',", "              'title': title,\n              'subject': (item['subject'] ?? '').toString(),\n              'source': 'hub',", 1)
text = text.replace("            await txn.update('flashcard_decks_local', {'title': title, 'updated_at': now},", "            await txn.update('flashcard_decks_local', {'title': title, 'subject': (item['subject'] ?? '').toString(), 'updated_at': now},", 1)
w(p, text)

# Connectivity: no operation is considered online until first heartbeat completes.
p = 'EduMesh-Android/lib/shared/services/connectivity_service.dart'
text = r(p)
if 'bool _verified = false;' not in text:
    text = text.replace('  bool _online = true;\n', '  bool _online = true;\n  bool _verified = false;\n', 1)
    text = text.replace('  bool get isOnline => _online;', '  bool get isOnline => _verified && _online;', 1)
    text = text.replace('      _online = true;\n      if (!_startupFlushed) {', '      _online = true;\n      _verified = true;\n      if (!_startupFlushed) {', 1)
    text = text.replace('      _online = false;\n    }', '      _online = false;\n      _verified = true;\n    }', 1)
w(p, text)

print('behavioral fixes applied')
