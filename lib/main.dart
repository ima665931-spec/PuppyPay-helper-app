import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kApiBase = 'https://puppy-pay-backend.vercel.app/api/device';
const String kAppVersion = '1.0.0';

// Packages that typically post UPI receive notifications
const Set<String> kUpiPackages = {
  'com.phonepe.app',
  'com.google.android.apps.nbu.paisa.user',
  'net.one97.paytm',
  'in.org.npci.upiapp',
  'com.dreamplug.androidapp',
  'com.whatsapp',
  'com.whatsapp.w4b',
  'com.axis.mobile',
  'com.sbi.SBIFreedomPlus',
  'com.csam.icici.bank.imobile',
  'com.msf.kbank.mobile',
  'com.bankofbaroda.upi',
  'com.snapwork.hdfc',
  'com.enstage.wibmo.usd',
  'com.mycompany.app.bbsc',
  'com.finopaymentbank.finobank',
  'com.freecharge.android',
  'com.mobikwik_new',
  'com.amazon.mobile.shopping',
  'com.phonepe.app.business',
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HelperApp());
}

class HelperApp extends StatelessWidget {
  const HelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PuppyPay Helper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF22C55E),
        useMaterial3: true,
      ),
      home: const Gate(),
    );
  }
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  String? secret;
  String? deviceName;
  String? upiId;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      secret = p.getString('device_secret');
      deviceName = p.getString('device_name');
      upiId = p.getString('device_upi');
      loading = false;
    });
  }

  void _onConnected(Map<String, dynamic> info) {
    setState(() {
      secret = info['secret'] as String?;
      deviceName = info['name'] as String?;
      upiId = info['upiId'] as String?;
    });
  }

  Future<void> _disconnect() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('device_secret');
    if (s != null) {
      try {
        await http.post(
          Uri.parse('$kApiBase/disconnect'),
          headers: {'Content-Type': 'application/json', 'X-Device-Secret': s},
          body: '{}',
        );
      } catch (_) {}
    }
    await p.remove('device_secret');
    await p.remove('device_name');
    await p.remove('device_upi');
    await p.remove('device_code');
    setState(() {
      secret = null;
      deviceName = null;
      upiId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (secret == null || secret!.isEmpty) {
      return ConnectPage(onConnected: _onConnected);
    }
    return HomePage(
      secret: secret!,
      deviceName: deviceName ?? 'Device',
      upiId: upiId ?? '',
      onDisconnect: _disconnect,
    );
  }
}

class ConnectPage extends StatefulWidget {
  final void Function(Map<String, dynamic> info) onConnected;
  const ConnectPage({super.key, required this.onConnected});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final codeCtrl = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> _connect() async {
    final code = codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => error = 'Device code required');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      String phoneModel = '';
      String androidVersion = '';
      try {
        final android = await DeviceInfoPlugin().androidInfo;
        phoneModel = '${android.manufacturer} ${android.model}';
        androidVersion = 'Android ${android.version.release}';
      } catch (_) {}

      final res = await http.post(
        Uri.parse('$kApiBase/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceCode': code,
          'phoneModel': phoneModel,
          'androidVersion': androidVersion,
          'appVersion': kAppVersion,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true && data['deviceSecret'] != null) {
        final p = await SharedPreferences.getInstance();
        await p.setString('device_secret', data['deviceSecret']);
        await p.setString('device_code', code);
        final d = data['device'] ?? {};
        await p.setString('device_name', d['name']?.toString() ?? code);
        await p.setString('device_upi', d['upiId']?.toString() ?? '');
        widget.onConnected({
          'secret': data['deviceSecret'],
          'name': d['name']?.toString() ?? code,
          'upiId': d['upiId']?.toString() ?? '',
        });
      } else {
        setState(() => error = data['message']?.toString() ?? 'Connect failed');
      }
    } catch (e) {
      setState(() => error = 'Network error');
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_android, size: 56, color: Color(0xFF22C55E)),
              const SizedBox(height: 12),
              const Text('PuppyPay Helper', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Pool UPI phone — listens for payment notifications',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Device Code (from Admin Panel)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. A1B2C3D4',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : _connect,
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String secret;
  final String deviceName;
  final String upiId;
  final VoidCallback onDisconnect;
  const HomePage({
    super.key,
    required this.secret,
    required this.deviceName,
    required this.upiId,
    required this.onDisconnect,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool listenerOn = false;
  bool listening = false;
  String status = 'Starting...';
  String lastEvent = '—';
  String lastResult = '—';
  int reportCount = 0;
  int matchCount = 0;
  Timer? heartbeatTimer;
  StreamSubscription? notifSub;
  final Set<String> _seenKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    heartbeatTimer?.cancel();
    notifSub?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await _checkPermission();
    await _startListener();
    _startHeartbeat();
  }

  Future<void> _checkPermission() async {
    try {
      final ok = await NotificationListenerService.isPermissionGranted();
      setState(() => listenerOn = ok);
      if (!ok) {
        setState(() => status = 'Notification Access OFF — tap Enable');
      }
    } catch (_) {
      setState(() => status = 'Could not check notification permission');
    }
  }

  Future<void> _requestPermission() async {
    try {
      await NotificationListenerService.requestPermission();
      await Future<void>.delayed(const Duration(seconds: 1));
      await _checkPermission();
      if (listenerOn) await _startListener();
    } catch (e) {
      setState(() => status = 'Open Settings → Notification access');
    }
  }

  Future<void> _startListener() async {
    if (!listenerOn) return;
    try {
      await notifSub?.cancel();
      notifSub = NotificationListenerService.notificationsStream.listen(
        _onNotification,
        onError: (e) => debugPrint('notif stream error: $e'),
      );
      setState(() {
        listening = true;
        status = 'Listening for UPI payments';
      });
    } catch (e) {
      setState(() {
        listening = false;
        status = 'Listener failed — re-enable Notification Access';
      });
    }
  }

  void _startHeartbeat() {
    heartbeatTimer?.cancel();
    _sendHeartbeat();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) => _sendHeartbeat());
  }

  Future<void> _sendHeartbeat() async {
    try {
      int? battery;
      try {
        battery = await Battery().batteryLevel;
      } catch (_) {}
      final res = await http.post(
        Uri.parse('$kApiBase/heartbeat'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Secret': widget.secret,
        },
        body: jsonEncode({if (battery != null) 'battery': battery}),
      );
      if (res.statusCode == 401) {
        setState(() => status = 'Session expired — reconnect with code');
      }
    } catch (_) {}
  }

  /// Parse amount + optional UTR from notification text
  Map<String, dynamic>? parsePayment(String title, String body) {
    final text = ('$title\n$body').replaceAll(',', '');
    final lower = text.toLowerCase();

    // Must look like money received (not sent)
    final isCredit = RegExp(
      r'received|credited|credit|deposited|has received|ne bheje|mila|prapt|collected|payment of',
      caseSensitive: false,
    ).hasMatch(lower);
    final isDebitOnly = RegExp(r'debited|sent to|paid to|you paid|withdrawn', caseSensitive: false).hasMatch(lower) &&
        !isCredit;
    if (isDebitOnly) return null;

    // Amount patterns
    final amountPatterns = [
      RegExp(r'(?:rs\.?|inr|₹)\s*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
      RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|₹)', caseSensitive: false),
      RegExp(r'(?:amount|amt)[:\s]+([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
    ];
    double? amount;
    for (final re in amountPatterns) {
      final m = re.firstMatch(text);
      if (m != null) {
        amount = double.tryParse(m.group(1)!);
        if (amount != null && amount > 0) break;
      }
    }
    if (amount == null || amount <= 0) return null;
    // Sanity: ignore tiny / huge junk
    if (amount < 1 || amount > 500000) return null;

    // UTR / UPI ref (12 digit common)
    String? utr;
    final utrRe = RegExp(r'\b([0-9]{12})\b');
    final um = utrRe.firstMatch(text);
    if (um != null) utr = um.group(1);

    return {'amount': amount, 'utr': utr};
  }

  String _guessSource(String? packageName) {
    final p = (packageName ?? '').toLowerCase();
    if (p.contains('phonepe')) return 'phonepe';
    if (p.contains('paisa') || p.contains('google')) return 'gpay';
    if (p.contains('paytm')) return 'paytm';
    if (p.contains('npci') || p.contains('bhim')) return 'bhim';
    if (p.contains('whatsapp')) return 'whatsapp';
    if (p.isEmpty) return 'unknown';
    return p.split('.').last;
  }

  Future<void> _onNotification(ServiceNotificationEvent event) async {
    try {
      final pkg = event.packageName ?? '';
      // Prefer known UPI apps; still allow others if text looks like credit
      final title = event.title ?? '';
      final body = event.content ?? '';
      final raw = '$title | $body';

      final parsed = parsePayment(title, body);
      if (parsed == null) return;

      // Dedupe same notif
      final key = '${pkg}_${parsed['amount']}_${parsed['utr'] ?? ''}_${title.hashCode}';
      if (_seenKeys.contains(key)) return;
      _seenKeys.add(key);
      if (_seenKeys.length > 200) {
        _seenKeys.remove(_seenKeys.first);
      }

      // If not known package, only accept strong credit wording
      if (!kUpiPackages.contains(pkg)) {
        final lower = raw.toLowerCase();
        if (!lower.contains('received') && !lower.contains('credited') && !lower.contains('₹')) {
          return;
        }
      }

      setState(() {
        lastEvent = 'Rs ${parsed['amount']} · ${parsed['utr'] ?? 'no-utr'} · ${_guessSource(pkg)}';
      });

      await _reportPayment(
        amount: parsed['amount'] as double,
        utr: parsed['utr'] as String?,
        sourceApp: _guessSource(pkg),
        rawText: raw,
      );
    } catch (e) {
      debugPrint('onNotification error: $e');
    }
  }

  Future<void> _reportPayment({
    required double amount,
    String? utr,
    required String sourceApp,
    required String rawText,
  }) async {
    try {
      int? battery;
      try {
        battery = await Battery().batteryLevel;
      } catch (_) {}

      final res = await http.post(
        Uri.parse('$kApiBase/payment'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Secret': widget.secret,
        },
        body: jsonEncode({
          'amount': amount,
          if (utr != null) 'utr': utr,
          'sourceApp': sourceApp,
          'rawText': rawText,
          if (battery != null) 'battery': battery,
        }),
      );
      final data = jsonDecode(res.body);
      reportCount++;
      final match = data['matchStatus']?.toString() ?? '';
      if (match == 'matched') matchCount++;
      setState(() {
        lastResult = data['success'] == true
            ? '$match · ${data['message'] ?? ''}'
            : 'FAIL · ${data['message'] ?? res.statusCode}';
        status = 'Listening · reports $reportCount · matched $matchCount';
      });
    } catch (e) {
      setState(() => lastResult = 'Network error reporting payment');
    }
  }

  /// Manual test report (for debugging without real notif)
  Future<void> _testReport() async {
    await _reportPayment(
      amount: 1.0,
      utr: null,
      sourceApp: 'manual-test',
      rawText: 'Manual test payment Rs 1.0',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PuppyPay Helper'),
        actions: [
          IconButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Disconnect?'),
                  content: const Text('This phone will stop reporting payments.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disconnect')),
                  ],
                ),
              );
              if (ok == true) widget.onDisconnect();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: listening && listenerOn ? const Color(0xFF14532D) : const Color(0xFF450A0A),
            child: ListTile(
              leading: Icon(
                listening && listenerOn ? Icons.sensors : Icons.sensors_off,
                color: listening && listenerOn ? Colors.greenAccent : Colors.redAccent,
              ),
              title: Text(
                listening && listenerOn ? 'LISTENING' : 'NOT LISTENING',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              subtitle: Text(status),
            ),
          ),
          const SizedBox(height: 12),
          _info('Device', widget.deviceName),
          _info('UPI', widget.upiId.isEmpty ? '— (set in admin)' : widget.upiId),
          _info('Last payment seen', lastEvent),
          _info('Last server result', lastResult),
          _info('Reports / Matched', '$reportCount / $matchCount'),
          const SizedBox(height: 16),
          if (!listenerOn)
            FilledButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.notifications_active),
              label: const Text('Enable Notification Access'),
            )
          else
            FilledButton.tonal(
              onPressed: () async {
                await _checkPermission();
                await _startListener();
              },
              child: const Text('Restart listener'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _testReport,
            child: const Text('Send test Rs 1 to server'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Keep this app installed. Turn off battery optimization for PuppyPay Helper so it runs with screen off.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _info(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.white54))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
