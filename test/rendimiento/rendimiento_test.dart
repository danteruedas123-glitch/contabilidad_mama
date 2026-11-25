// PRUEBAS DE RENDIMIENTO: con 60.000 movimientos (unos 30 al día durante
// 5 años y medio, mucho más de lo que mamá anotará) todo debe responder
// rápido. Los límites están pensados con margen para un celular de gama
// media (unas 4 veces más lento que este computador).
import 'dart:math';

import 'package:contabilidad_mama/core/dinero.dart';
import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/respaldo/respaldo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ayudantes.dart';

const cantidad = 60000;

Future<int> medir(String nombre, Future<void> Function() f, {int veces = 5}) async {
  await f(); // calentamiento
  final sw = Stopwatch()..start();
  for (var i = 0; i < veces; i++) {
    await f();
  }
  final ms = sw.elapsedMicroseconds ~/ veces ~/ 1000;
  // ignore: avoid_print
  print('  ⏱  $nombre: $ms ms');
  return ms;
}

void main() {
  late Repositorio r;
  late List<int> cats;

  setUpAll(() async {
    r = await repoDePrueba();
    cats = (await r.categorias()).map((c) => c.id!).toList();
    final azar = Random(7);
    final descripciones = ['Mercado', 'Bus', 'Pan', 'Chance', 'Bingo', 'Arriendo', 'Luz', 'Agua', 'Droguería', 'Almuerzo'];
    final ahora = DateTime.now().toUtc().toIso8601String();
    final sw = Stopwatch()..start();
    await r.db.transaction((t) async {
      final b = t.batch();
      for (var i = 0; i < cantidad; i++) {
        b.insert('movimientos', {
          'tipo': azar.nextInt(4) == 0 ? 'ingreso' : 'egreso',
          'monto': 1000 + azar.nextInt(500000),
          'categoria_id': cats[azar.nextInt(cats.length)],
          'descripcion': '${descripciones[azar.nextInt(descripciones.length)]} ${azar.nextInt(50)}',
          'fecha': sumarDias('2021-06-01', azar.nextInt(2000)),
          'creado_en': ahora,
          'actualizado_en': ahora,
        });
      }
      await b.commit(noResult: true);
    });
    // ignore: avoid_print
    print('  ⏱  insertar $cantidad movimientos: ${sw.elapsedMilliseconds} ms');
    expect(await r.totalMovimientos(), cantidad);
  });
  tearDownAll(() => r.db.close());

  final mes = Periodo.de(TipoPeriodo.mes, '2024-03-15');
  final anio = Periodo.de(TipoPeriodo.anio, '2024-03-15');

  test('las consultas por fecha usan el índice (no recorren toda la tabla)', () async {
    final plan = await r.db.rawQuery(
        "EXPLAIN QUERY PLAN SELECT sum(monto) FROM movimientos WHERE eliminado_en IS NULL AND fecha BETWEEN '2024-03-01' AND '2024-03-31'");
    final detalle = plan.map((f) => f['detail']).join(' | ');
    expect(detalle, contains('ix_mov_fecha'));
    expect(detalle, isNot(contains('SCAN movimientos')));
  });

  test('resumen del mes', () async => expect(await medir('resumen mes', () => r.resumen(mes)), lessThan(25)));
  test('resumen del año', () async => expect(await medir('resumen año', () => r.resumen(anio)), lessThan(60)));
  test('saldo acumulado (toda la historia)', () async => expect(await medir('saldo total', () => r.saldoHasta('2030-01-01')), lessThan(80)));
  test('totales por categoría del año', () async => expect(await medir('categorías año', () => r.totalesPorCategoria(anio)), lessThan(80)));
  test('gráfica del mes (por día)', () async => expect(await medir('serie mes', () => r.seriePorDia(mes)), lessThan(30)));
  test('gráfica del año (por mes)', () async => expect(await medir('serie año', () => r.seriePorMes('2024')), lessThan(80)));
  test('balance del juego del año', () async => expect(await medir('juego año', () => r.balanceJuego(anio)), lessThan(80)));
  test('lista del mes completa', () async => expect(await medir('lista mes', () => r.movimientos(mes)), lessThan(60)));
  test('búsqueda en toda la historia', () async => expect(await medir('buscar', () => r.buscar('Droguería 7')), lessThan(150)));
  test('sugerencias al escribir', () async =>
      expect(await medir('sugerencias', () => r.sugerencias(TipoMovimiento.egreso, prefijo: 'Mer')), lessThan(250)));

  test('pantalla de inicio completa (todo lo que carga a la vez)', () async {
    final ms = await medir('inicio completo', () => Future.wait([
          r.resumen(mes), r.resumen(mes.mover(-1)), r.saldoHasta(mes.hasta), r.balanceJuego(mes),
          r.movimientos(mes, limite: 3000), r.totalesPorCategoria(mes), r.seriePorDia(mes), r.categorias(incluirArchivadas: true),
        ]));
    expect(ms, lessThan(200));
  });

  test('agregar un movimiento con la base llena', () async {
    var n = 0;
    final ms = await medir('agregar 1', () async {
      await r.agregarMovimiento(gasto(1000, '2024-03-15', desc: 'rend ${n++}'));
    }, veces: 50);
    expect(ms, lessThan(20));
  });

  test('copia de seguridad de toda la base y restauración', () async {
    final resp = ServicioRespaldo(r, iteraciones: iteracionesMin);
    final sw = Stopwatch()..start();
    final archivo = await resp.crear('clave-larga');
    final crear = sw.elapsedMilliseconds;
    final otro = await repoDePrueba();
    sw.reset();
    final res = await ServicioRespaldo(otro).restaurar(archivo, 'clave-larga');
    final restaurar = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('  ⏱  copia de ${res.movimientos} movimientos: crear $crear ms, restaurar $restaurar ms, ${archivo.length ~/ 1024} KB');
    expect(res.movimientos, await r.totalMovimientos());
    expect(archivo.length, lessThan(tamanoMaximoRespaldo));
    expect(crear + restaurar, lessThan(15000));
    await otro.db.close();
  });

  test('leer montos: 100.000 lecturas en menos de 1 segundo', () {
    final entradas = ['50.000', '1 millón 200 mil', r'$ 25.000', '2,5 mil', '15.5', 'abc', '1.250.000,00'];
    final sw = Stopwatch()..start();
    for (var i = 0; i < 100000; i++) {
      leerMonto(entradas[i % entradas.length]);
    }
    // ignore: avoid_print
    print('  ⏱  100.000 lecturas de monto: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });
}
