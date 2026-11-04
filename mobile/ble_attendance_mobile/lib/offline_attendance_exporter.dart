import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Handles offline attendance XML generation and export to local storage.
class OfflineAttendanceExporter {
  /// Resolves or creates the destination directory:
  /// `<storage>/BLE_Attendance/<YYYY-MM-DD>/`
  static Future<Directory> getExportDirectory(DateTime date) async {
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    Directory? baseDir;

    // On Android, check the public Downloads directory first so the teacher
    // can easily locate and open the exported XML file in their phone's Files app.
    if (!kIsWeb && Platform.isAndroid) {
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (publicDownload.existsSync()) {
        baseDir = publicDownload;
      }
    }

    if (baseDir == null && !kIsWeb) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null && extDir.existsSync()) {
          baseDir = extDir;
        }
      } catch (_) {}
    }

    if (baseDir == null && !kIsWeb) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null && downloads.existsSync()) {
          baseDir = downloads;
        }
      } catch (_) {}
    }

    baseDir ??= await getApplicationDocumentsDirectory();

    final targetDir = Directory('${baseDir.path}/BLE_Attendance/$dateStr');
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    return targetDir;
  }

  /// Generates the formatted XML string corresponding to the attendance session.
  static String generateXml(Map<String, dynamic> session) {
    final sessionId = session['sessionId']?.toString() ?? '';
    final subject = session['subject']?.toString() ?? 'Lecture';
    final assignmentId = session['assignmentId'];
    final savedAt =
        session['savedAt']?.toString() ?? DateTime.now().toIso8601String();

    String dateStr = '';
    String timeStr = '';
    if (savedAt.contains('T')) {
      final parts = savedAt.split('T');
      dateStr = parts[0];
      timeStr = parts[1].split('.').first;
    } else if (savedAt.contains(' ')) {
      final parts = savedAt.split(' ');
      dateStr = parts[0];
      timeStr = parts[1].split('.').first;
    } else {
      dateStr = savedAt;
    }

    final rawDecisions = session['decisions'];
    final decisions = rawDecisions is List
        ? rawDecisions
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];

    final presentCount =
        decisions.where((d) => d['is_present'] == true).length;
    final absentCount = decisions.length - presentCount;

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<attendanceSession>');
    buffer.writeln('  <metadata>');
    buffer.writeln('    <sessionId>${_escapeXml(sessionId)}</sessionId>');
    buffer.writeln('    <subject>${_escapeXml(subject)}</subject>');
    if (assignmentId != null) {
      buffer.writeln('    <assignmentId>$assignmentId</assignmentId>');
    }
    buffer.writeln('    <date>$dateStr</date>');
    buffer.writeln('    <time>$timeStr</time>');
    buffer.writeln('    <savedAt>$savedAt</savedAt>');
    buffer.writeln('    <totalStudents>${decisions.length}</totalStudents>');
    buffer.writeln('    <presentCount>$presentCount</presentCount>');
    buffer.writeln('    <absentCount>$absentCount</absentCount>');
    buffer.writeln('  </metadata>');
    buffer.writeln('  <students>');
    for (final d in decisions) {
      final id =
          d['student_id']?.toString() ?? d['id']?.toString() ?? 'UNKNOWN';
      final name = d['student_name']?.toString() ?? d['name']?.toString();
      final isPresent = d['is_present'] == true;
      final hits = d['hits'] ?? 0;
      final total = d['total'] ?? 0;
      final verified = d['verified'] == true;

      buffer.writeln('    <student>');
      buffer.writeln('      <id>${_escapeXml(id)}</id>');
      if (name != null && name.isNotEmpty && name != id) {
        buffer.writeln('      <name>${_escapeXml(name)}</name>');
      }
      buffer.writeln(
          '      <status>${isPresent ? "Present" : "Absent"}</status>');
      buffer.writeln('      <hits>$hits</hits>');
      buffer.writeln('      <totalHits>$total</totalHits>');
      buffer.writeln('      <verified>$verified</verified>');
      buffer.writeln('    </student>');
    }
    buffer.writeln('  </students>');
    buffer.writeln('</attendanceSession>');
    return buffer.toString();
  }

  /// Exports attendance session data to an XML file inside `BLE_Attendance/<date>/`.
  /// Attempts to run the python export script if Python is installed on the host;
  /// gracefully falls back to the native Dart generator if Python runtime is unavailable.
  static Future<File> exportAttendanceXml(
    Map<String, dynamic> session, {
    Directory? customTargetDir,
  }) async {
    final savedAtStr = session['savedAt']?.toString() ?? '';
    final date = DateTime.tryParse(savedAtStr) ?? DateTime.now();
    final targetDir = customTargetDir ?? await getExportDirectory(date);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final rawSessionId = session['sessionId']?.toString() ??
        'session_${DateTime.now().millisecondsSinceEpoch}';
    final safeSessionId =
        rawSessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final rawSubject = session['subject']?.toString() ?? 'Lecture';
    final safeSubject =
        rawSubject.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final fileName = 'attendance_${safeSubject}_$safeSessionId.xml';
    final targetFile = File('${targetDir.path}/$fileName');

    bool pythonSuccess = false;
    if (!kIsWeb) {
      try {
        final tmpDir = await getTemporaryDirectory();
        final jsonFile = File(
            '${tmpDir.path}/temp_attendance_${DateTime.now().millisecondsSinceEpoch}.json');
        await jsonFile.writeAsString(jsonEncode(session));

        final pythonCmd = Platform.isWindows ? 'python' : 'python3';
        final scriptCandidates = [
          'scripts/export_attendance_xml.py',
          '../scripts/export_attendance_xml.py',
          '../../scripts/export_attendance_xml.py',
        ];

        String? scriptPath;
        for (final candidate in scriptCandidates) {
          if (File(candidate).existsSync()) {
            scriptPath = candidate;
            break;
          }
        }

        if (scriptPath != null) {
          final res = await Process.run(pythonCmd, [
            scriptPath,
            '--input',
            jsonFile.path,
            '--output',
            targetFile.path,
          ]);
          if (res.exitCode == 0 && targetFile.existsSync()) {
            pythonSuccess = true;
          }
        }
        try {
          if (jsonFile.existsSync()) await jsonFile.delete();
        } catch (_) {}
      } catch (_) {
        // Python process execution unavailable on standard mobile devices
      }
    }

    if (!pythonSuccess) {
      final xmlContent = generateXml(session);
      await targetFile.writeAsString(xmlContent);
    }

    return targetFile;
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
