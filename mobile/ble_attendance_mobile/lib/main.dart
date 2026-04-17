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
  defaultValue: 'https://ble-attendance.onrender.com',
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE8E8E8)),
          ),
          color: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
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

  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
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
    } catch (_) {
      // FlutterSecureStorage can fail on some devices (keystore issues).
      // Fall through to show the login form so the user is never stuck.
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



  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo + title
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.school_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 16),
                Text('BLE Attendance',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('Sign in to continue',
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withAlpha(140))),
                const SizedBox(height: 32),

                // Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 20, offset: const Offset(0, 4))],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Role selector
                      SegmentedButton<AppRole>(
                        segments: const [
                          ButtonSegment(value: AppRole.student, label: Text('Student'), icon: Icon(Icons.person_outline)),
                          ButtonSegment(value: AppRole.teacher, label: Text('Teacher'), icon: Icon(Icons.cast_for_education_outlined)),
                        ],
                        selected: {_role},
                        onSelectionChanged: (set) => setState(() => _role = set.first),
                      ),
                      const SizedBox(height: 20),
                      if (_isRegister) ...[
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _identifierCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: _role == AppRole.teacher ? 'Teacher ID (e.g. T001)' : 'Student ID (e.g. 25CE001)',
                          prefixIcon: const Icon(Icons.fingerprint),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordCtrl,
                        decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                        obscureText: true,
                      ),
                      const SizedBox(height: 8),
                      // Server URL (collapsed by default)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('Server URL', style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(160))),
                        children: [
                          TextField(
                            controller: _serverUrlCtrl,
                            decoration: const InputDecoration(labelText: 'API base URL', prefixIcon: Icon(Icons.dns_outlined)),
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _loading || !_ready ? null : _submit,
                        child: _loading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_isRegister ? 'Register & Login' : 'Sign In'),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _loading ? null : () => setState(() => _isRegister = !_isRegister),
                        child: Text(_isRegister ? 'Already have an account? Sign in' : 'New user? Register'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
  Timer? _scanRetryTimer;
  StreamSubscription<DiscoveredDevice>? _scanSub;

  // Today's schedule slots from server
  List<Map<String, dynamic>> _todaySlots = [];
  Map<String, dynamic>? _selectedSlot;

  // Local student detection tally
  final Map<String, _StudentTally> _studentTallies = {};

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _loadTodaySchedule();
    _loadActiveSession();
  }

  @override
  void dispose() {
    _blePeripheral.stop();
    _scanSub?.cancel();
    _scanRetryTimer?.cancel();
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  Future<void> _loadTodaySchedule() async {
    try {
      final slots = await widget.api.getTodaySlots();
      if (mounted) setState(() => _todaySlots = slots);
    } catch (_) {}
  }

  Future<void> _startSession() async {
    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a class first')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final permsOk = await _ensureBlePermissions();
      if (!permsOk) throw Exception('Bluetooth permissions are required.');
      await _ensureBluetoothEnabled();

      final subjectName = _selectedSlot!['subject_name'] as String;
      final assignmentId = _selectedSlot!['assignment_id'] as int;

      final session = await widget.api.startSession(subjectName, assignmentId: assignmentId);
      _sessionId = session['id'] as String;
      _token = session['token'] as String;
      _finalizationOpen = (session['finalization_open'] as bool?) ?? false;

      final data = AdvertiseData(
        serviceUuid: kTeacherServiceUuid,
        includeDeviceName: false,
        manufacturerId: kManufacturerId,
        manufacturerData: Uint8List.fromList(
          _encodeTeacherPayload(_token!, subjectName),
        ),
      );
      await _blePeripheral.start(advertiseData: data);
      _isAdvertising = true;
      _startStudentScan();
      _startForegroundService('Teaching: $subjectName');
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startStudentScan() {
    _scanSub?.cancel();
    _isScanning = true;
    _scanSub = _ble.scanForDevices(
      withServices: const [],
      scanMode: ScanMode.lowLatency,
      requireLocationServicesEnabled: false,
    ).listen(
      (device) {
        final studentId = _extractStudentId(device);
        if (studentId == null || _sessionId == null) return;
        final rssi = device.rssi;
        final ok = rssi > kRssiThreshold;
        final tally = _studentTallies.putIfAbsent(
          studentId, () => _StudentTally(studentId: studentId),
        );
        tally.total++;
        if (ok) tally.hits++;
        tally.latestRssi = rssi;
        tally.latestAt = DateTime.now();
        tally.inRange = ok;
        if (mounted) setState(() {});
      },
      onError: (_) { if (mounted) setState(() => _isScanning = false); _scheduleStudentScanRetry(); },
      onDone: () { if (mounted) setState(() => _isScanning = false); _scheduleStudentScanRetry(); },
    );
  }

  void _scheduleStudentScanRetry() {
    _scanRetryTimer?.cancel();
    _scanRetryTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isScanning && _sessionId != null) _startStudentScan();
    });
  }

  String? _extractStudentId(DiscoveredDevice device) {
    if (device.manufacturerData.isEmpty) return null;
    try {
      final bytes = device.manufacturerData;
      if (bytes.length < 4) return null;
      final rawId = utf8.decode(bytes.sublist(2), allowMalformed: true).trim();
      if (rawId.length >= 5 && rawId.length <= 12 && RegExp(r'^[A-Z0-9]+$').hasMatch(rawId)) {
        return rawId;
      }
    } catch (_) {}
    return null;
  }

  List<int> _encodeTeacherPayload(String token, String subject) {
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active session.')));
        return;
      }
    }
    setState(() => _loading = true);
    try {
      // Build final P/A list from local tallies and batch-submit
      final decisions = _studentTallies.values.map((t) => {
        'student_id': t.studentId,
        'is_present': t.hits > 0 && (t.hits / t.total) >= 0.6,
      }).toList();

      if (decisions.isNotEmpty) {
        await widget.api.batchSubmitAttendance(sessionId!, decisions);
      }

      await widget.api.endSession(sessionId!);
      await _blePeripheral.stop();
      _scanSub?.cancel();
      _isAdvertising = false;
      _isScanning = false;
      FlutterForegroundTask.stopService();

      // Refresh summary
      try {
        final summary = await widget.api.getAttendanceSummary(sessionId!);
        if (mounted) setState(() => _summary = summary);
      } catch (_) {}

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      setState(() => _finalizationOpen = (session['finalization_open'] as bool?) ?? true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Finalization opened for students.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _blePeripheral.stop();
    _scanSub?.cancel();
    FlutterForegroundTask.stopService();
    await widget.api.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sortedStudents = _studentTallies.values.toList()
      ..sort((a, b) => b.hits.compareTo(a.hits));

    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F5),
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Teacher Dashboard', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout_rounded))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sessionId == null) ...[
              // ── Class picker ──
              Text('Select a class to start',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withAlpha(160), letterSpacing: 0.5)),
              const SizedBox(height: 10),
              if (_todaySlots.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8E8E8))),
                  child: Column(children: [
                    Icon(Icons.event_busy_rounded, size: 36, color: cs.onSurface.withAlpha(80)),
                    const SizedBox(height: 8),
                    Text('No classes scheduled today', style: TextStyle(color: cs.onSurface.withAlpha(140))),
                  ]),
                )
              else
                ...(_todaySlots.map((slot) {
                  final isSelected = _selectedSlot?['slot_id'] == slot['slot_id'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => setState(() => _selectedSlot = slot),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? cs.primaryContainer : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? cs.primary : const Color(0xFFE8E8E8), width: isSelected ? 2 : 1),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(color: isSelected ? cs.primary : cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.menu_book_rounded, color: isSelected ? Colors.white : cs.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${slot['subject_name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(
                              '${slot['division_label']}${slot['batch_label'] != null ? ' · ${slot['batch_label']}' : ''}'
                              '  ${slot['time_start']}–${slot['time_end']}'
                              '${slot['room'] != null ? '  · ${slot['room']}' : ''}',
                              style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(160)),
                            ),
                          ])),
                          if (isSelected) Icon(Icons.check_circle_rounded, color: cs.primary),
                        ]),
                      ),
                    ),
                  );
                })),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading || _selectedSlot == null ? null : _startSession,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Session + BLE Broadcast'),
              ),
            ] else ...[
              // ── Active session ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.primary.withAlpha(200)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.radio_button_checked, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    const Text('Session Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    if (_summary != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(50), borderRadius: BorderRadius.circular(20)),
                        child: Text('${_summary!['present_students']}/${_summary!['total_students']} present',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    _StatusChip(label: _isAdvertising ? 'BLE ON' : 'BLE OFF', active: _isAdvertising),
                    _StatusChip(label: _isScanning ? 'Scan ON' : 'Scan OFF', active: _isScanning),
                    _StatusChip(label: _finalizationOpen ? 'Finalization OPEN' : 'Finalization CLOSED', active: _finalizationOpen),
                  ]),
                ]),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: _loading || _finalizationOpen ? null : _openFinalization,
                child: const Text('Open Finalization for Students'),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Text('Detected students', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)),
                  child: Text('${sortedStudents.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                ),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: sortedStudents.isEmpty
                    ? Center(child: Text('Waiting for students…', style: TextStyle(color: cs.onSurface.withAlpha(120))))
                    : ListView.separated(
                        itemCount: sortedStudents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final s = sortedStudents[index];
                          final ratio = s.total > 0 ? s.hits / s.total : 0.0;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: s.inRange ? const Color(0xFFBBF7D0) : const Color(0xFFE8E8E8)),
                            ),
                            child: Row(children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: s.inRange ? const Color(0xFFDCFCE7) : const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(s.inRange ? Icons.check_rounded : Icons.close_rounded,
                                    color: s.inRange ? Colors.green : Colors.grey, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s.studentId, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                Text('${s.hits}/${s.total} hits · RSSI ${s.latestRssi ?? '-'} · ${_timeAgo(s.latestAt)}',
                                    style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(140))),
                              ])),
                              SizedBox(
                                width: 36,
                                child: CircularProgressIndicator(
                                  value: ratio,
                                  strokeWidth: 3,
                                  backgroundColor: const Color(0xFFE8E8E8),
                                  color: ratio >= 0.6 ? Colors.green : Colors.orange,
                                ),
                              ),
                            ]),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                onPressed: _loading ? null : () => setState(() => _showEndConfirm = !_showEndConfirm),
                icon: Icon(_showEndConfirm ? Icons.close_rounded : Icons.stop_circle_outlined),
                label: Text(_showEndConfirm ? 'Cancel' : 'End Session'),
              ),
              if (_showEndConfirm)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _loading ? null : _endSession,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Confirm End + Submit Attendance'),
                  ),
                ),
            ],
            const SizedBox(height: 8),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? Colors.white.withAlpha(50) : Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(80)),
      ),
      child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white.withAlpha(160), fontSize: 11, fontWeight: FontWeight.w600)),
    );
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
                // Only use BLE-decoded subject if the server hasn't
                // provided one yet (server data is more reliable).
                if (_subject == null && payload['subject'] != null) {
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
      // Strict decode — reject garbled BLE noise instead of replacing chars.
      final payload = utf8.decode(bytes.sublist(2));
      if (!payload.contains('|')) return null;
      final parts = payload.split('|');
      final token = parts[0];
      final subject = parts.length > 1 ? parts[1].trim() : null;
      // Validate: token and subject must be printable (no control chars).
      if (token.isEmpty || RegExp(r'[\x00-\x1F]').hasMatch(token)) return null;
      if (subject != null && (subject.isEmpty || RegExp(r'[\x00-\x1F]').hasMatch(subject))) {
        return {'token': token, 'subject': null};
      }
      return {
        'token': token,
        'subject': subject,
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
    final cs = Theme.of(context).colorScheme;
    final proximityColor = _proximityOk == null
        ? Colors.grey
        : (_proximityOk! ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
    final proximityBg = _proximityOk == null
        ? const Color(0xFFF5F5F5)
        : (_proximityOk! ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2));
    final proximityText = _proximityOk == null
        ? 'Searching for teacher…'
        : (_proximityOk! ? 'In Range' : 'Out of Range');
    final proximityIcon = _proximityOk == null
        ? Icons.radar_rounded
        : (_proximityOk! ? Icons.wifi_rounded : Icons.wifi_off_rounded);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F5),
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Student Dashboard', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout_rounded))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Subject card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _subject != null ? cs.primaryContainer : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _subject != null ? cs.primary.withAlpha(60) : const Color(0xFFE8E8E8)),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: _subject != null ? cs.primary : Colors.grey.shade300, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.menu_book_rounded, color: _subject != null ? Colors.white : Colors.grey, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_subject != null ? 'Current Lecture' : 'No Active Lecture',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withAlpha(140), letterSpacing: 0.4)),
                  if (_subject != null) ...[
                    const SizedBox(height: 2),
                    Text(_subject!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ])),
              ]),
            ),

            const SizedBox(height: 16),

            // Proximity indicator — big and prominent
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(color: proximityBg, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: proximityColor.withAlpha(80))),
              child: Column(children: [
                Icon(proximityIcon, size: 52, color: proximityColor),
                const SizedBox(height: 10),
                Text(proximityText, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: proximityColor)),
                if (_latestRssi != null) ...[
                  const SizedBox(height: 4),
                  Text('Signal: ${_latestRssi} dBm', style: TextStyle(fontSize: 13, color: proximityColor.withAlpha(180))),
                ],
              ]),
            ),

            const SizedBox(height: 16),

            // Status info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8E8E8))),
              child: Column(children: [
                _StatusRow(icon: Icons.bluetooth_searching_rounded, label: 'BLE Scan', value: _scanning ? 'Active' : 'Off', active: _scanning),
                const Divider(height: 16),
                _StatusRow(icon: Icons.broadcast_on_personal_rounded, label: 'Advertising', value: _advertising ? (_studentIdentifier ?? 'On') : 'Off', active: _advertising),
                const Divider(height: 16),
                _StatusRow(icon: Icons.how_to_reg_rounded, label: 'Finalization',
                    value: _finalizationOpen ? 'Open — tap button below' : 'Waiting for teacher',
                    active: _finalizationOpen),
                if (_scanError != null) ...[
                  const Divider(height: 16),
                  _StatusRow(icon: Icons.warning_amber_rounded, label: 'Status', value: _scanError!, active: false, isWarning: true),
                ],
                if (!_blePermissionsGranted) ...[
                  const Divider(height: 16),
                  _StatusRow(icon: Icons.block_rounded, label: 'Permission', value: 'Nearby devices denied', active: false, isWarning: true),
                ],
              ]),
            ),

            const SizedBox(height: 16),

            // Finalize button
            FilledButton.icon(
              onPressed: _finalizationOpen ? _finalizeWithBiometric : null,
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Finalize Attendance (Biometric)'),
            ),

            if (Platform.isAndroid) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  const intent = AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS');
                  await intent.launch();
                },
                icon: const Icon(Icons.battery_saver_outlined),
                label: const Text('Disable Battery Optimization'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _openAutoStartSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Fix Background Restrictions'),
              ),
            ],
            const SizedBox(height: 8),
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

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.label, required this.value, required this.active, this.isWarning = false});
  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? Colors.orange : (active ? const Color(0xFF16A34A) : Colors.grey);
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    ]);
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
  Future<Map<String, dynamic>> startSession(String subject, {int? assignmentId}) =>
      _authedPost('/sessions', {
        'subject': subject,
        if (assignmentId != null) 'assignment_id': assignmentId,
      });

  Future<Map<String, dynamic>> endSession(String sessionId) =>
      _authedPost('/sessions/$sessionId/end', {});

  Future<Map<String, dynamic>> getActiveSession() =>
      _authedGet('/sessions/active');

  Future<Map<String, dynamic>> openFinalization(String sessionId) =>
      _authedPost('/teacher/sessions/$sessionId/open-finalization', {});

  // Today's schedule for mobile
  Future<List<Map<String, dynamic>>> getTodaySlots() async {
    final token = await _token();
    final response = await _dio.get(
      '/teacher/me/schedule/today/slots',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Batch submit final P/A at session end (replaces per-detection pings)
  Future<Map<String, dynamic>> batchSubmitAttendance(
    String sessionId,
    List<Map<String, dynamic>> decisions,
  ) async {
    final token = await _token();
    final response = await _dio.post(
      '/teacher/sessions/$sessionId/attendance/batch-submit',
      data: decisions,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

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
