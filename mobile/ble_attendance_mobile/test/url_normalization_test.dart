import 'package:flutter_test/flutter_test.dart';
import 'package:ble_attendance_mobile/main.dart';

void main() {
  group('Base URL Normalization and Security', () {
    test('adds https scheme when no scheme provided', () {
      expect(normalizeBaseUrl('example.com', isRelease: false), 'https://example.com');
      expect(normalizeBaseUrl('api.college.edu', isRelease: true), 'https://api.college.edu');
    });

    test('strips trailing slashes', () {
      expect(normalizeBaseUrl('https://example.com/', isRelease: false), 'https://example.com');
      expect(normalizeBaseUrl('https://example.com///', isRelease: true), 'https://example.com//');
    });

    test('allows http scheme in debug/development mode', () {
      expect(
        normalizeBaseUrl('http://10.0.2.2:8000', isRelease: false),
        'http://10.0.2.2:8000',
      );
    });

    test('rejects http scheme in release mode', () {
      expect(
        () => normalizeBaseUrl('http://example.com', isRelease: true),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Production builds require HTTPS'),
        )),
      );
    });

    test('rejects empty or whitespace URLs', () {
      expect(() => normalizeBaseUrl(''), throwsA(isA<Exception>()));
      expect(() => normalizeBaseUrl('   '), throwsA(isA<Exception>()));
    });
  });
}
