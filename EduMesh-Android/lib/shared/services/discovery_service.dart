import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// Singleton service that discovers the Lumina hub over mDNS.
///
/// The hub advertises `EduMeshHub._http._tcp.local.` on port 8000. This
/// service resolves its IPv4 address so the app can connect on any WiFi
/// that carries a hub, without a fixed DNS name.
class HubDiscoveryService extends ChangeNotifier {
  static final HubDiscoveryService _instance = HubDiscoveryService._internal();
  factory HubDiscoveryService() => _instance;
  HubDiscoveryService._internal();

  static const String _serviceType = '_http._tcp.local.';
  static const String _instanceName = 'EduMeshHub';
  static const int _port = 8000;

  /// Whether mDNS discovery is supported on this platform.
  bool get isAvailable => !kIsWeb;

  /// Looks up the hub via mDNS and returns its base URL.
  ///
  /// Returns `http://{ip}:8000` or null if no hub is advertised, the
  /// lookup times out (4s), or multicast is unavailable.
  Future<String?> findHubBaseUrl() async {
    final client = MDnsClient();
    try {
      await client.start();
      final ptr = await client
          .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(_serviceType))
          .timeout(const Duration(seconds: 4))
          .firstWhere(
            (r) => r.domainName.startsWith('$_instanceName.'),
            orElse: () => throw StateError('hub not advertised'),
          );
      final srv = await client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
          .timeout(const Duration(seconds: 4))
          .firstWhere(
            (r) => r.target.isNotEmpty,
            orElse: () => throw StateError('no SRV record'),
          );
      final ips = await client
          .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))
          .timeout(const Duration(seconds: 4))
          .toList();
      if (ips.isEmpty) return null;
      final best = ips.firstWhere(
        (r) => !r.address.isLinkLocal,
        orElse: () => ips.first,
      );
      return 'http://${best.address.address}:$_port';
    } catch (_) {
      return null;
    } finally {
      client.stop();
    }
  }
}
