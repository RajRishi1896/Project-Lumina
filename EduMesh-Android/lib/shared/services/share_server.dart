import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/models/resource_model.dart';
import '../../core/storage/db_helper.dart';
import '../../core/utils/profile_scoped_prefs.dart';
import '../../features/auth/data/auth_service.dart';
import 'download_service.dart';

/// Peer-to-peer file sharing between students on the same WiFi hotspot.
///
/// A student who taps Download broadcasts a discovery request on UDP 8676;
/// nearby phones that have the file and the share setting ON reply with a
/// `have` message, and the file streams over TCP 8675 with Range support.
/// Pull-only: no push, no presence list, no UI beyond a settings toggle.
/// Silence by default: when the share setting is OFF this phone never
/// replies and never serves.
class ShareServer {
  /// The singleton instance of [ShareServer].
  static final ShareServer _instance = ShareServer._internal();

  /// Returns the singleton instance.
  factory ShareServer() => _instance;

  ShareServer._internal();

  /// UDP port for discovery requests and `have` replies.
  static const int kUdpPort = 8676;

  /// TCP port for range-aware file streaming.
  static const int kTcpPort = 8675;

  /// SharedPreferences key for the share setting (default OFF).
  static const String enabledPrefKey = 'share_files_enabled';

  static const String _broadcastAddress = '255.255.255.255';
  static const Duration _discoverTimeout = Duration(seconds: 2);

  /// Minimum request-title length accepted when answering a discovery.
  static const int _minTitleLength = 3;

  /// Minimum gap between request datagrams answered from one source IP.
  static const Duration _rateLimitInterval = Duration(milliseconds: 200);

  /// Cache age after which the shareable-file index is rebuilt.
  static const Duration _indexMaxAge = Duration(minutes: 5);

  /// Maximum tracked source IPs before the rate map is pruned.
  static const int _maxTrackedIps = 64;

  /// Maximum `have` replies sent per discovery request (amplification cap).
  static const int _maxRepliesPerRequest = 3;

  RawDatagramSocket? _udpSocket;
  HttpServer? _tcpServer;
  bool _started = false;

  /// Whether both listeners are currently bound and serving.
  ///
  /// False after [stop] or after a start/socket error tore the listeners
  /// down; the settings toggle reads this to reflect the real state.
  bool get isServing => _started;

  /// Last handled request time per source IP, for UDP rate limiting.
  final Map<String, DateTime> _lastRequestAt = {};

  /// Cached shareable-file index, keyed by precomputed record maps.
  List<Map<String, dynamic>>? _shareIndex;
  DateTime _indexBuiltAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _indexDirty = true;

  /// Binds the UDP and TCP listeners, but only while the share setting is ON.
  ///
  /// Idempotent: a second call while already running is a no-op. Safe to call
  /// from app startup (post-frame) and from the settings toggle.
  Future<void> start() async {
    if (_started) return;
    try {
      if (!await _isEnabled()) return;
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kUdpPort);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen(_onUdpEvent);
      _tcpServer = await HttpServer.bind(InternetAddress.anyIPv4, kTcpPort);
      _tcpServer!.listen((request) {
        unawaited(_handleHttpRequest(request));
      }, onError: (Object e, StackTrace stackTrace) {
        // A socket error kills the listener; tear down so a later toggle
        // rebinds cleanly instead of serving from a half-dead socket.
        debugPrint('ShareServer TCP listener error: $e');
        unawaited(stop());
      });
      _started = true;
      _indexDirty = true;
      unawaited(_buildShareIndex());
      debugPrint('ShareServer: listening on UDP $kUdpPort and TCP $kTcpPort');
    } catch (e) {
      debugPrint('ShareServer start failed: $e');
      await stop();
    }
  }

  /// Closes both listeners. Safe to call when never started.
  Future<void> stop() async {
    _started = false;
    try {
      _udpSocket?.close();
    } catch (_) {}
    try {
      await _tcpServer?.close(force: true);
    } catch (_) {}
    _udpSocket = null;
    _tcpServer = null;
    _shareIndex = null;
    _indexDirty = true;
    _lastRequestAt.clear();
  }

  /// Invalidates the cached shareable-file index.
  ///
  /// Called when a download completes so the next discovery request sees the
  /// new file. The index also rebuilds when empty or older than [_indexMaxAge].
  void markIndexDirty() {
    _indexDirty = true;
  }

  /// Broadcasts a discovery request for [resource]'s title, waits 2 seconds
  /// for `have` replies, and downloads the file from the first peer found.
  ///
  /// The peer file is recorded under the local [ResourceModel.id] so it is
  /// findable in the saved library. Returns the local path, or null when no
  /// peer replied or the download failed (the caller falls back to the hub).
  Future<String?> discoverAndDownload(
    ResourceModel resource,
    String fileName, {
    required String subject,
    required String grade,
    required String type,
    Function(int, int)? onProgress,
    void Function(String name)? onPeerFound,
  }) async {
    try {
      final reply = await _discover(_newReqId(), resource.title);
      if (reply == null) return null;
      final peerResourceId = reply['resource_id']?.toString() ?? '';
      final ip = reply['_ip']?.toString() ?? reply['ip']?.toString() ?? '';
      final port = (reply['port'] as num?)?.toInt() ?? kTcpPort;
      if (ip.isEmpty || peerResourceId.isEmpty) return null;
      onPeerFound?.call(reply['name']?.toString() ?? 'Phone');
      final mtime = (reply['mtime'] as num?)?.toDouble() ?? 0;
      return await DownloadService().downloadAndTrack(
        resource.id,
        'http://$ip:$port/file/$peerResourceId',
        fileName,
        title: resource.title,
        subject: subject,
        grade: grade,
        type: type,
        mtime: mtime,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('ShareServer discoverAndDownload failed: $e');
      return null;
    }
  }

  /// Broadcasts {req_id, title} on UDP 8676 and collects `have` replies for
  /// [_discoverTimeout], deduplicated by dev+resource_id, keeping the first.
  Future<Map<String, dynamic>?> _discover(String reqId, String title) async {
    RawDatagramSocket? socket;
    try {
      final bound = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket = bound;
      bound.broadcastEnabled = true;
      final payload = utf8.encode(jsonEncode({'req_id': reqId, 'title': title}));
      bound.send(payload, InternetAddress(_broadcastAddress), kUdpPort);
      final seen = <String>{};
      Map<String, dynamic>? first;
      bound.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = bound.receive();
        if (datagram == null) return;
        try {
          final reply = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
          if (reply['req_id'] != reqId) return;
          final dev = reply['dev']?.toString() ?? '';
          final rid = reply['resource_id']?.toString() ?? '';
          if (dev.isEmpty || rid.isEmpty) return;
          if (seen.add('$dev|$rid')) {
            reply['_ip'] = datagram.address.address;
            first ??= reply;
          }
        } catch (_) {}
      });
      await Future<void>.delayed(_discoverTimeout);
      return first;
    } catch (e) {
      debugPrint('ShareServer discover failed: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  void _onUdpEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _udpSocket?.receive();
    if (datagram == null) return;
    unawaited(_handleUdpRequest(datagram));
  }

  /// Handles a discovery request: unicasts a `have` reply for every downloaded
  /// record whose title matches, but only while sharing is ON.
  ///
  /// Requests are rate-limited per source IP and titles shorter than
  /// [_minTitleLength] chars get no reply, to blunt UDP-flood enumeration.
  Future<void> _handleUdpRequest(Datagram datagram) async {
    try {
      if (!await _isEnabled()) return;
      if (!_rateAllow(datagram.address.address)) return;
      final data = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final reqId = data['req_id']?.toString() ?? '';
      final title = (data['title']?.toString() ?? '').trim().toLowerCase();
      if (reqId.isEmpty || title.length < _minTitleLength) return;
      final downloads = await _shareableRecords();
      if (downloads.isEmpty) return;
      final deviceId = await _deviceId();
      final name = await _deviceName();
      final ip = await _localIp();
      var replies = 0;
      for (final record in downloads) {
        if (replies >= _maxRepliesPerRequest) break;
        final recordTitle = record['title'] as String? ?? '';
        if (recordTitle.isEmpty) continue;
        if (!recordTitle.contains(title) && !title.contains(recordTitle)) continue;
        replies++;
        final reply = jsonEncode({
          'req_id': reqId,
          'dev': deviceId,
          'name': name,
          'resource_id': record['resource_id'] ?? '',
          'title': record['title'],
          'size': record['size'],
          'mtime': record['mtime'],
          'ip': ip,
          'port': kTcpPort,
        });
        _udpSocket?.send(utf8.encode(reply), datagram.address, datagram.port);
      }
    } catch (e) {
      debugPrint('ShareServer request handler failed: $e');
    }
  }

  /// True when [ip] is not requesting faster than [_rateLimitInterval] apart.
  bool _rateAllow(String ip) {
    final now = DateTime.now();
    final last = _lastRequestAt[ip];
    if (last != null && now.difference(last) < _rateLimitInterval) return false;
    _lastRequestAt[ip] = now;
    if (_lastRequestAt.length > _maxTrackedIps) {
      final cutoff = now.subtract(const Duration(seconds: 10));
      _lastRequestAt.removeWhere((_, t) => t.isBefore(cutoff));
    }
    return true;
  }

  /// The cached shareable-file index, rebuilt when dirty, empty, or stale.
  Future<List<Map<String, dynamic>>> _shareableRecords() {
    if (!_indexDirty &&
        _shareIndex != null &&
        DateTime.now().difference(_indexBuiltAt) <= _indexMaxAge) {
      return Future.value(_shareIndex);
    }
    return _buildShareIndex();
  }

  /// Rebuilds the shareable-file index in one pass: DB scan + file stat per
  /// downloaded record, cached until the next download completes.
  // ponytail: two concurrent UDP requests may both rebuild; the scan is
  // idempotent and rare, so no in-flight dedup needed.
  Future<List<Map<String, dynamic>>> _buildShareIndex() async {
    try {
      final downloads = await DBHelper().getDownloadedResources();
      final records = <Map<String, dynamic>>[];
      for (final record in downloads) {
        final title = (record['title']?.toString() ?? '').trim().toLowerCase();
        final localPath = record['local_path']?.toString() ?? '';
        if (title.isEmpty || localPath.isEmpty) continue;
        int size = 0;
        double mtime = (record['mtime'] as num?)?.toDouble() ?? 0;
        try {
          final file = File(localPath);
          if (!await file.exists()) continue;
          size = await file.length();
          if (mtime <= 0) {
            mtime = (await file.stat()).modified.millisecondsSinceEpoch.toDouble();
          }
        } catch (_) {
          continue;
        }
        records.add({
          'resource_id': record['resource_id']?.toString() ?? '',
          'title': title,
          'local_path': localPath,
          'size': size,
          'mtime': mtime,
        });
      }
      _shareIndex = records;
      _indexBuiltAt = DateTime.now();
      _indexDirty = false;
      return records;
    } catch (e) {
      debugPrint('ShareServer index build failed: $e');
      _indexDirty = true;
      return _shareIndex ?? [];
    }
  }

  /// Serves GET /file/{resource_id} with Range support for `.part` resume.
  ///
  /// The served path comes ONLY from the downloads table row for that resource
  /// id (never from the request), which makes path traversal impossible.
  Future<void> _handleHttpRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (!path.startsWith('/file/')) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final resourceId = Uri.decodeComponent(path.substring('/file/'.length));
      if (resourceId.isEmpty) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final downloads = await DBHelper().getDownloadedResources();
      Map<String, dynamic>? record;
      for (final r in downloads) {
        if (r['resource_id'] == resourceId) {
          record = r;
          break;
        }
      }
      final dbPath = record?['local_path'] as String?;
      if (dbPath == null || dbPath.isEmpty || !await File(dbPath).exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final file = File(dbPath);
      final length = await file.length();
      var start = 0;
      var end = length - 1;
      var partial = false;
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parsed = _parseRange(rangeHeader, length);
        if (parsed == null) {
          // Not a usable byte range, serve the full file (200).
        } else if (!parsed.satisfiable) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers
              .set(HttpHeaders.contentRangeHeader, 'bytes */$length');
          await response.close();
          return;
        } else {
          start = parsed.start;
          end = parsed.end;
          partial = true;
        }
      }
      response.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
      if (partial) {
        response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
      }
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentType = ContentType('application', 'octet-stream');
      response.contentLength = end - start + 1;
      await response.addStream(file.openRead(start, end + 1));
      await response.close();
    } catch (e) {
      debugPrint('ShareServer http handler failed: $e');
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Parses a single-part `Range: bytes=start-end` header against [length].
  ///
  /// Also accepts the suffix form `bytes=-n` (the last n bytes; a suffix
  /// longer than the file yields the whole file). Returns null when the
  /// header is not a usable byte range (serve full 200). Returns
  /// `satisfiable: false` for out-of-bounds or inverted ranges, which must
  /// be answered with 416 and `Content-Range: bytes */length`. Valid ranges
  /// are clamped to the file size and returned for a 206 response.
  ({int start, int end, bool satisfiable})? _parseRange(String header, int length) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)\s*$').firstMatch(header);
    if (match == null) return null;
    final startGroup = match.group(1)!;
    final endGroup = match.group(2)!;
    if (startGroup.isEmpty) {
      if (endGroup.isEmpty) return null;
      final n = int.tryParse(endGroup) ?? -1;
      if (n <= 0 || length <= 0) {
        return (start: 0, end: 0, satisfiable: false);
      }
      return (start: length >= n ? length - n : 0, end: length - 1, satisfiable: true);
    }
    final start = int.tryParse(startGroup) ?? -1;
    if (start < 0 || start >= length) {
      return (start: 0, end: 0, satisfiable: false);
    }
    var end = length - 1;
    if (endGroup.isNotEmpty) {
      final parsedEnd = int.tryParse(endGroup) ?? -1;
      if (parsedEnd < 0 || parsedEnd < start) {
        return (start: 0, end: 0, satisfiable: false);
      }
      if (parsedEnd < end) end = parsedEnd;
    }
    return (start: start, end: end, satisfiable: true);
  }

  Future<bool> _isEnabled() async {
    try {
      return await ProfileScopedPrefs.getBool(enabledPrefKey);
    } catch (_) {
      return false;
    }
  }

  /// The last 4 characters of the user id, used as the peer device id.
  Future<String> _deviceId() async {
    try {
      final userId = await AuthService().getUniqueUserId();
      if (userId != null && userId.isNotEmpty) {
        return userId.length >= 4 ? userId.substring(userId.length - 4) : userId;
      }
    } catch (_) {}
    return '0000';
  }

  /// The peer-facing device name: display name, else username, else Phone-xxxx.
  Future<String> _deviceName() async {
    try {
      final name = await AuthService().getDisplayName();
      if (name != null && name.isNotEmpty) return name;
      final username = await AuthService().getLoggedUsername();
      if (username != null && username.isNotEmpty) return username;
      final userId = await AuthService().getUniqueUserId();
      if (userId != null && userId.length >= 4) {
        return 'Phone-${userId.substring(userId.length - 4)}';
      }
    } catch (_) {}
    return 'Phone';
  }

  /// The first non-loopback IPv4 address, for the informational `ip` field.
  Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final a = addr.address;
          if (!a.startsWith('127.') && !a.startsWith('169.254.')) return a;
        }
      }
    } catch (_) {}
    return '0.0.0.0';
  }

  /// A random v4-shaped request id. No uuid package needed for uniqueness
  /// within a single discovery round.
  String _newReqId() {
    final r = Random.secure();
    String h(int len) => List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${h(4)}-${h(12)}';
  }
}
