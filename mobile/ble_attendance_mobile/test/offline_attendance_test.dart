import 'package:ble_attendance_mobile/offline_attendance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleSession = {
    'sessionId': 'offline-1730745600000',
    'subject': 'Database Management',
    'savedAt': '2026-11-04T10:15:00.000000',
    'decisions': [
      {
        'student_id': '25CE001',
        'student_name': 'Student One',
        'is_present': true,
        'hits': 15,
        'total': 15,
        'verified': true,
      },
      {
        'student_id': '25CE002',
        'student_name': 'Student Two',
        'is_present': false,
        'hits': 1,
        'total': 15,
        'verified': false,
      },
      {
        'student_id': '25CE003',
        'student_name': 'Student Three',
        'is_present': true,
        'hits': 12,
        'total': 15,
        'verified': false,
      },
    ],
  };

  group('OfflineAttendanceListPage Widget Tests', () {
    testWidgets('renders session card with required message, Show and Upload buttons',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineAttendanceListPage(
            sessions: [sampleSession],
            onUpload: (_) async {},
            onDiscard: (_) async {},
          ),
        ),
      );

      // Verify subject and session ID
      expect(find.text('Database Management'), findsOneWidget);
      expect(find.textContaining('offline-1730745600000'), findsOneWidget);
      expect(find.textContaining('Date: 2026-11-04'), findsOneWidget);

      // Verify required message
      expect(
        find.text(
          'You can upload this attendance. Previously it was not stored on the server, but now that your phone is connected to the server, you can send it.',
        ),
        findsOneWidget,
      );

      // Verify Show and Upload buttons
      expect(find.widgetWithText(OutlinedButton, 'Show'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Upload'), findsOneWidget);
    });
  });

  group('OfflineAttendanceDetailsPage Widget Tests', () {
    testWidgets('displays present and absent numbers and filters students',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineAttendanceDetailsPage(
            session: sampleSession,
          ),
        ),
      );

      // Verify summary numbers: 3 total, 2 present, 1 absent
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Total count
      expect(find.text('Present'), findsWidgets);
      expect(find.text('2'), findsOneWidget); // Present count
      expect(find.text('Absent'), findsWidgets);
      expect(find.text('1'), findsOneWidget); // Absent count

      // Verify initially all students are shown
      expect(find.text('25CE001'), findsOneWidget);
      expect(find.text('25CE002'), findsOneWidget);
      expect(find.text('25CE003'), findsOneWidget);

      // Tap Present filter tab
      await tester.tap(find.text('Present (2)'));
      await tester.pumpAndSettle();

      // Only present students should be visible in the list
      expect(find.text('25CE001'), findsOneWidget);
      expect(find.text('25CE003'), findsOneWidget);
      expect(find.text('25CE002'), findsNothing);

      // Tap Absent filter tab
      await tester.tap(find.text('Absent (1)'));
      await tester.pumpAndSettle();

      // Only absent student should be visible in the list
      expect(find.text('25CE002'), findsOneWidget);
      expect(find.text('25CE001'), findsNothing);
      expect(find.text('25CE003'), findsNothing);

      // Verify Export button is present in AppBar
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
    });
  });
}
