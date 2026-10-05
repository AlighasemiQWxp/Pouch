import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

class PouchBootstrap {
  const PouchBootstrap(this.directory, this.legacyJsonCandidates);

  final String directory;
  final List<String> legacyJsonCandidates;
}

abstract class PouchPlatform {
  static PouchPlatform create() {
    if (Platform.isAndroid) return AndroidPouchPlatform();
    if (Platform.isWindows || Platform.isLinux) return DesktopPouchPlatform();
    throw UnsupportedError('This platform is not supported by Pouch.');
  }

  bool get isDesktop;
  Future<PouchBootstrap> bootstrap();
  Future<void> close();
  Future<void> markDataImportComplete();
  Future<String> loadThemeStyle();
  Future<void> saveThemeStyle(String style);
  Future<String?> pickBackup();
  Future<bool> saveBackup(String filename, String contents);
  Future<void> printReport(String title, String html);
  Future<bool> printPdf(String title, Uint8List bytes);
  Future<bool> savePdf(String filename, Uint8List bytes);
  Future<void> openExternalUrl(String url);
}

class AndroidPouchPlatform implements PouchPlatform {
  static const _native = MethodChannel('com.daybook.app/legacy');

  @override
  bool get isDesktop => false;

  @override
  Future<PouchBootstrap> bootstrap() async {
    final data = await _native.invokeMapMethod<String, Object?>(
      'getBootstrapData',
    );
    final directory = data?['dataDirectory'] as String?;
    if (directory == null || directory.isEmpty) {
      throw StateError('Pouch could not read its Android storage location.');
    }
    final candidates = [
      data?['legacyPrimary'],
      data?['legacyRecovery'],
      data?['legacyOriginal'],
    ].whereType<String>().where((value) => value.isNotEmpty).toSet().toList();
    return PouchBootstrap(directory, candidates);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> markDataImportComplete() =>
      _native.invokeMethod<void>('markDataImportComplete');

  @override
  Future<String> loadThemeStyle() async {
    try {
      final style = await _native.invokeMethod<String>('getThemeStyle');
      if (style == 'ocean' || style == 'forest') return style!;
    } catch (_) {}
    return 'classic';
  }

  @override
  Future<void> saveThemeStyle(String style) =>
      _native.invokeMethod<void>('setThemeStyle', {'style': style});

  @override
  Future<String?> pickBackup() => _native.invokeMethod<String>('pickBackup');

  @override
  Future<bool> saveBackup(String filename, String contents) async =>
      await _native.invokeMethod<bool>('saveBackup', {
        'filename': filename,
        'contents': contents,
      }) ??
      false;

  @override
  Future<void> printReport(String title, String html) =>
      _native.invokeMethod<void>('printReport', {'title': title, 'html': html});

  @override
  Future<bool> printPdf(String title, Uint8List bytes) =>
      throw UnsupportedError('Android uses its existing report print window.');

  @override
  Future<bool> savePdf(String filename, Uint8List bytes) =>
      throw UnsupportedError('Android uses its existing report print window.');

  @override
  Future<void> openExternalUrl(String url) =>
      _native.invokeMethod<void>('openExternalUrl', {'url': url});
}

class DesktopPouchPlatform implements PouchPlatform {
  DesktopPouchPlatform({Directory? applicationSupportDirectory})
    : _supportDirectory = applicationSupportDirectory;

  final Directory? _supportDirectory;
  static const maxBackupBytes = 5000000;
  static const _jsonType = XTypeGroup(label: 'JSON', extensions: ['json']);
  static const _pdfType = XTypeGroup(label: 'PDF', extensions: ['pdf']);
  RandomAccessFile? _storageLock;
  String? _directory;

  @override
  bool get isDesktop => true;

  @override
  Future<PouchBootstrap> bootstrap() async {
    if (_storageLock != null) {
      throw StateError('Pouch storage is already open.');
    }
    final directory =
        _supportDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final lock = await File('${directory.path}/pouch.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } catch (_) {
      await lock.close();
      throw StateError('Pouch storage is already open in another window.');
    }
    _storageLock = lock;
    _directory = directory.path;
    return PouchBootstrap(directory.path, const []);
  }

  @override
  Future<void> close() async {
    final lock = _storageLock;
    _storageLock = null;
    _directory = null;
    if (lock != null) {
      try {
        await lock.unlock();
      } finally {
        await lock.close();
      }
    }
  }

  @override
  Future<void> markDataImportComplete() async {}

  File get _themeFile {
    if (_storageLock == null || _directory == null) {
      throw StateError('Pouch storage has not been opened.');
    }
    return File('$_directory/pouch-theme.txt');
  }

  @override
  Future<String> loadThemeStyle() async {
    try {
      final style = (await _themeFile.readAsString()).trim();
      if (style == 'ocean' || style == 'forest') return style;
    } on FileSystemException {
      return 'classic';
    }
    return 'classic';
  }

  @override
  Future<void> saveThemeStyle(String style) async {
    if (!['classic', 'ocean', 'forest'].contains(style)) {
      throw ArgumentError('The theme style is not supported.');
    }
    await _writeFile(_themeFile.path, utf8.encode(style));
  }

  @override
  Future<String?> pickBackup() async {
    final selected = await openFile(acceptedTypeGroups: [_jsonType]);
    if (selected == null) return null;
    final file = await File(selected.path).open();
    try {
      if (await file.length() > maxBackupBytes) {
        throw StateError('Backup exceeds the supported size.');
      }
      final bytes = await file.read(maxBackupBytes + 1);
      if (bytes.length > maxBackupBytes) {
        throw StateError('Backup exceeds the supported size.');
      }
      return utf8.decode(bytes);
    } finally {
      await file.close();
    }
  }

  @override
  Future<bool> saveBackup(String filename, String contents) async {
    final bytes = utf8.encode(contents);
    if (bytes.length > maxBackupBytes) {
      throw StateError('Backup exceeds the supported size.');
    }
    return _save(filename, bytes, _jsonType);
  }

  @override
  Future<void> printReport(String title, String html) =>
      throw UnsupportedError('Desktop reports use the PDF preview.');

  @override
  Future<bool> printPdf(String title, Uint8List bytes) =>
      Printing.layoutPdf(name: title, onLayout: (_) async => bytes);

  @override
  Future<bool> savePdf(String filename, Uint8List bytes) =>
      _save(filename, bytes, _pdfType);

  Future<bool> _save(String filename, List<int> bytes, XTypeGroup type) async {
    final target = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [type],
    );
    if (target == null) return false;
    if (_directory == null) {
      throw StateError('Pouch storage has not been opened.');
    }
    final storage = await Directory(_directory!).resolveSymbolicLinks();
    final destination = await File(target.path).absolute.parent
        .resolveSymbolicLinks();
    String normalized(String path) {
      var value = path.replaceAll('\\', '/');
      if (Platform.isWindows) value = value.toLowerCase();
      return value;
    }

    final protectedDirectory = normalized(storage);
    final selectedDirectory = normalized(destination);
    if (selectedDirectory == protectedDirectory ||
        selectedDirectory.startsWith('$protectedDirectory/')) {
      throw FileSystemException(
        'Exports cannot overwrite Pouch application storage.',
      );
    }
    await _writeFile(target.path, bytes);
    return true;
  }

  Future<void> _writeFile(String path, List<int> bytes) async {
    final temporary = File('$path.${Random.secure().nextInt(1 << 32)}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('The external URL is not supported.');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('The external URL could not be opened.');
    }
  }
}
