import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Merkezi yapilandirma.
// 10.0.2.2 -> Android emulatorunun host makineye (localhost) erisim adresidir.
// Gercek cihazda buraya sunucu IP'sini yazin (or. http://192.168.1.10:8000).
const String kApiBaseUrl = 'http://10.0.2.2:8000';
const String kSyncEndpoint = '/api/v1/delivery/sync';
const String kPendingQueueKey = 'logistep_pending_deliveries';

void main() {
  runApp(const LogiStepApp());
}

class LogiStepApp extends StatelessWidget {
  const LogiStepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogiStep',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true, // Material 3 tasarim dili
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshPendingCount();
    // Acilista bekleyen offline kayitlari senkronize etmeyi dene
    _syncPending();
  }

  // ---- 🚀 REST API HABERLESME ----
  Future<void> _scanAndSyncDocument() async {
    // BuildContext'i async oncesi yakala (lint: use_build_context_synchronously)
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);

    // Python tarafindaki DeliveryPayload modeliyle birebir eslesir
    final Map<String, dynamic> payload = {
      "delivery_id": "80012345",
      "driver_id": "DRV_HANS_01",
      "status_code": "DELIVERED",
      "gps_location": "48.6606, 8.9366", // Ehningen bolgesi koordinatlari
      // Gercek senaryoda: "image": base64Encode(imageBytes)
    };

    try {
      final response = await http
          .post(
            Uri.parse('$kApiBaseUrl$kSyncEndpoint'),
            headers: const {"Content-Type": "application/json"},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        messenger.showSnackBar(SnackBar(
          content: Text('Erfolgreich: ${data['message']}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
        // Cevrimici basariliysa bekleyen kayitlari da gonder
        await _syncPending();
      } else {
        // Sunucu hata dondurduyse lokal kayit mekanizmasi tetiklenir
        await _saveToLocalDatabase(payload, messenger);
      }
    } catch (_) {
      // Internet kesikse veya Timeout olursa lokal kayit mekanizmasi tetiklenir
      await _saveToLocalDatabase(payload, messenger);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---- 🛡 CEVRIMDISI MOD (OFFLINE) YONETIMI ----
  Future<void> _saveToLocalDatabase(
    Map<String, dynamic> data,
    ScaffoldMessengerState messenger,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(kPendingQueueKey) ?? <String>[];
    queue.add(json.encode(data));
    await prefs.setStringList(kPendingQueueKey, queue);

    await _refreshPendingCount();
    messenger.showSnackBar(const SnackBar(
      content: Text('Offline-Modus: Daten lokal gespeichert. Synct spaeter.'),
      backgroundColor: Colors.orange,
      duration: Duration(seconds: 3),
    ));
  }

  // ---- 🔄 BEKLEYEN KAYITLARI SENKRONIZE ET ----
  Future<void> _syncPending() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(kPendingQueueKey) ?? <String>[];
    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (final item in queue) {
      try {
        final response = await http
            .post(
              Uri.parse('$kApiBaseUrl$kSyncEndpoint'),
              headers: const {"Content-Type": "application/json"},
              body: item,
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) {
          remaining.add(item); // basarisiz -> kuyrukta kalsin
        }
      } catch (_) {
        remaining.add(item); // hala offline -> kuyrukta kalsin
      }
    }

    await prefs.setStringList(kPendingQueueKey, remaining);
    await _refreshPendingCount();
  }

  Future<void> _refreshPendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(kPendingQueueKey) ?? <String>[];
    if (mounted) setState(() => _pendingCount = queue.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LogiStep - Fahrer Dashboard'),
        actions: [
          Icon(
            _pendingCount == 0 ? Icons.cloud_done : Icons.cloud_off,
            color: _pendingCount == 0 ? Colors.green : Colors.orange,
          ),
          if (_pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 16),
              child: Center(
                child: Text(
                  '$_pendingCount',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )
          else
            const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ust Bilgi Karti
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Aktuelle Route: Stuttgart Depot\nFahrzeug: B-LG 2026',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const Spacer(),
            // Dinamik Ana Buton (Glance & Go - Basparmak Bolgesi)
            ElevatedButton.icon(
              onPressed: () {
                // GPS ile hedefe varildiginda tetiklenen ana aksiyon
              },
              icon: const Icon(Icons.local_shipping, size: 32),
              label: const Text('Zustellung Starten',
                  style: TextStyle(fontSize: 24)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 32),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            // Alt Ikincil Eylemler (Kamera ve Hata Bildirimi)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    // Butona basildiginda HTTP istegi tetiklenir
                    onPressed: _isLoading ? null : _scanAndSyncDocument,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner),
                    label: const Text('Beleg Scannen'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.warning_amber),
                    label: const Text('Verzoegerung'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
