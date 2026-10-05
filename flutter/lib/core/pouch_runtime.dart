import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:pouch/src/rust/frb_generated.dart';

Future<void> initializePouchCore() async {
  final directory = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isWindows) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open('$directory/pouch_core.dll'),
    );
    return;
  }
  if (Platform.isLinux) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open('$directory/lib/libpouch_core.so'),
    );
    return;
  }
  await RustLib.init();
}
