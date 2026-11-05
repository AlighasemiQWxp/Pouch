import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:pouch/src/rust/frb_generated.dart';

String? pouchCoreLibraryPath(String operatingSystem, String executable) {
  if (operatingSystem == 'android') return 'libpouch_core.so';
  final directory = File(executable).parent.path;
  if (operatingSystem == 'windows') return '$directory/pouch_core.dll';
  if (operatingSystem == 'linux') return '$directory/lib/libpouch_core.so';
  return null;
}

Future<void> initializePouchCore() async {
  final path = pouchCoreLibraryPath(
    Platform.operatingSystem,
    Platform.resolvedExecutable,
  );
  if (path != null) {
    await RustLib.init(externalLibrary: ExternalLibrary.open(path));
    return;
  }
  await RustLib.init();
}
