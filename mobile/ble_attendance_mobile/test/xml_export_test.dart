import 'dart:io';

import 'package:ble_attendance_mobile/offline_attendance_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineAttendanceExporter XML generation', () {
    final sampleSession = {
      'sessionId': 'offline-1730745600000',
      'assignmentId': 42,
      'subject': 'Operating Systems & Networks',
      'savedAt': '2026-11-04T14:30:00.000000',
      'decisions': [
        {
          'student_id': '25CE001',
          'student_name': 'Alice Smith',
          'is_present': true,
          'hits': 16,
          'total': 18,
          'verified': true,
        },
        {
          'student_id': '25CE002',
          'student_name': 'Bob <Jones> & "Co"',
          'is_present': false,
          'hits': 2,
          'total': 18,
          'verified': false,
        },
      ],
    };

    test('generates valid and complete XML structure', () {
      final xml = OfflineAttendanceExporter.generateXml(sampleSession);

      expect(xml, startsWith('<?xml version="1.0" encoding="utf-8"?>'));
      expect(xml, contains('<attendanceSession>'));
      expect(xml, contains('<metadata>'));
      expect(xml, contains('<sessionId>offline-1730745600000</sessionId>'));
      expect(xml, contains('<subject>Operating Systems &amp; Networks</subject>'));
      expect(xml, contains('<assignmentId>42</assignmentId>'));
      expect(xml, contains('<date>2026-11-04</date>'));
      expect(xml, contains('<time>14:30:00</time>'));
      expect(xml, contains('<totalStudents>2</totalStudents>'));
      expect(xml, contains('<presentCount>1</presentCount>'));
      expect(xml, contains('<absentCount>1</absentCount>'));

      expect(xml, contains('<students>'));
      expect(xml, contains('<id>25CE001</id>'));
      expect(xml, contains('<name>Alice Smith</name>'));
      expect(xml, contains('<status>Present</status>'));
      expect(xml, contains('<hits>16</hits>'));
      expect(xml, contains('<totalHits>18</totalHits>'));
      expect(xml, contains('<verified>true</verified>'));

      expect(xml, contains('<id>25CE002</id>'));
      expect(xml, contains('<name>Bob &lt;Jones&gt; &amp; &quot;Co&quot;</name>'));
      expect(xml, contains('<status>Absent</status>'));
      expect(xml, contains('<verified>false</verified>'));
    });

    test('exports XML file directly into BLE_Attendance date folder', () async {
      final tmpDir = await Directory.systemTemp.createTemp('ble_test_');
      try {
        final date = DateTime(2026, 11, 4);
        final dateStr = '2026-11-04';
        final targetSubdir = Directory('${tmpDir.path}/BLE_Attendance/$dateStr');

        final file = await OfflineAttendanceExporter.exportAttendanceXml(
          sampleSession,
          customTargetDir: targetSubdir,
        );

        expect(file.existsSync(), isTrue);
        expect(file.path, contains('BLE_Attendance'));
        expect(file.path, contains('2026-11-04'));
        expect(file.path.endsWith('.xml'), isTrue);

        final readBack = file.readAsStringSync();
        expect(readBack, contains('<sessionId>offline-1730745600000</sessionId>'));
        expect(readBack, contains('<status>Present</status>'));
        expect(readBack, contains('<status>Absent</status>'));
      } finally {
        if (tmpDir.existsSync()) {
          tmpDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
