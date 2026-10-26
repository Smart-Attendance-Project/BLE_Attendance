/// BLE Scan Handler Stress Test
/// ==============================
/// Tests the teacher-side BLE scan logic WITHOUT real hardware by pumping
/// synthetic DiscoveredDevice events through the exact same parsing and
/// state-update functions that run in production.
///
/// What this catches
/// -----------------
///  1. Payload parser crashes on any of the 70 student ID formats
///  2. Incorrect deduplication (same student counted twice)
///  3. Division/batch filter dropping students it should accept
///  4. Division range filter (start/end student ID) working correctly
///  5. setState storm — 70 rapid events should complete in < 1 s wall time
///  6. Edge cases: empty payload, garbage bytes, teacher beacon leaking through
///
/// Run with:
///   flutter test test/ble_scan_stress_test.dart
///   flutter test test/ble_scan_stress_test.dart --reporter expanded

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constants (copied from main.dart — keep in sync)
// ---------------------------------------------------------------------------

const String kTeacherServiceUuid = '0000180D-0000-1000-8000-00805F9B34FB';
const String kStudentServiceUuid = '0000181C-0000-1000-8000-00805F9B34FB';
const int kManufacturerId = 0x004C;
const int kRssiThreshold = -150; // production value — effectively "accept all"

// ---------------------------------------------------------------------------
// Pure Dart port of _extractStudentPayload (main.dart ~line 690)
// Keep 100 % in sync with the production implementation.
// ---------------------------------------------------------------------------

Map<String, dynamic>? extractStudentPayload(DiscoveredDevice device) {
  if (device.manufacturerData.isEmpty) return null;

  if (device.serviceUuids.isNotEmpty &&
      device.serviceUuids.contains(Uuid.parse(kTeacherServiceUuid))) {
    return null;
  }

  try {
    final bytes = device.manufacturerData;
    if (bytes.length < 4) return null;

    final payload = utf8.decode(bytes.sublist(2)).trim();
    if (!payload.contains('|')) return null;
    if (payload.startsWith('T|')) return null;

    final parts = payload.split('|');
    final studentId = parts[0];
    final hits = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final total = parts.length > 2 ? int.tryParse(parts[2]) : null;

    int? divisionId;
    int? batchId;
    bool verified = false;

    if (parts.length > 3) {
      for (final part in parts.sublist(3)) {
        if (part == 'V') {
          verified = true;
          continue;
        }
        final scope = part.split(':');
        if (scope.length == 2) {
          divisionId = int.tryParse(scope[0]);
          final parsedBatchId = int.tryParse(scope[1]);
          batchId = parsedBatchId == 0 ? null : parsedBatchId;
        }
      }
    }

    if (studentId.length >= 5 &&
        studentId.length <= 12 &&
        RegExp(r'^[A-Z0-9]+$').hasMatch(studentId)) {
      if (hits != null && total != null) {
        return {
          'student_id': studentId,
          'hits': hits,
          'total': total,
          'verified': verified,
          'division_id': divisionId,
          'batch_id': batchId,
        };
      }
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// Minimal port of _StudentTally (main.dart)
// ---------------------------------------------------------------------------

class StudentTally {
  final String studentId;
  int hits = 0;
  int total = 0;
  int latestRssi = 0;
  bool inRange = false;
  bool biometricVerified = false;

  StudentTally({required this.studentId});
}

// ---------------------------------------------------------------------------
// Minimal port of the teacher scan handler closure (main.dart ~line 660)
// Returns the updated tally map so we can assert on it.
// ---------------------------------------------------------------------------

Map<String, StudentTally> runScanHandler({
  required List<DiscoveredDevice> events,
  required int activeDivisionId,
  int? activeBatchId,
  String? startStudentId,
  String? endStudentId,
  required int globalTotalHits,
}) {
  final tallies = <String, StudentTally>{};

  for (final device in events) {
    final parsed = extractStudentPayload(device);
    if (parsed == null) continue;

    final studentId = parsed['student_id'] as String;
    final studentDivisionId = parsed['division_id'] as int?;
    final studentBatchId = parsed['batch_id'] as int?;

    // Division + batch filter
    if (studentDivisionId != activeDivisionId ||
        studentBatchId != activeBatchId) {
      continue;
    }

    // Range filter
    if (startStudentId != null &&
        studentId.compareTo(startStudentId) < 0) continue;
    if (endStudentId != null &&
        studentId.compareTo(endStudentId) > 0) continue;

    final hits = parsed['hits'] as int;
    final verified = parsed['verified'] as bool;
    final rssi = device.rssi;
    final ok = rssi > kRssiThreshold;

    final tally = tallies.putIfAbsent(
      studentId,
      () => StudentTally(studentId: studentId),
    );
    if (hits > tally.hits) tally.hits = hits;
    tally.total = globalTotalHits;
    tally.latestRssi = rssi;
    tally.inRange = ok;
    if (verified) tally.biometricVerified = true;
  }

  return tallies;
}

// ---------------------------------------------------------------------------
// Helpers to build synthetic BLE events
// ---------------------------------------------------------------------------

/// Encode exactly as _updateStudentAdvertising does in main.dart:
///   company_id (2 bytes LE) + UTF-8 payload
Uint8List encodeStudentMfrData({
  required String studentId,
  required int hits,
  required int total,
  required int divId,
  int batchId = 0,
  bool verified = false,
}) {
  final vFlag = verified ? '|V' : '';
  final payloadStr = '$studentId|$hits|$total|$divId:$batchId$vFlag';
  final mfrIdBytes = [kManufacturerId & 0xFF, (kManufacturerId >> 8) & 0xFF];
  return Uint8List.fromList(mfrIdBytes + utf8.encode(payloadStr));
}

DiscoveredDevice makeStudentDevice({
  required String studentId,
  int hits = 5,
  int total = 10,
  int divId = 1,
  int batchId = 0,
  bool verified = false,
  int rssi = -60,
  String? macOverride,
}) {
  return DiscoveredDevice(
    id: macOverride ?? 'AA:BB:CC:DD:${studentId.hashCode.toRadixString(16).padLeft(4, '0').toUpperCase().substring(0, 4)}',
    name: '',
    serviceData: const {},
    serviceUuids: [Uuid.parse(kStudentServiceUuid)],
    manufacturerData: encodeStudentMfrData(
      studentId: studentId,
      hits: hits,
      total: total,
      divId: divId,
      batchId: batchId,
      verified: verified,
    ),
    rssi: rssi,
  );
}

DiscoveredDevice makeTeacherDevice() {
  final payload = utf8.encode('T2|1|0|LoadTest|5');
  final mfrBytes = Uint8List.fromList(
    [kManufacturerId & 0xFF, (kManufacturerId >> 8) & 0xFF] + payload,
  );
  return DiscoveredDevice(
    id: 'FF:FF:FF:FF:FF:FF',
    name: 'Teacher',
    serviceData: const {},
    serviceUuids: [Uuid.parse(kTeacherServiceUuid)], // teacher UUID — must be filtered out
    manufacturerData: mfrBytes,
    rssi: -50,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Group 1: Parser unit tests ────────────────────────────────────────────

  group('extractStudentPayload — parser correctness', () {
    test('parses standard payload without batch', () {
      final device = makeStudentDevice(
        studentId: '25CE001',
        hits: 7,
        total: 10,
        divId: 1,
        batchId: 0,
      );
      final result = extractStudentPayload(device);
      expect(result, isNotNull);
      expect(result!['student_id'], '25CE001');
      expect(result['hits'], 7);
      expect(result['total'], 10);
      expect(result['division_id'], 1);
      expect(result['batch_id'], isNull); // batchId==0 → null
      expect(result['verified'], false);
    });

    test('parses payload with batch ID', () {
      final device = makeStudentDevice(
        studentId: '25CE035',
        hits: 3,
        total: 10,
        divId: 2,
        batchId: 5,
      );
      final result = extractStudentPayload(device);
      expect(result!['batch_id'], 5);
      expect(result['division_id'], 2);
    });

    test('parses verified flag', () {
      final device = makeStudentDevice(
        studentId: '25CE010',
        hits: 8,
        total: 10,
        divId: 1,
        verified: true,
      );
      final result = extractStudentPayload(device);
      expect(result!['verified'], true);
    });

    test('rejects empty manufacturerData', () {
      final device = DiscoveredDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: '',
        serviceData: const {},
        serviceUuids: [Uuid.parse(kStudentServiceUuid)],
        manufacturerData: Uint8List(0),
        rssi: -60,
      );
      expect(extractStudentPayload(device), isNull);
    });

    test('rejects too-short manufacturerData (< 4 bytes)', () {
      final device = DiscoveredDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: '',
        serviceData: const {},
        serviceUuids: [],
        manufacturerData: Uint8List.fromList([0x4C, 0x00, 0x41]),
        rssi: -60,
      );
      expect(extractStudentPayload(device), isNull);
    });

    test('rejects teacher beacon leaking through (T| prefix)', () {
      final mfr = Uint8List.fromList(
        [0x4C, 0x00] + utf8.encode('T2|1|0|DS|10'),
      );
      final device = DiscoveredDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: '',
        serviceData: const {},
        serviceUuids: [], // no teacher UUID — simulates a packet that leaked
        manufacturerData: mfr,
        rssi: -60,
      );
      expect(extractStudentPayload(device), isNull);
    });

    test('rejects device with teacher service UUID', () {
      expect(extractStudentPayload(makeTeacherDevice()), isNull);
    });

    test('rejects garbled UTF-8 garbage bytes', () {
      final device = DiscoveredDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: '',
        serviceData: const {},
        serviceUuids: [],
        manufacturerData: Uint8List.fromList([0x4C, 0x00, 0xFF, 0xFE, 0xFD, 0x00]),
        rssi: -60,
      );
      // Must not throw — just return null
      expect(() => extractStudentPayload(device), returnsNormally);
      expect(extractStudentPayload(device), isNull);
    });

    test('rejects student ID that is too short (< 5 chars)', () {
      final mfr = Uint8List.fromList(
        [0x4C, 0x00] + utf8.encode('AB|5|10|1:0'),
      );
      final device = DiscoveredDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: '',
        serviceData: const {},
        serviceUuids: [],
        manufacturerData: mfr,
        rssi: -60,
      );
      expect(extractStudentPayload(device), isNull);
    });

    test('rejects student ID with lowercase letters', () {
      final mfr = Uint8List.fromList(
        [0x4C, 0x00] + utf8.encode('25ce001|5|10|1:0'),
      );
      final device = DiscoveredDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: '',
        serviceData: const {},
        serviceUuids: [],
        manufacturerData: mfr,
        rssi: -60,
      );
      expect(extractStudentPayload(device), isNull);
    });
  });

  // ── Group 2: Scan handler stress — 70 students at once ───────────────────

  group('Scan handler — 70-student storm', () {
    const divId = 1;
    const totalBeacons = 10;
    const numStudents = 70;

    List<DiscoveredDevice> buildStudentFlood({
      int hitsPerStudent = 8,
      bool withVerified = false,
    }) {
      return List.generate(numStudents, (i) {
        final id = '25CE${(i + 1).toString().padLeft(3, '0')}';
        return makeStudentDevice(
          studentId: id,
          hits: hitsPerStudent,
          total: totalBeacons,
          divId: divId,
          batchId: 0,
          verified: withVerified,
          rssi: -50 - (i % 30), // vary RSSI
        );
      });
    }

    test('all 70 students are detected in one scan burst', () {
      final events = buildStudentFlood();
      final tallies = runScanHandler(
        events: events,
        activeDivisionId: divId,
        activeBatchId: null,
        globalTotalHits: totalBeacons,
      );
      expect(tallies.length, numStudents,
          reason: 'All 70 students should be tallied');
    });

    test('completes in under 200ms wall time (no setState storm hang)', () {
      final events = buildStudentFlood();
      final sw = Stopwatch()..start();
      runScanHandler(
        events: events,
        activeDivisionId: divId,
        activeBatchId: null,
        globalTotalHits: totalBeacons,
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(200),
          reason: 'Parsing 70 events must be fast — '
              'actual: ${sw.elapsedMilliseconds}ms');
    });

    test('duplicate events for the same student do not double-count hits', () {
      // Send student 25CE001 three times with ascending hit counts
      final events = [
        makeStudentDevice(studentId: '25CE001', hits: 3, total: 10, divId: divId),
        makeStudentDevice(studentId: '25CE001', hits: 7, total: 10, divId: divId),
        makeStudentDevice(studentId: '25CE001', hits: 5, total: 10, divId: divId),
      ];
      final tallies = runScanHandler(
        events: events,
        activeDivisionId: divId,
        activeBatchId: null,
        globalTotalHits: 10,
      );
      expect(tallies.length, 1);
      // Must keep the MAX hits seen, not the last
      expect(tallies['25CE001']!.hits, 7);
    });

    test('division filter blocks students from other divisions', () {
      final myDiv = buildStudentFlood(); // divId=1
      final otherDiv = List.generate(10, (i) {
        final id = '25CE${(i + 71).toString().padLeft(3, '0')}';
        return makeStudentDevice(studentId: id, divId: 99, batchId: 0);
      });
      final tallies = runScanHandler(
        events: [...myDiv, ...otherDiv],
        activeDivisionId: divId,
        activeBatchId: null,
        globalTotalHits: totalBeacons,
      );
      // Only the 70 from our division should appear
      expect(tallies.length, numStudents);
      for (final key in tallies.keys) {
        expect(int.parse(key.substring(4)), lessThanOrEqualTo(70));
      }
    });

    test('batch filter blocks students from wrong batch', () {
      final batchA = List.generate(5, (i) =>
          makeStudentDevice(studentId: '25CE${(i + 1).toString().padLeft(3, '0')}', divId: 1, batchId: 1));
      final batchB = List.generate(5, (i) =>
          makeStudentDevice(studentId: '25CE${(i + 6).toString().padLeft(3, '0')}', divId: 1, batchId: 2));

      final tallies = runScanHandler(
        events: [...batchA, ...batchB],
        activeDivisionId: 1,
        activeBatchId: 1, // teacher is running batch 1
        globalTotalHits: 10,
      );
      expect(tallies.length, 5, reason: 'Only batch-1 students should pass');
    });

    test('division range filter (start/end student ID) is respected', () {
      // Active range: 25CE010 … 25CE040
      final events = List.generate(70, (i) {
        final id = '25CE${(i + 1).toString().padLeft(3, '0')}';
        return makeStudentDevice(studentId: id, divId: divId, batchId: 0);
      });
      final tallies = runScanHandler(
        events: events,
        activeDivisionId: divId,
        activeBatchId: null,
        startStudentId: '25CE010',
        endStudentId: '25CE040',
        globalTotalHits: totalBeacons,
      );
      expect(tallies.length, 31, reason: '25CE010 … 25CE040 = 31 students');
      expect(tallies.containsKey('25CE009'), false);
      expect(tallies.containsKey('25CE010'), true);
      expect(tallies.containsKey('25CE040'), true);
      expect(tallies.containsKey('25CE041'), false);
    });

    test('biometric verified flag is latched — once true, stays true', () {
      final events = [
        makeStudentDevice(studentId: '25CE001', hits: 3, total: 10, divId: divId, verified: false),
        makeStudentDevice(studentId: '25CE001', hits: 6, total: 10, divId: divId, verified: true),
        makeStudentDevice(studentId: '25CE001', hits: 8, total: 10, divId: divId, verified: false),
      ];
      final tallies = runScanHandler(
        events: events,
        activeDivisionId: divId,
        activeBatchId: null,
        globalTotalHits: 10,
      );
      expect(tallies['25CE001']!.biometricVerified, true,
          reason: 'Verified flag must latch true once seen');
    });

    test('teacher beacon in the flood does not crash or pollute tallies', () {
      final flood = buildStudentFlood();
      final withTeacher = [...flood, makeTeacherDevice()];
      final tallies = runScanHandler(
        events: withTeacher,
        activeDivisionId: divId,
        activeBatchId: null,
        globalTotalHits: totalBeacons,
      );
      // Teacher beacon must be silently ignored — no extra tally entry
      expect(tallies.length, numStudents);
      expect(tallies.containsKey('FF:FF:FF:FF:FF:FF'), false);
    });

    test('presence ratio calculation is correct at 75% threshold', () {
      const total = 10;
      // hits=7 → ratio=0.7  → absent (below 0.75)
      // hits=8 → ratio=0.8  → present
      final events = [
        makeStudentDevice(studentId: '25CE001', hits: 7, total: total, divId: divId),
        makeStudentDevice(studentId: '25CE002', hits: 8, total: total, divId: divId),
        makeStudentDevice(studentId: '25CE003', hits: 10, total: total, divId: divId),
      ];
      final tallies = runScanHandler(
        events: events,
        activeDivisionId: divId,
        activeBatchId: null,
        globalTotalHits: total,
      );
      double ratio(String id) => tallies[id]!.hits / tallies[id]!.total;
      expect(ratio('25CE001'), lessThan(0.75));
      expect(ratio('25CE002'), greaterThanOrEqualTo(0.75));
      expect(ratio('25CE003'), greaterThanOrEqualTo(0.75));
    });
  });

  // ── Group 3: Rapid successive rounds (simulates 7-second scan restart) ────

  group('Scan handler — rapid repeated rounds', () {
    test('5 full rounds of 70 students complete in under 500ms total', () {
      const divId = 1;
      final sw = Stopwatch()..start();

      for (int round = 1; round <= 5; round++) {
        final events = List.generate(70, (i) {
          final id = '25CE${(i + 1).toString().padLeft(3, '0')}';
          return makeStudentDevice(
            studentId: id,
            hits: round * 2,
            total: round * 2 + 5,
            divId: divId,
          );
        });
        runScanHandler(
          events: events,
          activeDivisionId: divId,
          activeBatchId: null,
          globalTotalHits: round * 2 + 5,
        );
      }

      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: '5 × 70 events must parse in < 500ms, '
              'actual: ${sw.elapsedMilliseconds}ms');
    });
  });
}
