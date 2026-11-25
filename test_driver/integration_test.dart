import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Guarda las capturas del recorrido en build/capturas/.
Future<void> main() => integrationDriver(
      onScreenshot: (nombre, bytes, [args]) async {
        final f = File('build/capturas/$nombre.png');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes);
        return true;
      },
    );
