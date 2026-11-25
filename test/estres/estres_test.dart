// PRUEBAS DE ESTRÉS: muchas operaciones a la vez, datos al azar (fuzzing),
// valores extremos y archivos de copia destrozados. La regla: la app nunca
// se cae y la plata siempre cuadra.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:contabilidad_mama/core/dinero.dart';
import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/respaldo/respaldo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ayudantes.dart';

void main() {
  late Repositorio r;
  setUp(() async => r = await repoDePrueba());
  tearDown(() => r.db.close());

  test('500 movimientos guardados AL MISMO TIEMPO: ninguno se pierde ni se duplica', () async {
    final ids = await Future.wait([
      for (var i = 1; i <= 500; i++) r.agregarMovimiento(i.isEven ? ingreso(i * 100, '2026-11-25') : gasto(i * 100, '2026-11-25')),
    ]);
    expect(ids.toSet().length, 500);
    final res = await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'));
    var ing = 0, egr = 0;
    for (var i = 1; i <= 500; i++) {
      i.isEven ? ing += i * 100 : egr += i * 100;
    }
    expect([res.ingresos, res.egresos, res.cantidad], [ing, egr, 500]);
  });

  test('3.000 operaciones al azar (agregar, editar, borrar, recuperar) contra un modelo en memoria', () async {
    final azar = Random(2026);
    final modelo = <int, Movimiento>{}; // los vivos
    final papelera = <int, Movimiento>{};
    for (var paso = 0; paso < 3000; paso++) {
      final op = azar.nextInt(10);
      if (op < 5 || modelo.isEmpty) {
        final m = Movimiento(
          tipo: azar.nextBool() ? TipoMovimiento.ingreso : TipoMovimiento.egreso,
          monto: 1 + azar.nextInt(2000000),
          fecha: sumarDias('2026-01-01', azar.nextInt(365)),
        );
        modelo[await r.agregarMovimiento(m)] = m;
      } else if (op < 7) {
        final id = modelo.keys.elementAt(azar.nextInt(modelo.length));
        final nuevo = (await r.movimiento(id))!.copiar(monto: 1 + azar.nextInt(900000), tipo: azar.nextBool() ? TipoMovimiento.ingreso : TipoMovimiento.egreso);
        await r.actualizarMovimiento(nuevo);
        modelo[id] = nuevo;
      } else if (op < 9) {
        final id = modelo.keys.elementAt(azar.nextInt(modelo.length));
        await r.eliminarMovimiento(id);
        papelera[id] = modelo.remove(id)!;
      } else if (papelera.isNotEmpty) {
        final id = papelera.keys.elementAt(azar.nextInt(papelera.length));
        await r.restaurarMovimiento(id);
        modelo[id] = papelera.remove(id)!;
      }
    }
    var ing = 0, egr = 0;
    for (final m in modelo.values) {
      m.tipo == TipoMovimiento.ingreso ? ing += m.monto : egr += m.monto;
    }
    final res = await r.resumen(Periodo.de(TipoPeriodo.anio, '2026-01-01'));
    expect([res.ingresos, res.egresos, res.cantidad], [ing, egr, modelo.length]);
    expect((await r.papelera()).length, papelera.length);
  });

  test('montos máximos: 50.000 × \$100.000 millones suman exacto (sin desbordar)', () async {
    final ahora = DateTime.now().toIso8601String();
    await r.db.transaction((t) async {
      final b = t.batch();
      for (var i = 0; i < 50000; i++) {
        b.insert('movimientos', {'tipo': 'ingreso', 'monto': montoMaximo, 'fecha': '2026-11-25', 'creado_en': ahora, 'actualizado_en': ahora});
      }
      await b.commit(noResult: true);
    });
    final res = await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'));
    expect(res.ingresos, 50000 * montoMaximo); // 5.000.000.000.000.000
    expect(formatearCOP(res.ingresos), r'$5.000.000.000.000.000');
  });

  test('fechas en los extremos del calendario', () async {
    await r.agregarMovimiento(gasto(1, '2000-01-01'));
    await r.agregarMovimiento(gasto(2, '2200-12-31'));
    await r.agregarMovimiento(gasto(3, '2028-02-29'));
    expect(await r.saldoHasta('2200-12-31'), -6);
    expect(() => r.agregarMovimiento(gasto(1, '1999-12-31')), throwsA(isA<ErrorDatos>()));
  });

  test('textos raros: emojis, otros alfabetos, caracteres invisibles, se guardan idénticos', () async {
    const textos = ['Arepas 🫓 y café ☕', 'مرحبا', '中文测试', 'a​b‏c', 'Ñandú ÁÉÍÓÚ üñ', '"comillas" \'simples\' `acento`', 'línea1\nlínea2'];
    for (final t in textos) {
      await r.agregarMovimiento(Movimiento(tipo: TipoMovimiento.egreso, monto: 1, fecha: '2026-11-25', descripcion: t, nota: t));
    }
    final guardados = (await r.movimientos(Periodo.de(TipoPeriodo.dia, '2026-11-25'))).map((m) => m.descripcion).toSet();
    expect(guardados, textos.toSet());
    expect((await r.buscar('🫓')).single.descripcion, textos.first);
  });

  test('fuzzing del lector de montos: 30.000 entradas al azar nunca lo rompen', () {
    final azar = Random(99);
    const alfabeto = "0123456789.,\$ milkMpalosucny-+=%abcñó'\u0000\n";
    for (var i = 0; i < 30000; i++) {
      final largo = azar.nextInt(25);
      final s = String.fromCharCodes(List.generate(largo, (_) => alfabeto.codeUnitAt(azar.nextInt(alfabeto.length))));
      final res = leerMonto(s);
      if (res.valido) {
        expect(res.valor, inInclusiveRange(1, montoMaximo), reason: '"$s"');
      } else {
        expect(res.error, isNotEmpty, reason: '"$s"');
      }
    }
  });

  test('fuzzing de fechas: nada inválido pasa la validación', () {
    final azar = Random(5);
    for (var i = 0; i < 20000; i++) {
      final f = '${azar.nextInt(3000).toString().padLeft(4, '0')}-${azar.nextInt(15).toString().padLeft(2, '0')}-${azar.nextInt(35).toString().padLeft(2, '0')}';
      if (esFechaValida(f)) {
        final d = DateTime.parse('${f}T00:00:00Z');
        expect(aTexto(d), f);
      }
    }
  });

  test('fuzzing de copias: 400 archivos destrozados al azar → solo errores controlados y la base intacta', () async {
    await r.agregarMovimiento(ingreso(123456, '2026-11-25', desc: 'Base'));
    final resp = ServicioRespaldo(r, iteraciones: iteracionesMin);
    final bueno = await resp.crear('clave-fuzz');
    final azar = Random(31);
    var rechazados = 0;
    for (var i = 0; i < 400; i++) {
      final b = Uint8List.fromList(bueno);
      switch (i % 4) {
        case 0: // cambia bytes al azar
          for (var k = 0; k < 1 + azar.nextInt(5); k++) {
            b[azar.nextInt(b.length)] = azar.nextInt(256);
          }
        case 1: // lo corta
          final corto = b.sublist(0, azar.nextInt(b.length - 1));
          try {
            await ServicioRespaldo(r, iteraciones: iteracionesMin).restaurar(corto, 'clave-fuzz');
          } on ErrorRespaldo {
            rechazados++;
          }
          continue;
        case 2: // reemplaza un valor del JSON
          final j = jsonDecode(utf8.decode(bueno)) as Map<String, dynamic>;
          final k = j.keys.elementAt(azar.nextInt(j.length));
          j[k] = [null, 0, -1, '', 'x' * 50, [], {}, 1e308][azar.nextInt(8)];
          b.setAll(0, Uint8List(b.length));
          final nuevo = utf8.encode(jsonEncode(j));
          try {
            await resp.leer(nuevo, 'clave-fuzz');
          } on ErrorRespaldo {
            rechazados++;
          }
          continue;
        default: // basura total
          for (var k = 0; k < b.length; k++) {
            b[k] = azar.nextInt(256);
          }
      }
      try {
        await ServicioRespaldo(r, iteraciones: iteracionesMin).restaurar(b, 'clave-fuzz');
      } on ErrorRespaldo {
        rechazados++;
      }
    }
    // ignore: avoid_print
    print('  🔒 $rechazados de 400 archivos dañados fueron rechazados');
    expect(await r.saldoHasta('2030-01-01'), 123456);
    expect(await r.totalMovimientos(), 1);
    expect(rechazados, greaterThan(390));
  });

  test('contraseñas de copia al azar nunca abren una copia ajena', () async {
    await r.agregarMovimiento(ingreso(1, '2026-11-25'));
    final resp = ServicioRespaldo(r, iteraciones: iteracionesMin);
    final archivo = await resp.crear('la-clave-de-mama');
    for (final intento in ['la-clave-de-mamá', 'LA-CLAVE-DE-MAMA', 'la-clave-de-mama ', '', 'la-clave-de-mam']) {
      await expectLater(resp.leer(archivo, intento), throwsA(isA<ErrorRespaldo>()));
    }
  });

  test('categorías: crear 300 seguidas y renombrar sin romper nada', () async {
    for (var i = 0; i < 300; i++) {
      await r.guardarCategoria(Categoria(nombre: 'Cat $i', tipo: TipoCategoria.values[i % 3], icono: 'otros', color: 0xFF000000 + i));
    }
    final todas = await r.categorias();
    expect(todas.length, 300 + 18);
    expect(todas.map((c) => c.nombre.toLowerCase()).toSet().length, todas.length);
  });
}
