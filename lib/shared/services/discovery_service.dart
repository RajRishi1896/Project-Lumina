import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  String? _serverIp;
  String? get serverIp => _serverIp;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  Future<void> startDiscovery({Function(String)? onFound}) async {
    if (_isSearching) return;
    _isSearching = true;

    try {
      final RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888);
      debugPrint('Listening for Lumina Beacon on port 8888...');

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? dg = socket.receive();
          if (dg != null) {
            final String message = utf8.decode(dg.data);
            if (message.startsWith('LUMINA_SERVER_IP:')) {
              final String ip = message.split(':')[1];
              debugPrint('Lumina Server Found: $ip');
              _serverIp = ip;
              _isSearching = false;
              socket.close();
              if (onFound != null) onFound(ip);
            }
          }
        }
      });

      // Timeout after 30 seconds if not found
      Future.delayed(const Duration(seconds: 30), () {
        if (_isSearching) {
          debugPrint('Discovery timeout');
          _isSearching = false;
          socket.close();
        }
      });
    } catch (e) {
      debugPrint('Discovery error: $e');
      _isSearching = false;
    }
  }
}
