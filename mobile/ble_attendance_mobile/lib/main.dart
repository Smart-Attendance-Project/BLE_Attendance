import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

const String kAdvertiseServiceUuid = '0000180D-0000-1000-8000-00805F9B34FB';
const int kRssiThreshold = -80;
const Duration kDetectionPostInterval = Duration(seconds: 10);
const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

void main() {
  runApp(const BleAttendanceApp());
}

class BleAttendanceApp extends StatelessWidget {
  const BleAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
      ),
      home: const LoginPage(),
    );
  }
}

enum AppRole { teacher, student }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _serverUrlCtrl = TextEditingController();
  AppRole _role = AppRole.student;
  bool _isRegister = false;
  bool _loading = false;
  bool _ready = false;

  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _api.init();
    _serverUrlCtrl.text = _api.baseUrl;
    if (!mounted) {
      return;
    }
    setState(() {
      _ready = true;
    });
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _serverUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
    });

    try {
      await _api.setBaseUrl(_serverUrlCtrl.text);

      if (_isRegister) {
        await _api.register(
          fullName: _nameCtrl.text.trim(),
          identifier: _identifierCtrl.text.trim().toUpperCase(),
          password: _passwordCtrl.text,
          role: _role,
        );
      }

      final token = await _api.login(
        identifier: _identifierCtrl.text.trim().toUpperCase(),
        password: _passwordCtrl.text,
      );
      await _api.saveToken(token);

      if (!mounted) {
        return;
      }

      if (_role == AppRole.teacher) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TeacherPage(api: _api)),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => StudentPage(api: _api)),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _loading = true;
    });
    try {
      await _api.setBaseUrl(_serverUrlCtrl.text);
      await _api.healthCheck();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server connection successful.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Attendance Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<AppRole>(
              segments: const [
                ButtonSegment(value: AppRole.student, label: Text('Student')),
                ButtonSegment(value: AppRole.teacher, label: Text('Teacher')),
              ],
              selected: {_role},
              onSelectionChanged: (set) {
                setState(() {
                  _role = set.first;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_isRegister)
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _identifierCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: _role == AppRole.teacher ? 'Teacher ID (e.g. T001)' : 'Student ID (e.g. 25CE099)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.1.10:8000',
              ),
            ),
            const SizedBox(height: 8),
            const Text('For real phones use http://<laptop-ip>:8000'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading || !_ready ? null : _submit,
              child: Text(_loading ? 'Please wait...' : (_isRegister ? 'Register and Login' : 'Login')),
            ),
            OutlinedButton(
              onPressed: _loading || !_ready ? null : _testConnection,
              child: const Text('Test Connection'),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      setState(() {
                        _isRegister = !_isRegister;
                      });
                    },
              child: Text(_isRegister ? 'Already have account? Login' : 'New user? Register'),
            ),
            const SizedBox(height: 8),
            const Text('Prototype tip: keep app open during class on iOS.'),
          ],
        ),
      ),
    );
  }
}

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  final _subjectCtrl = TextEditingController(text: 'Distributed Systems');
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  String? _sessionId;
  String? _token;
  bool _loading = false;
  bool _isAdvertising = false;
  List<Map<String, dynamic>> _detections = const [];
  Map<String, dynamic>? _summary;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _blePeripheral.stop();
    super.dispose();
  }

  Future<void> _startSession() async {
    setState(() {
      _loading = true;
    });
    try {
      final permsOk = await _ensureBlePermissions();
      if (!permsOk) {
        throw Exception('Bluetooth permissions are required.');
      }

      final session = await widget.api.startSession(_subjectCtrl.text.trim());
      _sessionId = session['id'] as String;
      _token = session['token'] as String;

      final data = AdvertiseData(
        serviceUuid: kAdvertiseServiceUuid,
        includeDeviceName: false,
        manufacturerId: 0x004C,
        manufacturerData: Uint8List.fromList(_token!.codeUnits),
      );
      await _blePeripheral.start(advertiseData: data);
      _isAdvertising = true;

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _endSession() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }

    setState(() {
      _loading = true;
    });
    try {
      await widget.api.endSession(sessionId);
      await _blePeripheral.stop();
      _isAdvertising = false;
      await _refreshSummary();
      if (mounted) {
        setState(() {
          _sessionId = null;
          _token = null;
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshDetections() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    try {
      final rows = await widget.api.getDetections(sessionId);
      if (mounted) {
        setState(() {
          _detections = rows.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshSummary() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    try {
      final summary = await widget.api.getAttendanceSummary(sessionId);
      if (mounted) {
        setState(() {
          _summary = summary;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading || _sessionId != null ? null : _startSession,
              child: const Text('Start Session + BLE Broadcast'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _loading || _sessionId == null ? null : _endSession,
              child: const Text('End Session'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sessionId == null ? null : _refreshDetections,
                    child: const Text('Refresh Detections'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sessionId == null ? null : _refreshSummary,
                    child: const Text('Refresh Summary'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Session ID: ${_sessionId ?? '-'}'),
            Text('Token: ${_token ?? '-'}'),
            Text('BLE Advertising: ${_isAdvertising ? 'ON' : 'OFF'}'),
            if (_summary != null)
              Text(
                'Present: ${_summary!['present_students']}/${_summary!['total_students']}',
              ),
            const SizedBox(height: 12),
            const Text('Recent detections:'),
            Expanded(
              child: ListView.builder(
                itemCount: _detections.length,
                itemBuilder: (context, index) {
                  final row = _detections[index];
                  return ListTile(
                    title: Text('${row['student_id']} (${row['student_name']})'),
                    subtitle: Text('RSSI: ${row['rssi']} | ${row['detected_at']}'),
                    trailing: Icon(
                      (row['proximity_ok'] as bool?) == true ? Icons.check_circle : Icons.cancel,
                      color: (row['proximity_ok'] as bool?) == true ? Colors.green : Colors.red,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StudentPage extends StatefulWidget {
  const StudentPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final LocalAuthentication _localAuth = LocalAuthentication();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  String? _sessionId;
  int? _latestRssi;
  bool _proximityOk = false;
  bool _scanning = false;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _ensureBlePermissions();
    await _loadActiveSession();
    await _startScan();
  }

  Future<void> _loadActiveSession() async {
    try {
      final session = await widget.api.getActiveSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionId = session['id'] as String;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _sessionId = null;
        });
      }
    }
  }

  Future<void> _startScan() async {
    if (_scanning) {
      return;
    }
    setState(() {
      _scanning = true;
    });

    _scanSub = _ble
        .scanForDevices(
          withServices: [Uuid.parse(kAdvertiseServiceUuid)],
          scanMode: ScanMode.lowLatency,
        )
        .listen((device) async {
          final sessionId = _sessionId;
          if (sessionId == null) {
            return;
          }

          final rssi = device.rssi;
          final ok = rssi > kRssiThreshold;
          setState(() {
            _latestRssi = rssi;
            _proximityOk = ok;
          });

          final now = DateTime.now();
          if (now.difference(_lastSentAt) < kDetectionPostInterval) {
            return;
          }

          try {
            await widget.api.submitDetection(
              sessionId: sessionId,
              rssi: rssi,
              proximityOk: ok,
            );
            _lastSentAt = now;
          } catch (_) {}
        }, onError: (_) {
          if (mounted) {
            setState(() {
              _scanning = false;
            });
          }
        });
  }

  Future<void> _finalizeWithBiometric() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }

    try {
      final canAuth = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuth) {
        throw Exception('Biometric/passcode auth is not available on this device.');
      }

      final success = await _localAuth.authenticate(
        localizedReason: 'Authenticate to finalize attendance',
        persistAcrossBackgrounding: true,
      );
      if (!success) {
        return;
      }

      final attendance = await widget.api.finalizeAttendance(sessionId);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Finalized. Present: ${attendance['is_present']} | Ratio: ${attendance['presence_ratio']}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _proximityOk ? Colors.green : Colors.red;
    return Scaffold(
      appBar: AppBar(title: const Text('Student Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Active Session: ${_sessionId ?? 'Not found'}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_proximityOk ? 'In range' : 'Out of range'),
              ],
            ),
            const SizedBox(height: 8),
            Text('Latest RSSI: ${_latestRssi ?? '-'}'),
            Text('Scanning: ${_scanning ? 'ON' : 'OFF'}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _finalizeWithBiometric,
              child: const Text('Finalize Attendance (Biometric)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _loadActiveSession,
              child: const Text('Refresh Active Session'),
            ),
          ],
        ),
      ),
    );
  }
}

class ApiClient {
  ApiClient();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: kDefaultApiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String _baseUrl = kDefaultApiBaseUrl;

  String get baseUrl => _baseUrl;

  Future<void> init() async {
    final saved = await _storage.read(key: 'api_base_url');
    if (saved != null && saved.trim().isNotEmpty) {
      final normalized = _normalizeBaseUrl(saved);
      _baseUrl = normalized;
      _dio.options.baseUrl = normalized;
    }
  }

  Future<void> setBaseUrl(String input) async {
    final normalized = _normalizeBaseUrl(input);
    _baseUrl = normalized;
    _dio.options.baseUrl = normalized;
    await _storage.write(key: 'api_base_url', value: normalized);
  }

  Future<void> healthCheck() async {
    await _dio.get('/health');
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: 'token', value: token);
  }

  Future<String?> _token() async {
    return _storage.read(key: 'token');
  }

  Future<Map<String, dynamic>> _authedGet(String path) async {
    final token = await _token();
    final response = await _dio.get(
      path,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> _authedGetList(String path) async {
    final token = await _token();
    final response = await _dio.get(
      path,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> _authedPost(String path, Map<String, dynamic> data) async {
    final token = await _token();
    final response = await _dio.post(
      path,
      data: data,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> register({
    required String fullName,
    required String identifier,
    required String password,
    required AppRole role,
  }) async {
    await _dio.post('/auth/register', data: {
      'full_name': fullName,
      'role': role.name,
      'identifier': identifier,
      'password': password,
    });
  }

  Future<String> login({required String identifier, required String password}) async {
    final response = await _dio.post('/auth/login', data: {
      'identifier': identifier,
      'password': password,
    });
    final json = Map<String, dynamic>.from(response.data as Map);
    return json['access_token'] as String;
  }

  Future<Map<String, dynamic>> startSession(String subject) {
    return _authedPost('/sessions', {'subject': subject});
  }

  Future<Map<String, dynamic>> endSession(String sessionId) {
    return _authedPost('/sessions/$sessionId/end', {});
  }

  Future<Map<String, dynamic>> getActiveSession() {
    return _authedGet('/sessions/active');
  }

  Future<Map<String, dynamic>> submitDetection({
    required String sessionId,
    required int rssi,
    required bool proximityOk,
  }) {
    return _authedPost('/detections', {
      'session_id': sessionId,
      'rssi': rssi,
      'proximity_ok': proximityOk,
    });
  }

  Future<Map<String, dynamic>> finalizeAttendance(String sessionId) {
    return _authedPost('/attendance/finalize', {
      'session_id': sessionId,
      'biometric_verified': true,
    });
  }

  Future<List<dynamic>> getDetections(String sessionId) {
    return _authedGetList('/teacher/sessions/$sessionId/detections');
  }

  Future<Map<String, dynamic>> getAttendanceSummary(String sessionId) {
    return _authedGet('/teacher/sessions/$sessionId/attendance-summary');
  }
}

Future<bool> _ensureBlePermissions() async {
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.locationWhenInUse,
  ].request();

  for (final status in statuses.values) {
    if (!status.isGranted && !status.isLimited) {
      return false;
    }
  }
  return true;
}

String _friendlyError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Cannot reach server. Check Server URL and Wi-Fi.';
    }
    if (data is Map && data['detail'] != null) {
      return '${data['detail']} (HTTP ${status ?? '-'})';
    }
    return 'Network/API error (HTTP ${status ?? '-'})';
  }
  return error.toString();
}

String _normalizeBaseUrl(String input) {
  final raw = input.trim();
  if (raw.isEmpty) {
    throw Exception('Server URL is required.');
  }

  final withScheme = raw.startsWith('http://') || raw.startsWith('https://')
      ? raw
      : 'http://$raw';

  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) {
    throw Exception('Enter a valid server URL.');
  }

  return withScheme.endsWith('/') ? withScheme.substring(0, withScheme.length - 1) : withScheme;
}
