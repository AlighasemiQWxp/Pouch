import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pouch/core/pouch_platform.dart';

void main() {
  test(
    'Desktop theme survives reopening without changing budget files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pouch-storage-test-',
      );
      final records = File('${directory.path}/pouch.data');
      await records.writeAsBytes([1, 2, 3]);
      final platform = DesktopPouchPlatform(
        applicationSupportDirectory: directory,
      );
      try {
        final bootstrap = await platform.bootstrap();
        expect(bootstrap.directory, directory.path);
        expect(bootstrap.legacyJsonCandidates, isEmpty);
        expect(await platform.loadThemeStyle(), 'classic');
        await platform.saveThemeStyle('forest');
        await platform.saveThemeStyle('ocean');
        await platform.close();
        await platform.bootstrap();
        expect(await platform.loadThemeStyle(), 'ocean');
        expect(await records.readAsBytes(), [1, 2, 3]);
        expect(
          directory.listSync().whereType<File>().where(
            (file) => file.path.endsWith('.tmp'),
          ),
          isEmpty,
        );
        await expectLater(
          platform.saveThemeStyle('invalid'),
          throwsArgumentError,
        );
        expect(await platform.loadThemeStyle(), 'ocean');
      } finally {
        await platform.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
