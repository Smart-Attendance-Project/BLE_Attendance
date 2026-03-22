import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String kTeacherServiceUuid = '0000180D-0000-1000-8000-00805F9B34FB';
const String kStudentServiceUuid = '0000181C-0000-1000-8000-00805F9B34FB';
const int kRssiThreshold = -88;
const Duration kTeacherDetectionBatchInterval = Duration(seconds: 30);
const Duration kTeacherPollInterval = Duration(seconds: 10);
const Duration kStudentSessionPollInterval = Duration(seconds: 15);
const int kRssiWindowSize = 8;
const Duration kProximityDebounceDuration = Duration(seconds: 3);
const int kManufacturerId = 0x004C;
const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.1.7:8000',
);

// ---------------------------------------------------------------------------
// App entry point
// ---------------------------------------------------------------------------

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

// ===========================================================================
// LOGIN PAGE
// ===========================================================================

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
  bool _wakingServer = false;
  int _wakeCountdown = 0;
  Timer? _wakeTimer;

  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _api.init();
    await _api.enablePersistentConnection();
    _serverUrlCtrl.text = _api.baseUrl;
    final token = await _api.readToken();
    if (token != null && token.isNotEmpty) {
      final roleName = await _api.readRole();
      if (!mounted) return;
      if (roleName == AppRole.teacher.name) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TeacherPage(api: _api)),
        );
        return;
      }
      if (roleName == AppRole.student.name) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => StudentPage(api: _api)),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _serverUrlCtrl.dispose();
    _wakeTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
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
      await _api.saveRole(_role.name);
      // Save identifier for BLE advertising (student) or display (teacher)
      await _api.saveIdentifier(_identifierCtrl.text.trim().toUpperCase());
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _loading = true);
    try {
      await _api.setBaseUrl(_serverUrlCtrl.text);
      await _api.healthCheck();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server connection successful.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _wakeServer() async {
    await _api.setBaseUrl(_serverUrlCtrl.text);
    setState(() {
      _wakingServer = true;
      _wakeCountdown = 60;
    });
    _wakeTimer?.cancel();
    _wakeTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_wakeCountdown <= 0) {
        timer.cancel();
        setState(() => _wakingServer = false);
        return;
      }
      setState(() => _wakeCountdown--);
      // Try health check every 10 seconds
      if (_wakeCountdown % 10 == 0 || _wakeCountdown == 59) {
        try {
          await _api.healthCheck();
          timer.cancel();
          if (mounted) {
            setState(() {
              _wakingServer = false;
              _wakeCountdown = 0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Server is ready!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (_) {
          // Server still sleeping, keep waiting
        }
      }
    });
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
              onSelectionChanged: (set) => setState(() => _role = set.first),
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
                labelText: _role == AppRole.teacher
                    ? 'Teacher ID (e.g. T001)'
                    : 'Student ID (e.g. 25CE099)',
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
              child: Text(
                _loading
                    ? 'Please wait...'
                    : (_isRegister ? 'Register and Login' : 'Login'),
              ),
            ),
            const SizedBox(height: 4),
            OutlinedButton(
              onPressed: _loading || !_ready ? null : _testConnection,
              child: const Text('Test Connection'),
            ),
            const SizedBox(height: 4),
            // Wake server button for Render free tier
            OutlinedButton.icon(
              onPressed:
                  _wakingServer || _loading || !_ready ? null : _wakeServer,
              icon: _wakingServer
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.power_settings_new),
              label: Text(
                _wakingServer
                    ? 'Waking server... ${_wakeCountdown}s'
                    : 'Wake Server (Render)',
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() => _isRegister = !_isRegister),
              child: Text(
                _isRegister
                    ? 'Already have account? Login'
                    : 'New user? Register',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// TEACHER PAGE
// ===========================================================================

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  final _subjectCtrl = TextEditingController(text: 'Distributed Systems');
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  String? _sessionId;
  String? _token;
  bool _loading = false;
  bool _isAdvertising = false;
  bool _finalizationOpen = false;
  bool _showEndConfirm = false;
  bool _isScanning = false;
  Map<String, dynamic>? _summary;
  Timer? _pollTimer;
  Timer? _batchTimer;
  StreamSubscription<DiscoveredDevice>? _scanSub;

  // Local student detection tally (teacher-side)
  final Map<String, _StudentTally> _studentTallies = {};

  // Queued detections to batch-post
  final List<Map<String, dynamic>> _pendingDetections = [];

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _loadActiveSession();
    _startPolling();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _blePeripheral.stop();
    _scanSub?.cancel();
    _pollTimer?.cancel();
    _batchTimer?.cancel();
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(kTeacherPollInterval, (_) async {
      if (!mounted || _loading) return;
      await _loadActiveSession();
      if (_sessionId != null) {
        await _refreshSummary();
      }
    });
  }

  void _startBatchPosting() {
    _batchTimer?.cancel();
    _batchTimer = Timer.periodic(kTeacherDetectionBatchInterval, (_) async {
      if (_pendingDetections.isEmpty || _sessionId == null) return;
      await _flushDetections();
    });
  }

  Future<void> _flushDetections() async {
    if (_pendingDetections.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_pendingDetections);
    _pendingDetections.clear();
    try {
      await widget.api.submitDetectionBatch(batch);
    } catch (_) {
      // Re-queue on failure
      _pendingDetections.insertAll(0, batch);
    }
  }

  Future<void> _startSession() async {
    setState(() => _loading = true);
    try {
      final permsOk = await _ensureBlePermissions();
      if (!permsOk) throw Exception('Bluetooth permissions are required.');

      // Check if BT is on
      await _ensureBluetoothEnabled();

      final session = await widget.api.startSession(_subjectCtrl.text.trim());
      _sessionId = session['id'] as String;
      _token = session['token'] as String;
      _finalizationOpen = (session['finalization_open'] as bool?) ?? false;

      // Start BLE advertising (teacher beacon)
      final data = AdvertiseData(
        serviceUuid: kTeacherServiceUuid,
        includeDeviceName: false,
        manufacturerId: kManufacturerId,
        manufacturerData: Uint8List.fromList(
          _encodeTeacherPayload(_token!, _subjectCtrl.text.trim()),
        ),
      );
      await _blePeripheral.start(advertiseData: data);
      _isAdvertising = true;

      // Start scanning for student beacons
      _startStudentScan();
      _startBatchPosting();

      // Start foreground service
      _startForegroundService('Teaching: ${_subjectCtrl.text.trim()}');

      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startStudentScan() {
    _scanSub?.cancel();
    _isScanning = true;
    _scanSub = _ble
        .scanForDevices(
          withServices: const [],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(
          (device) {
            final studentId = _extractStudentId(device);
            if (studentId == null || _sessionId == null) return;

            final rssi = device.rssi;
            final ok = rssi > kRssiThreshold;
            final now = DateTime.now();

            // Update local tally
            final tally = _studentTallies.putIfAbsent(
              studentId,
              () => _StudentTally(studentId: studentId),
            );
            tally.total++;
            if (ok) tally.hits++;
            tally.latestRssi = rssi;
            tally.latestAt = now;
            tally.inRange = ok;

            // Queue detection for batch-post
            _pendingDetections.add({
              'session_id': _sessionId,
              'student_identifier': studentId,
              'rssi': rssi,
              'proximity_ok': ok,
            });

            if (mounted) setState(() {});
          },
          onError: (_) {
            if (mounted) setState(() => _isScanning = false);
            _scheduleStudentScanRetry();
          },
          onDone: () {
            if (mounted) setState(() => _isScanning = false);
            _scheduleStudentScanRetry();
          },
        );
  }

  void _scheduleStudentScanRetry() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isScanning && _sessionId != null) {
        _startStudentScan();
      }
    });
  }

  String? _extractStudentId(DiscoveredDevice device) {
    // Student devices advertise with kStudentServiceUuid and encode
    // their student ID in manufacturer data
    if (device.manufacturerData.isEmpty) return null;

    try {
      final bytes = device.manufacturerData;
      // First 2 bytes are manufacturer ID, rest is student ID
      if (bytes.length < 4) return null;
      final idBytes = bytes.sublist(2);
      final rawId = utf8.decode(idBytes, allowMalformed: true).trim();
      // Validate looks like a student ID (alphanumeric, 5-12 chars)
      if (rawId.length >= 5 &&
          rawId.length <= 12 &&
          RegExp(r'^[A-Z0-9]+$').hasMatch(rawId)) {
        return rawId;
      }
    } catch (_) {}
    return null;
  }

  List<int> _encodeTeacherPayload(String token, String subject) {
    // Format: token(16 bytes padded) + | + subject(up to 10 bytes)
    final tokenPart = token.length > 16 ? token.substring(0, 16) : token;
    final subjectPart = subject.length > 10 ? subject.substring(0, 10) : subject;
    return utf8.encode('$tokenPart|$subjectPart');
  }

  Future<void> _endSession() async {
    var sessionId = _sessionId;
    if (sessionId == null) {
      try {
        final active = await widget.api.getActiveSession();
        sessionId = active['id'] as String;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active session to end.')),
          );
        }
        return;
      }
    }

    setState(() => _loading = true);
    try {
      // Flush remaining detections
      await _flushDetections();
      await widget.api.endSession(sessionId);
      await _blePeripheral.stop();
      _scanSub?.cancel();
      _batchTimer?.cancel();
      _isAdvertising = false;
      _isScanning = false;
      await _refreshSummary();
      FlutterForegroundTask.stopService();
      if (mounted) {
        setState(() {
          _sessionId = null;
          _token = null;
          _finalizationOpen = false;
          _showEndConfirm = false;
          _studentTallies.clear();
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshSummary() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      final summary = await widget.api.getAttendanceSummary(sessionId);
      if (mounted) setState(() => _summary = summary);
    } catch (_) {}
  }

  Future<void> _loadActiveSession() async {
    try {
      final session = await widget.api.getActiveSession();
      if (!mounted) return;
      setState(() {
        _sessionId = session['id'] as String;
        _token = session['token'] as String;
        _finalizationOpen = (session['finalization_open'] as bool?) ?? false;
      });
    } catch (_) {}
  }

  Future<void> _openFinalization() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    setState(() => _loading = true);
    try {
      final session = await widget.api.openFinalization(sessionId);
      if (!mounted) return;
      setState(() {
        _finalizationOpen = (session['finalization_open'] as bool?) ?? true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finalization opened for students.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadAttendanceReport() async {
    final sessionId = _sessionId ?? _summary?['session_id'];
    if (sessionId == null) return;
    setState(() => _loading = true);
    try {
      final bytes = await widget.api.downloadAttendanceExcel(sessionId as String);
      // Save to a temp-ish known location
      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(
        '${dir.path}/attendance_${sessionId.toString().substring(0, 8)}.xlsx',
      );
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to ${file.path}')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _blePeripheral.stop();
    _scanSub?.cancel();
    _batchTimer?.cancel();
    FlutterForegroundTask.stopService();
    await widget.api.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedStudents = _studentTallies.values.toList()
      ..sort((a, b) => b.hits.compareTo(a.hits));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Subject input
            TextField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 12),

            // Start session
            FilledButton(
              onPressed: _loading || _sessionId != null ? null : _startSession,
              child: const Text('Start Session + BLE Broadcast'),
            ),
            const SizedBox(height: 8),

            // Open finalization
            FilledButton.tonal(
              onPressed: _loading || _sessionId == null || _finalizationOpen
                  ? null
                  : _openFinalization,
              child: const Text('Open Finalization for Students'),
            ),
            const SizedBox(height: 8),

            // Recover session
            OutlinedButton(
              onPressed: _loadActiveSession,
              child: const Text('Recover Active Session'),
            ),
            const SizedBox(height: 8),

            // Download attendance
            OutlinedButton.icon(
              onPressed: _loading ? null : _downloadAttendanceReport,
              icon: const Icon(Icons.download),
              label: const Text('Download Attendance (Excel)'),
            ),

            const SizedBox(height: 12),

            // Status row
            Text('Session: ${_sessionId != null ? "ACTIVE" : "None"}'),
            Text(
              'BLE: ${_isAdvertising ? "📡 Advertising" : "OFF"} '
              '| Scan: ${_isScanning ? "🔍 ON" : "OFF"}',
            ),
            Text('Finalization: ${_finalizationOpen ? "OPEN" : "CLOSED"}'),
            if (_summary != null)
              Text(
                'Attendance: ${_summary!['present_students']}/${_summary!['total_students']} present',
              ),

            const SizedBox(height: 12),
            Text(
              'Students detected (${sortedStudents.length}):',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),

            // Student hit tally list
            Expanded(
              child: ListView.builder(
                itemCount: sortedStudents.length,
                itemBuilder: (context, index) {
                  final s = sortedStudents[index];
                  return ListTile(
                    dense: true,
                    title: Text(s.studentId),
                    subtitle: Text(
                      'Hits: ${s.hits}/${s.total} '
                      '| RSSI: ${s.latestRssi} '
                      '| ${_timeAgo(s.latestAt)}',
                    ),
                    trailing: Icon(
                      s.inRange ? Icons.check_circle : Icons.cancel,
                      color: s.inRange ? Colors.green : Colors.red,
                    ),
                  );
                },
              ),
            ),

            // End Session — intentionally at the bottom with spacing
            const Divider(height: 32),
            const SizedBox(height: 8),
            if (_sessionId != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: _loading
                    ? null
                    : () => setState(
                          () => _showEndConfirm = !_showEndConfirm,
                        ),
                child: Text(
                  _showEndConfirm
                      ? 'Cancel End Confirmation'
                      : 'Show End Session Button',
                ),
              ),
            if (_showEndConfirm && _sessionId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _loading ? null : _endSession,
                  child: const Text('Confirm End Session'),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '-';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

class _StudentTally {
  _StudentTally({required this.studentId});
  final String studentId;
  int hits = 0;
  int total = 0;
  int? latestRssi;
  DateTime? latestAt;
  bool inRange = false;
}

// ===========================================================================
// STUDENT PAGE
// ===========================================================================

class StudentPage extends StatefulWidget {
  const StudentPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  final LocalAuthentication _localAuth = LocalAuthentication();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<BleStatus>? _bleStatusSub;

  String? _sessionId;
  String? _subject;
  String? _studentIdentifier;
  int? _latestRssi;
  bool _scanning = false;
  bool _advertising = false;
  bool _finalizationOpen = false;
  bool _blePermissionsGranted = true;
  String? _scanError;
  Timer? _scanRetryTimer;
  Timer? _sessionPollTimer;
  BleStatus _bleStatus = BleStatus.unknown;

  // Debounced proximity
  bool? _proximityOk;
  bool? _rawProximityOk;
  DateTime? _rawProximityChangeAt;

  // RSSI sliding window
  final List<int> _rssiWindow = [];

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _watchBleStatus();
    _bootstrap();
    _startSessionPolling();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bleStatusSub?.cancel();
    _scanRetryTimer?.cancel();
    _sessionPollTimer?.cancel();
    _blePeripheral.stop();
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  void _startSessionPolling() {
    _sessionPollTimer?.cancel();
    _sessionPollTimer =
        Timer.periodic(kStudentSessionPollInterval, (_) async {
      if (!mounted) return;
      await _loadActiveSession();
    });
  }

  void _watchBleStatus() {
    _bleStatusSub = _ble.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _bleStatus = status);

      if (status == BleStatus.ready &&
          _blePermissionsGranted &&
          !_scanning &&
          _sessionId != null) {
        _startScan();
        return;
      }

      if (status != BleStatus.ready && _scanning) {
        _scanSub?.cancel();
        setState(() {
          _scanning = false;
          _scanError = 'Bluetooth state is $status';
        });
      }
    });
  }

  Future<void> _bootstrap() async {
    // Load saved student identifier
    _studentIdentifier = await widget.api.readIdentifier();

    final permsOk = await _ensureBleScanPermissions();
    if (!permsOk) {
      if (mounted) {
        setState(() {
          _blePermissionsGranted = false;
          _scanError = 'Nearby devices permission denied.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions are required for scanning.'),
          ),
        );
      }
      return;
    }

    // Prompt to enable BT if needed
    await _ensureBluetoothEnabled();

    await _loadActiveSession();
    _startScan();
    _startStudentAdvertising();
    _startForegroundService('BLE Attendance — scanning');
  }

  Future<void> _loadActiveSession() async {
    // Try server first (may fail if offline — that's ok)
    try {
      final session = await widget.api.getActiveSession();
      if (!mounted) return;
      setState(() {
        _sessionId = session['id'] as String;
        _subject = session['subject'] as String?;
        _finalizationOpen = (session['finalization_open'] as bool?) ?? false;
        _blePermissionsGranted = true;
      });
    } catch (_) {
      // Offline — rely on BLE scan to detect teacher beacon
      // Don't clear session ID if we already have one from BLE
    }
  }

  Future<void> _startStudentAdvertising() async {
    if (_advertising || _studentIdentifier == null) return;
    try {
      final permsOk = await _ensureBleAdvertisePermissions();
      if (!permsOk) return;

      final idBytes = utf8.encode(_studentIdentifier!);
      final data = AdvertiseData(
        serviceUuid: kStudentServiceUuid,
        includeDeviceName: false,
        manufacturerId: kManufacturerId,
        manufacturerData: Uint8List.fromList(idBytes),
      );
      await _blePeripheral.start(advertiseData: data);
      if (mounted) setState(() => _advertising = true);
    } catch (_) {
      // BLE peripheral advertising may fail on some devices
    }
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    if (_bleStatus != BleStatus.ready) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanError = 'Bluetooth not ready: $_bleStatus';
        });
      }
      _scheduleScanRetry();
      return;
    }
    _scanRetryTimer?.cancel();
    await _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _scanError = null;
    });

    _scanSub = _ble
        .scanForDevices(
          withServices: const [],
          scanMode: ScanMode.lowPower,
          requireLocationServicesEnabled: false,
        )
        .listen(
          (device) {
            // Look for teacher beacon
            final payload = _decodeTeacherPayload(device);
            if (payload != null) {
              final rssi = device.rssi;
              _rssiWindow.add(rssi);
              if (_rssiWindow.length > kRssiWindowSize) {
                _rssiWindow.removeAt(0);
              }
              final avgRssi = _rssiWindow.isEmpty
                  ? rssi
                  : (_rssiWindow.reduce((a, b) => a + b) / _rssiWindow.length)
                        .round();
              final ok = avgRssi > kRssiThreshold;

              // Debounce proximity changes
              _updateDebouncedProximity(ok);

              setState(() {
                _latestRssi = avgRssi;
                _sessionId ??= 'ble-detected';
                if (payload['subject'] != null) {
                  _subject = payload['subject'] as String;
                }
              });
            }
          },
          onError: (error) {
            if (mounted) {
              setState(() {
                _scanning = false;
                _scanError = 'Scan error: $error';
              });
              _scheduleScanRetry();
            }
          },
          onDone: () {
            if (mounted) {
              setState(() {
                _scanning = false;
                _scanError = 'Scan ended. Retrying...';
              });
              _scheduleScanRetry();
            }
          },
        );
  }

  void _updateDebouncedProximity(bool newValue) {
    final now = DateTime.now();
    if (_rawProximityOk != newValue) {
      _rawProximityOk = newValue;
      _rawProximityChangeAt = now;
    } else if (_rawProximityChangeAt != null &&
        now.difference(_rawProximityChangeAt!) >= kProximityDebounceDuration) {
      // Value has been stable for debounce duration — apply it
      if (_proximityOk != newValue) {
        setState(() => _proximityOk = newValue);
      }
    }
    // Also set immediately on first reading
    _proximityOk ??= newValue;
  }

  Map<String, dynamic>? _decodeTeacherPayload(DiscoveredDevice device) {
    if (device.manufacturerData.isEmpty) return null;
    try {
      final bytes = device.manufacturerData;
      if (bytes.length < 4) return null;
      final payload = utf8.decode(bytes.sublist(2), allowMalformed: true);
      if (!payload.contains('|')) return null;
      final parts = payload.split('|');
      return {
        'token': parts[0],
        'subject': parts.length > 1 ? parts[1] : null,
      };
    } catch (_) {}
    return null;
  }

  void _scheduleScanRetry() {
    _scanRetryTimer?.cancel();
    _scanRetryTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || !_blePermissionsGranted || _scanning) return;
      await _startScan();
    });
  }

  Future<void> _finalizeWithBiometric() async {
    final sessionId = _sessionId;
    if (sessionId == null || sessionId == 'ble-detected') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need server connection to finalize. Check internet.'),
        ),
      );
      return;
    }
    if (!_finalizationOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teacher has not opened finalization yet.'),
        ),
      );
      return;
    }

    try {
      final canAuth = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuth) {
        throw Exception(
          'Biometric/passcode auth is not available on this device.',
        );
      }

      final success = await _localAuth.authenticate(
        localizedReason: 'Authenticate to finalize attendance',
        biometricOnly: false,
      );
      if (!success) return;

      final attendance = await widget.api.finalizeAttendance(sessionId);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Finalized. Present: ${attendance['is_present']} '
            '| Ratio: ${attendance['presence_ratio']}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  Future<void> _logout() async {
    _scanSub?.cancel();
    _bleStatusSub?.cancel();
    _blePeripheral.stop();
    FlutterForegroundTask.stopService();
    await widget.api.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _proximityOk == null
        ? Colors.grey
        : (_proximityOk! ? Colors.green : Colors.red);
    final statusText = _proximityOk == null
        ? 'Searching for teacher...'
        : (_proximityOk! ? 'In range ✅' : 'Out of range ❌');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lecture name — prominent
            if (_subject != null && _subject!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _subject!,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'No active lecture',
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 16),

            // Proximity status
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  statusText,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Status details
            Text('RSSI: ${_latestRssi ?? '-'}'),
            Text('Scanning: ${_scanning ? 'ON' : 'OFF'}'),
            Text('Advertising ID: ${_advertising ? (_studentIdentifier ?? '-') : 'OFF'}'),
            Text('Bluetooth: $_bleStatus'),
            if (_scanError != null) Text('Status: $_scanError'),
            if (!_blePermissionsGranted)
              const Text(
                'Scanning blocked: enable Nearby devices permission.',
                style: TextStyle(color: Colors.red),
              ),
            Text(
              'Finalization: ${_finalizationOpen ? 'OPEN' : 'WAITING FOR TEACHER'}',
            ),
            const Text(
              'Auto-scanning periodically. No action needed.',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 20),

            // Biometric finalize
            FilledButton.icon(
              onPressed: _finalizationOpen ? _finalizeWithBiometric : null,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Finalize Attendance (Biometric)'),
            ),
            const SizedBox(height: 12),

            // Battery settings button
            if (Platform.isAndroid) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  const intent = AndroidIntent(
                    action:
                        'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
                  );
                  await intent.launch();
                },
                icon: const Icon(Icons.battery_saver),
                label: const Text('Disable Battery Optimization'),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _openAutoStartSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Fix Background Restrictions (Xiaomi/Samsung)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openAutoStartSettings() async {
    if (!Platform.isAndroid) return;
    // Try Xiaomi/MIUI autostart intent
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.miui.securitycenter',
        componentName:
            'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
      );
      await intent.launch();
      return;
    } catch (_) {}

    // Fallback: open app info
    try {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:com.example.ble_attendance_mobile',
      );
      await intent.launch();
    } catch (_) {}
  }
}

// ===========================================================================
// API CLIENT
// ===========================================================================

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

  // Token / role / identifier persistence
  Future<void> saveToken(String token) =>
      _storage.write(key: 'token', value: token);
  Future<String?> readToken() => _storage.read(key: 'token');
  Future<void> saveRole(String role) =>
      _storage.write(key: 'role', value: role);
  Future<String?> readRole() => _storage.read(key: 'role');
  Future<void> saveIdentifier(String id) =>
      _storage.write(key: 'identifier', value: id);
  Future<String?> readIdentifier() => _storage.read(key: 'identifier');

  Future<void> clearSession() async {
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'role');
    await _storage.delete(key: 'identifier');
  }

  Future<void> enablePersistentConnection() async {
    _dio.options.connectTimeout = const Duration(seconds: 12);
    _dio.options.receiveTimeout = const Duration(seconds: 12);
  }

  Future<String?> _token() => _storage.read(key: 'token');

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

  Future<Map<String, dynamic>> _authedPost(
    String path,
    Map<String, dynamic> data,
  ) async {
    final token = await _token();
    final response = await _dio.post(
      path,
      data: data,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  // Auth
  Future<void> register({
    required String fullName,
    required String identifier,
    required String password,
    required AppRole role,
  }) async {
    await _dio.post(
      '/auth/register',
      data: {
        'full_name': fullName,
        'role': role.name,
        'identifier': identifier,
        'password': password,
      },
    );
  }

  Future<String> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    final json = Map<String, dynamic>.from(response.data as Map);
    return json['access_token'] as String;
  }

  // Sessions
  Future<Map<String, dynamic>> startSession(String subject) =>
      _authedPost('/sessions', {'subject': subject});

  Future<Map<String, dynamic>> endSession(String sessionId) =>
      _authedPost('/sessions/$sessionId/end', {});

  Future<Map<String, dynamic>> getActiveSession() =>
      _authedGet('/sessions/active');

  Future<Map<String, dynamic>> openFinalization(String sessionId) =>
      _authedPost('/teacher/sessions/$sessionId/open-finalization', {});

  // Detections — teacher batch-posts
  Future<Map<String, dynamic>> submitDetectionBatch(
    List<Map<String, dynamic>> detections,
  ) =>
      _authedPost('/detections/batch', {'detections': detections});

  // Attendance
  Future<Map<String, dynamic>> finalizeAttendance(String sessionId) =>
      _authedPost('/attendance/finalize', {
        'session_id': sessionId,
        'biometric_verified': true,
      });

  Future<Map<String, dynamic>> getAttendanceSummary(String sessionId) =>
      _authedGet('/teacher/sessions/$sessionId/attendance-summary');

  // Excel download
  Future<List<int>> downloadAttendanceExcel(String sessionId) async {
    final token = await _token();
    final response = await _dio.get(
      '/teacher/sessions/$sessionId/attendance-export',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.bytes,
      ),
    );
    return response.data as List<int>;
  }
}

// ===========================================================================
// PERMISSIONS & UTILITIES
// ===========================================================================

Future<bool> _ensureBlePermissions() async {
  final bleStatuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
  ].request();

  for (final status in bleStatuses.values) {
    if (!status.isGranted && !status.isLimited) return false;
  }

  await Permission.locationWhenInUse.request();
  return true;
}

Future<bool> _ensureBleAdvertisePermissions() async {
  final bleStatuses = await [
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
  ].request();

  for (final status in bleStatuses.values) {
    if (!status.isGranted && !status.isLimited) return false;
  }
  return true;
}

Future<bool> _ensureBleScanPermissions() async {
  final bleStatuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  for (final status in bleStatuses.values) {
    if (!status.isGranted && !status.isLimited) return false;
  }

  await Permission.locationWhenInUse.request();
  return true;
}

Future<void> _ensureBluetoothEnabled() async {
  if (!Platform.isAndroid) return;
  try {
    const intent = AndroidIntent(
      action: 'android.bluetooth.adapter.action.REQUEST_ENABLE',
    );
    await intent.launch();
  } catch (_) {
    // Silently fail — user will see BLE status in the UI
  }
}

void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'ble_attendance_fg',
      channelName: 'BLE Attendance',
      channelDescription: 'Keeps BLE scanning/advertising alive',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

Future<void> _startForegroundService(String text) async {
  if (!Platform.isAndroid) return;
  await FlutterForegroundTask.startService(
    notificationTitle: 'BLE Attendance',
    notificationText: text,
  );
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
  if (raw.isEmpty) throw Exception('Server URL is required.');
  final withScheme = raw.startsWith('http://') || raw.startsWith('https://')
      ? raw
      : 'http://$raw';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) {
    throw Exception('Enter a valid server URL.');
  }
  return withScheme.endsWith('/')
      ? withScheme.substring(0, withScheme.length - 1)
      : withScheme;
}
