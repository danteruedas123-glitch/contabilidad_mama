// PRUEBAS EN EL CELULAR (emulador o real): cifrado de verdad con SQLCipher,
// llave en el Keystore de Android y la app completa de punta a punta.
//
//   flutter test integration_test -d emulator-5554
import 'dart:convert';
import 'dart:io';

import 'package:contabilidad_mama/datos/abrir_bd.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/main.dart' as app;
import 'package:contabilidad_mama/seguridad/almacen_seguro.dart';
import 'package:contabilidad_mama/seguridad/llave_bd.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

Future<void> limpiar() async {
  final ruta = await rutaBD();
  for (final f in [File(ruta), File('$ruta-journal'), File('$ruta-wal'), File('$ruta-shm')]) {
    if (f.existsSync()) f.deleteSync();
  }
  final a = AlmacenKeystore();
  for (final k in [kLlaveBD, 'pin.hash', 'pin.sal', 'pin.iter', 'pin.fallos', 'pin.bloqueado_hasta', 'rec.hash', 'rec.sal', 'rec.iter', 'bio.activa', 'auto.clave']) {
    await a.borrar(k);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('cifrado real', () {
    setUp(limpiar);

    testWidgets('el archivo de la base está cifrado: sin la llave es basura', (tester) async {
      final almacen = AlmacenKeystore();
      final db = await abrirBDCifrada(almacen);
      final repo = Repositorio(db);
      await repo.agregarMovimiento(const Movimiento(
          tipo: TipoMovimiento.egreso, monto: 987654, fecha: '2026-11-25', descripcion: 'SECRETO-DE-MAMA'));
      await db.close();

      final bytes = await File(await rutaBD()).readAsBytes();
      // Un SQLite normal empieza con "SQLite format 3"; uno cifrado no.
      expect(ascii.decode(bytes.sublist(0, 15), allowInvalid: true), isNot('SQLite format 3'));
      expect(latin1.decode(bytes).contains('SECRETO-DE-MAMA'), isFalse);
      expect(latin1.decode(bytes).contains('Mercado y comida'), isFalse);

      // Abrir sin llave o con otra llave falla
      Future<void> abrirCon(String? clave) async {
        final d = await cipher.openDatabase(await rutaBD(), password: clave, singleInstance: false);
        try {
          await d.rawQuery('SELECT count(*) FROM movimientos');
        } finally {
          await d.close();
        }
      }

      await expectLater(abrirCon(null), throwsA(anything));
      await expectLater(abrirCon('0' * 64), throwsA(anything));

      // Con la llave del Keystore sí se lee todo
      final otra = await abrirBDCifrada(almacen);
      final r2 = Repositorio(otra);
      expect((await r2.buscar('SECRETO')).single.monto, 987654);
      await otra.close();
    });

    testWidgets('la llave queda en el Keystore y es de 256 bits', (tester) async {
      final almacen = AlmacenKeystore();
      final db = await abrirBDCifrada(almacen);
      await db.close();
      expect(await almacen.leer(kLlaveBD), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    testWidgets('si la llave desaparece, NO se crea una base nueva encima', (tester) async {
      final almacen = AlmacenKeystore();
      final db = await abrirBDCifrada(almacen);
      await db.close();
      await almacen.borrar(kLlaveBD);
      await expectLater(abrirBDCifrada(almacen), throwsA(isA<LlavePerdida>()));
      expect(File(await rutaBD()).existsSync(), isTrue);
    });
  });

  group('app completa', () {
    setUpAll(limpiar);

    testWidgets('primer uso, anotar entrada y salida, y ver el balance', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byKey(const ValueKey('empezar')));
      await tester.pumpAndSettle();
      Future<void> pin(String p) async {
        for (final d in p.split('')) {
          await tester.tap(find.byKey(ValueKey('tecla-$d')));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.byKey(const ValueKey('pin-aceptar')));
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      await pin('2580');
      await pin('2580');
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('codigo-recuperacion')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ya-lo-anote')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('codigo-continuar')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // En el emulador no hay huella registrada: no pregunta. Si pregunta, "Ahora no".
      if (find.text('Ahora no').evaluate().isNotEmpty) {
        await tester.tap(find.text('Ahora no'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Te quedó'), findsOneWidget);

      Future<void> anotar(String boton, String valor, String desc) async {
        await tester.tap(find.byKey(ValueKey(boton)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('campo-monto')), valor);
        await tester.enterText(find.byKey(const ValueKey('campo-descripcion')), desc);
        FocusManager.instance.primaryFocus?.unfocus(); // cierra el teclado
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.scrollUntilVisible(find.byKey(const ValueKey('guardar')), 300,
            scrollable: find.descendant(of: find.byKey(const ValueKey('form-movimiento')), matching: find.byType(Scrollable)).first);
        await tester.ensureVisible(find.byKey(const ValueKey('guardar'))); // completo, no a medias
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('guardar')));
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      await anotar('nuevo-ingreso', '1500000', 'Quincena');
      await anotar('nuevo-egreso', '320000', 'Mercado');
      String txt(String k) => (tester.widget(find.byKey(ValueKey(k))) as Text).data!;
      expect(txt('total-ingresos'), r'$1.500.000');
      expect(txt('total-egresos'), r'$320.000');
      expect(txt('balance'), r'$1.180.000');
      expect(find.text('Quincena'), findsOneWidget);
    });
  });
}
