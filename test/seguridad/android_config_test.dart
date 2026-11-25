// PRUEBAS DE SEGURIDAD de la configuración Android (lo que corrigió la
// auditoría de Foodzy: H-05 firma, H-06 backup, H-07 R8, H-08 logs).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String leer(String ruta) => File(ruta).readAsStringSync();

void main() {
  final manifest = leer('android/app/src/main/AndroidManifest.xml');
  final gradle = leer('android/app/build.gradle.kts');
  final actividad = leer('android/app/src/main/kotlin/com/familia/contabilidadmama/MainActivity.kt');
  final gitignore = leer('android/.gitignore');

  test('la app release no tiene permiso de internet (los datos no salen del celular)', () {
    expect(manifest, contains('android.permission.INTERNET" tools:node="remove"'));
    expect(RegExp(r'<uses-permission android:name="android.permission.INTERNET"\s*/>').hasMatch(manifest), isFalse);
  });

  test('sin copias automáticas a la nube ni por adb (H-06)', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    final reglas = leer('android/app/src/main/res/xml/reglas_extraccion_datos.xml');
    expect(RegExp('<exclude domain="root"').allMatches(reglas).length, 2);
  });

  test('sin tráfico sin cifrar', () {
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
  });

  test('pantalla protegida contra capturas y vista en recientes (FLAG_SECURE)', () {
    expect(actividad, contains('FLAG_SECURE'));
    expect(actividad.indexOf('FLAG_SECURE'), lessThan(actividad.indexOf('super.onCreate')));
  });

  test('solo exporta la actividad principal', () {
    expect(RegExp('android:exported="true"').allMatches(manifest).length, 1);
    expect(manifest, isNot(contains('<provider')));
    expect(manifest, isNot(contains('<receiver')));
  });

  test('release con R8, recursos encogidos y llave propia (H-05, H-07)', () {
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(gradle, contains('key.properties'));
    expect(gitignore, contains('key.properties'));
    expect(gitignore, contains('**/*.jks'));
  });

  test('ninguna contraseña ni llave dentro del código (H-01)', () {
    final archivos = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    final sospechoso = RegExp(r'''(storePassword|api[_-]?key|secret|BEGIN (RSA )?PRIVATE KEY)\s*[:=]\s*['"][^'"]{6,}''', caseSensitive: false);
    for (final f in archivos) {
      expect(sospechoso.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('sin print/debugPrint que puedan filtrar datos al log (H-08)', () {
    final archivos = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in archivos) {
      expect(RegExp(r'\b(print|debugPrint)\(').hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('sin librerías de red, analítica ni publicidad', () {
    final pubspec = leer('pubspec.yaml');
    for (final p in ['http:', 'dio:', 'firebase', 'google_mobile_ads', 'sentry', 'analytics']) {
      expect(pubspec, isNot(contains(p)), reason: p);
    }
  });
}
