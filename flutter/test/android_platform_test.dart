import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pouch/core/pouch_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.daybook.app/legacy');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'getBootstrapData':
              return {
                'dataDirectory': '/private/pouch',
                'legacyPrimary': 'primary',
                'legacyRecovery': 'recovery',
                'legacyOriginal': 'primary',
              };
            case 'getThemeStyle':
              return 'forest';
            case 'saveBackup':
              return false;
            default:
              return null;
          }
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android keeps ordered migration candidates and native theme storage',
    () async {
      final platform = AndroidPouchPlatform();
      final bootstrap = await platform.bootstrap();
      expect(bootstrap.directory, '/private/pouch');
      expect(bootstrap.legacyJsonCandidates, ['primary', 'recovery']);
      expect(await platform.loadThemeStyle(), 'forest');
      await platform.markDataImportComplete();
      expect(calls.last.method, 'markDataImportComplete');
    },
  );

  test(
    'Android keeps cancelled backup and original HTML printing contracts',
    () async {
      final platform = AndroidPouchPlatform();
      expect(await platform.pickBackup(), isNull);
      expect(await platform.saveBackup('pouch.json', '{}'), isFalse);
      await platform.printReport('Report', '<html>گزارش</html>');
      expect(calls.last.method, 'printReport');
      expect(calls.last.arguments, {
        'title': 'Report',
        'html': '<html>گزارش</html>',
      });
    },
  );
}
