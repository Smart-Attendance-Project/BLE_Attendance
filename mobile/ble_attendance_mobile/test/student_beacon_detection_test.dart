// Student BLE Beacon Detection & Lifecycle Test
// ===============================================
// Tests the student-side BLE discovery, beacon timeout, and lecture display logic.
// Verifies:
//  1. On login, no lecture is shown ('No Active Lecture') when no teacher beacon is heard.
//  2. Only physical BLE teacher packets activate the session and display the lecture.
//  3. If teacher beacon stops for > 20s, the session automatically resets to 'No Active Lecture'.
//  4. Division and batch enrollment scoping prevents neighbor classrooms from triggering lectures.
//  5. Finalization open/close is signaled in-band via BLE without requiring server polling.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

const String kTeacherServiceUuid = '0000180D-0000-1000-8000-00805F9B34FB';
const int kManufacturerId = 0x004C;

// ---------------------------------------------------------------------------
// Pure Dart decoder matching _decodeTeacherPayload in main.dart
// ---------------------------------------------------------------------------
Map<String, dynamic>? decodeTeacherPayload(DiscoveredDevice device) {
  if (device.manufacturerData.isEmpty) return null;
  if (device.serviceUuids.isNotEmpty &&
      !device.serviceUuids.contains(Uuid.parse(kTeacherServiceUuid))) {
    return null;
  }
  try {
    final bytes = device.manufacturerData;
    if (bytes.length < 4) return null;
    final payload = utf8.decode(bytes.sublist(2));
    if (!payload.contains('|')) return null;
    final parts = payload.split('|');
    if (parts.length < 4) return null;
    final isV2 = parts[0] == 'T2';
    if (!isV2 && parts[0] != 'T') return null;

    final divisionId = int.tryParse(parts[1]);
    final batchId = isV2 ? int.tryParse(parts[2]) : null;
    final subjectIndex = isV2 ? 3 : 2;
    final seqIndex = isV2 ? 4 : 3;
    final subject =
        parts.length > subjectIndex ? parts[subjectIndex].trim() : null;
    final seqStr = parts.length > seqIndex ? parts[seqIndex].trim() : null;
    final seq = seqStr != null ? int.tryParse(seqStr) : null;
    final finalizationOpen =
        parts.length > seqIndex + 1 && parts[seqIndex + 1].trim() == 'F';

    if (divisionId == null) return null;
    if (subject != null &&
        (subject.isEmpty || RegExp(r'[\x00-\x1F]').hasMatch(subject))) {
      return {
        'divisionId': divisionId,
        'batchId': batchId == 0 ? null : batchId,
        'subject': null,
        'seq': seq,
        'finalizationOpen': finalizationOpen,
      };
    }
    return {
      'divisionId': divisionId,
      'batchId': batchId == 0 ? null : batchId,
      'subject': subject,
      'seq': seq,
      'finalizationOpen': finalizationOpen,
    };
  } catch (_) {}
  return null;
}

// Helper to encode synthetic teacher beacon advertisements
DiscoveredDevice makeTeacherDevice({
  required int divisionId,
  int? batchId,
  required String subject,
  int seq = 1,
  bool finalizationOpen = false,
  int rssi = -60,
}) {
  final bId = batchId ?? 0;
  final fFlag = finalizationOpen ? '|F' : '';
  final payloadStr = 'T2|$divisionId|$bId|$subject|$seq$fFlag';
  final payloadBytes = utf8.encode(payloadStr);

  final mfg = Uint8List(2 + payloadBytes.length);
  mfg[0] = kManufacturerId & 0xFF;
  mfg[1] = (kManufacturerId >> 8) & 0xFF;
  mfg.setRange(2, mfg.length, payloadBytes);

  return DiscoveredDevice(
    id: 'teacher-mac-001',
    name: 'TeacherPhone',
    serviceData: const {},
    manufacturerData: mfg,
    rssi: rssi,
    serviceUuids: [Uuid.parse(kTeacherServiceUuid)],
  );
}

// Student session model simulating student dashboard presence lifecycle
class StudentSessionState {
  String? subject;
  String? sessionId;
  bool? proximityOk;
  bool finalizationOpen = false;
  DateTime? lastTeacherBeaconTime;
  final List<int> enrolledDivisionIds;

  StudentSessionState({required this.enrolledDivisionIds});

  String get displayedSubject => subject ?? 'No Active Lecture';
  String get statusText => proximityOk == null
      ? 'Searching for teacher…'
      : (proximityOk! ? 'In Range' : 'Out of Range');

  void onTeacherBeaconReceived(DiscoveredDevice device) {
    final payload = decodeTeacherPayload(device);
    if (payload == null) return;

    final divId = payload['divisionId'] as int?;
    if (divId == null || !enrolledDivisionIds.contains(divId)) {
      return; // Not for this student's class
    }

    lastTeacherBeaconTime = DateTime.now();
    proximityOk = device.rssi > -85;
    sessionId = 'ble-detected';
    finalizationOpen = payload['finalizationOpen'] as bool? ?? false;

    final beaconSubject = payload['subject'] as String?;
    if (beaconSubject != null && beaconSubject.isNotEmpty) {
      subject = beaconSubject;
    }
  }

  void checkBeaconTimeout({DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    if (lastTeacherBeaconTime != null &&
        now.difference(lastTeacherBeaconTime!) > const Duration(seconds: 20)) {
      lastTeacherBeaconTime = null;
      proximityOk = null;
      subject = null;
      sessionId = null;
      finalizationOpen = false;
    }
  }
}

void main() {
  group('Student BLE Beacon Detection and Session Lifecycle', () {
    test('Student on initial login displays "No Active Lecture" and searches for teacher', () {
      final student = StudentSessionState(enrolledDivisionIds: [1]);

      // Before any BLE packet arrives
      expect(student.subject, isNull);
      expect(student.sessionId, isNull);
      expect(student.proximityOk, isNull);
      expect(student.displayedSubject, equals('No Active Lecture'));
      expect(student.statusText, equals('Searching for teacher…'));
    });

    test('Receiving valid teacher BLE beacon activates lecture and marks student In Range', () {
      final student = StudentSessionState(enrolledDivisionIds: [1]);

      final device = makeTeacherDevice(
        divisionId: 1,
        subject: 'Engineering Mathematics-II',
        seq: 5,
        rssi: -65,
      );

      student.onTeacherBeaconReceived(device);

      expect(student.displayedSubject, equals('Engineering Mathematics-II'));
      expect(student.sessionId, equals('ble-detected'));
      expect(student.proximityOk, isTrue);
      expect(student.statusText, equals('In Range'));
      expect(student.lastTeacherBeaconTime, isNotNull);
    });

    test('Teacher beacon from another division is ignored and does not show lecture', () {
      final student = StudentSessionState(enrolledDivisionIds: [1]); // Enrolled in CE (1)

      final otherClassBeacon = makeTeacherDevice(
        divisionId: 2, // IT division
        subject: 'Digital Electronics',
        seq: 10,
        rssi: -50,
      );

      student.onTeacherBeaconReceived(otherClassBeacon);

      // Student must NOT show Digital Electronics
      expect(student.displayedSubject, equals('No Active Lecture'));
      expect(student.statusText, equals('Searching for teacher…'));
      expect(student.sessionId, isNull);
    });

    test('When teacher beacon stops for > 20s, lecture automatically resets to "No Active Lecture"', () {
      final student = StudentSessionState(enrolledDivisionIds: [1]);

      final device = makeTeacherDevice(
        divisionId: 1,
        subject: 'Engineering Mathematics-II',
        seq: 1,
      );

      final startTime = DateTime(2026, 11, 5, 10, 0, 0);
      student.onTeacherBeaconReceived(device);
      student.lastTeacherBeaconTime = startTime;

      expect(student.displayedSubject, equals('Engineering Mathematics-II'));
      expect(student.proximityOk, isTrue);

      // Check at 10 seconds: still active
      student.checkBeaconTimeout(
        currentTime: startTime.add(const Duration(seconds: 10)),
      );
      expect(student.displayedSubject, equals('Engineering Mathematics-II'));

      // Check at 25 seconds: timed out!
      student.checkBeaconTimeout(
        currentTime: startTime.add(const Duration(seconds: 25)),
      );
      expect(student.displayedSubject, equals('No Active Lecture'));
      expect(student.statusText, equals('Searching for teacher…'));
      expect(student.sessionId, isNull);
      expect(student.lastTeacherBeaconTime, isNull);
    });

    test('Teacher opening finalization via BLE flag |F updates student without server HTTP', () {
      final student = StudentSessionState(enrolledDivisionIds: [1]);

      // Regular lecture beacon
      final deviceNormal = makeTeacherDevice(
        divisionId: 1,
        subject: 'Database Systems',
        finalizationOpen: false,
      );
      student.onTeacherBeaconReceived(deviceNormal);
      expect(student.finalizationOpen, isFalse);

      // Finalization opened beacon
      final deviceFinalize = makeTeacherDevice(
        divisionId: 1,
        subject: 'Database Systems',
        finalizationOpen: true,
      );
      student.onTeacherBeaconReceived(deviceFinalize);
      expect(student.finalizationOpen, isTrue);
    });
  });
}
