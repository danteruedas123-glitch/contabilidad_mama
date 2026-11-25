import 'dart:math';

import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ayudantes.dart';

void main() {
  late Repositorio r;
  late Map<String, int> cat;

  setUp(() async {
    r = await repoDePrueba();
    cat = await idsCategorias(r);
  });
  tearDown(() => r.db.close());

  test('arranca con las categorías iniciales, incluida Juego para ambos lados', () async {
    final cats = await r.categorias();
    expect(cats.map((c) => c.nombre), containsAll(['Trabajo', 'Juego', 'Gastos personales', 'Gastos por fuera', 'Otros']));
    final juego = cats.firstWhere((c) => c.nombre == 'Juego');
    expect(juego.tipo.sirvePara(TipoMovimiento.ingreso), isTrue);
    expect(juego.tipo.sirvePara(TipoMovimiento.egreso), isTrue);
  });

  test('resumen por día, semana, mes y año cuadra al peso', () async {
    await r.agregarMovimiento(ingreso(1500000, '2026-11-02', cat: cat['Trabajo']));
    await r.agregarMovimiento(gasto(350000, '2026-11-02', cat: cat['Mercado y comida']));
    await r.agregarMovimiento(gasto(85500, '2026-11-25', cat: cat['Servicios']));
    await r.agregarMovimiento(ingreso(200000, '2026-11-25', cat: cat['Juego']));
    await r.agregarMovimiento(gasto(50000, '2026-11-26', cat: cat['Juego']));
    await r.agregarMovimiento(gasto(10000, '2026-10-31')); // otro mes, sin categoría

    final dia = await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'));
    expect([dia.ingresos, dia.egresos, dia.balance, dia.cantidad], [200000, 85500, 114500, 2]);

    final semana = await r.resumen(Periodo.de(TipoPeriodo.semana, '2026-11-25'));
    expect([semana.ingresos, semana.egresos], [200000, 135500]);

    final mes = await r.resumen(Periodo.de(TipoPeriodo.mes, '2026-11-25'));
    expect([mes.ingresos, mes.egresos, mes.balance], [1700000, 485500, 1214500]);

    final anio = await r.resumen(Periodo.de(TipoPeriodo.anio, '2026-11-25'));
    expect(anio.egresos, 495500);
    expect(await r.saldoHasta('2026-12-31'), 1700000 - 495500);
    expect(await r.saldoHasta('2026-11-01'), -10000);
  });

  test('balance del juego: lo ganado menos lo jugado', () async {
    await r.agregarMovimiento(ingreso(200000, '2026-11-25', cat: cat['Juego'], desc: 'Bingo'));
    await r.agregarMovimiento(gasto(50000, '2026-11-20', cat: cat['Juego'], desc: 'Cartones'));
    await r.agregarMovimiento(gasto(30000, '2026-11-21', cat: cat['Juego']));
    await r.agregarMovimiento(gasto(99999, '2026-11-21', cat: cat['Salud'])); // no cuenta
    final b = await r.balanceJuego(Periodo.de(TipoPeriodo.mes, '2026-11-01'));
    expect([b.ganado, b.jugado, b.neto], [200000, 80000, 120000]);

    // Si la renombra ("Lotería y bingo"), sigue contando como juego por su ícono
    final juego = (await r.categorias()).firstWhere((c) => c.nombre == 'Juego');
    await r.guardarCategoria(juego.copiar(nombre: 'Lotería y bingo'));
    expect((await r.balanceJuego(Periodo.de(TipoPeriodo.mes, '2026-11-01'))).neto, 120000);
  });

  test('totales por categoría separan entradas y salidas', () async {
    await r.agregarMovimiento(ingreso(100000, '2026-11-25', cat: cat['Juego']));
    await r.agregarMovimiento(gasto(40000, '2026-11-25', cat: cat['Juego']));
    await r.agregarMovimiento(gasto(60000, '2026-11-25', cat: cat['Juego']));
    await r.agregarMovimiento(gasto(5000, '2026-11-25'));
    final t = await r.totalesPorCategoria(Periodo.de(TipoPeriodo.dia, '2026-11-25'));
    final juegoIngreso = t.firstWhere((x) => x.categoria?.nombre == 'Juego' && x.tipo == TipoMovimiento.ingreso);
    final juegoGasto = t.firstWhere((x) => x.categoria?.nombre == 'Juego' && x.tipo == TipoMovimiento.egreso);
    expect([juegoIngreso.total, juegoGasto.total, juegoGasto.cantidad], [100000, 100000, 2]);
    expect(t.firstWhere((x) => x.categoria == null).total, 5000);
  });

  test('series por día y por mes rellenan los huecos con cero', () async {
    await r.agregarMovimiento(gasto(1000, '2026-11-24'));
    await r.agregarMovimiento(ingreso(5000, '2026-11-26'));
    final dias = await r.seriePorDia(Periodo.de(TipoPeriodo.semana, '2026-11-25'));
    expect(dias.length, 7);
    expect(dias.map((p) => p.egresos).toList(), [0, 1000, 0, 0, 0, 0, 0]);
    expect(dias.map((p) => p.ingresos).toList(), [0, 0, 0, 5000, 0, 0, 0]);
    final meses = await r.seriePorMes('2026');
    expect(meses.length, 12);
    expect(meses[10].ingresos, 5000);
    expect(meses.where((m) => m.clave != '2026-11').every((m) => m.ingresos == 0 && m.egresos == 0), isTrue);
  });

  group('nada se pierde', () {
    test('eliminar manda a la papelera y restaurar lo devuelve con todo', () async {
      final id = await r.agregarMovimiento(gasto(70000, '2026-11-25', cat: cat['Salud'], desc: 'Droguería'));
      await r.eliminarMovimiento(id);
      expect((await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'))).egresos, 0);
      expect((await r.papelera()).single.descripcion, 'Droguería');

      await r.restaurarMovimiento(id);
      expect((await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'))).egresos, 70000);
      expect(await r.papelera(), isEmpty);
    });

    test('el borrado definitivo solo funciona desde la papelera', () async {
      final id = await r.agregarMovimiento(gasto(1000, '2026-11-25'));
      await r.eliminarDefinitivo(id); // no está en la papelera: no hace nada
      expect(await r.movimiento(id), isNotNull);
      await r.eliminarMovimiento(id);
      await r.eliminarDefinitivo(id);
      expect(await r.movimiento(id), isNull);
    });

    test('no se puede editar algo que está en la papelera', () async {
      final id = await r.agregarMovimiento(gasto(1000, '2026-11-25'));
      await r.eliminarMovimiento(id);
      final m = (await r.movimiento(id))!;
      expect(() => r.actualizarMovimiento(m.copiar(monto: 5)), throwsA(isA<ErrorDatos>()));
    });

    test('una categoría con movimientos no se puede borrar, solo archivar', () async {
      await r.agregarMovimiento(gasto(1000, '2026-11-25', cat: cat['Ropa']));
      expect(() => r.eliminarCategoria(cat['Ropa']!), throwsA(isA<ErrorDatos>()));
      await r.archivarCategoria(cat['Ropa']!);
      expect((await r.categorias()).any((c) => c.nombre == 'Ropa'), isFalse);
      // La plata sigue contando aunque la categoría esté archivada
      expect((await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'))).egresos, 1000);
      final t = await r.totalesPorCategoria(Periodo.de(TipoPeriodo.dia, '2026-11-25'));
      expect(t.single.categoria?.nombre, 'Ropa');
    });

    test('una categoría que nunca se usó sí se puede borrar', () async {
      final c = await r.guardarCategoria(const Categoria(nombre: 'Mascotas', tipo: TipoCategoria.egreso, icono: 'mascota', color: 0xFF795548));
      await r.eliminarCategoria(c.id!);
      expect((await r.categorias(incluirArchivadas: true)).any((x) => x.nombre == 'Mascotas'), isFalse);
    });

    test('editar cambia el valor sin duplicar el movimiento', () async {
      final id = await r.agregarMovimiento(gasto(1000, '2026-11-25'));
      final m = (await r.movimiento(id))!;
      await r.actualizarMovimiento(m.copiar(monto: 2500, tipo: TipoMovimiento.ingreso, descripcion: 'Corregido'));
      final res = await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'));
      expect([res.ingresos, res.egresos, res.cantidad], [2500, 0, 1]);
    });
  });

  group('categorías propias (flexible)', () {
    test('crear, renombrar y evitar duplicados sin importar mayúsculas o espacios', () async {
      final c = await r.guardarCategoria(const Categoria(nombre: '  Uñas   y pelo ', tipo: TipoCategoria.egreso, icono: 'personal', color: 1));
      expect(c.nombre, 'Uñas y pelo');
      expect(() => r.guardarCategoria(const Categoria(nombre: 'uñas Y PELO', tipo: TipoCategoria.egreso, icono: 'x', color: 1)),
          throwsA(isA<ErrorDatos>().having((e) => e.mensaje, 'mensaje', contains('Ya existe'))));
      expect(() => r.guardarCategoria(const Categoria(nombre: '   ', tipo: TipoCategoria.egreso, icono: 'x', color: 1)),
          throwsA(isA<ErrorDatos>()));
    });
  });

  test('sugerencias: lo que más escribe sale primero y trae su categoría', () async {
    for (var i = 0; i < 3; i++) {
      await r.agregarMovimiento(gasto(2000, '2026-11-2$i', cat: cat['Transporte'], desc: 'Bus'));
    }
    await r.agregarMovimiento(gasto(30000, '2026-11-20', cat: cat['Mercado y comida'], desc: 'Banano y tomate'));
    await r.agregarMovimiento(ingreso(30000, '2026-11-20', desc: 'Bono'));
    final s = await r.sugerencias(TipoMovimiento.egreso);
    expect(s.first.descripcion, 'Bus');
    expect(s.first.veces, 3);
    expect(s.first.categoriaId, cat['Transporte']);
    expect(s.map((x) => x.descripcion), isNot(contains('Bono')));
    expect((await r.sugerencias(TipoMovimiento.egreso, prefijo: 'ban')).single.descripcion, 'Banano y tomate');
  });

  test('búsqueda por texto en descripción y nota', () async {
    await r.agregarMovimiento(gasto(1000, '2026-01-01', desc: 'Pan donde Doña Rosa'));
    await r.agregarMovimiento(const Movimiento(tipo: TipoMovimiento.egreso, monto: 5, fecha: '2025-05-05', nota: 'se lo di a rosa'));
    await r.agregarMovimiento(gasto(1000, '2026-01-01', desc: 'Leche'));
    expect((await r.buscar('rosa')).length, 2);
    expect((await r.buscar('LECHE')).length, 1);
  });

  test('propiedad: con 2.000 movimientos al azar, la suma de la base es igual a la suma a mano', () async {
    final azar = Random(42);
    final ids = cat.values.toList();
    var ing = 0, egr = 0;
    final hechos = <int, Movimiento>{};
    for (var i = 0; i < 2000; i++) {
      final monto = 1 + azar.nextInt(azar.nextBool() ? 100000 : 50000000);
      final m = Movimiento(
        tipo: azar.nextBool() ? TipoMovimiento.ingreso : TipoMovimiento.egreso,
        monto: monto,
        categoriaId: azar.nextInt(5) == 0 ? null : ids[azar.nextInt(ids.length)],
        fecha: sumarDias('2026-01-01', azar.nextInt(365)),
      );
      hechos[await r.agregarMovimiento(m)] = m;
    }
    // Borra 200 al azar (a la papelera)
    for (final id in hechos.keys.toList()..shuffle(azar)) {
      if (hechos.length <= 1800) break;
      await r.eliminarMovimiento(id);
      hechos.remove(id);
    }
    for (final m in hechos.values) {
      m.tipo == TipoMovimiento.ingreso ? ing += m.monto : egr += m.monto;
    }
    final anio = await r.resumen(Periodo.de(TipoPeriodo.anio, '2026-06-01'));
    expect([anio.ingresos, anio.egresos, anio.cantidad], [ing, egr, 1800]);

    // La suma de los 12 meses y la de las categorías dan lo mismo que el año
    var sumaMeses = 0;
    for (final p in await r.seriePorMes('2026')) {
      sumaMeses += p.ingresos - p.egresos;
    }
    expect(sumaMeses, anio.balance);
    final porCat = await r.totalesPorCategoria(Periodo.de(TipoPeriodo.anio, '2026-06-01'));
    expect(porCat.fold<int>(0, (s, t) => s + (t.tipo == TipoMovimiento.ingreso ? t.total : -t.total)), anio.balance);
    var sumaDias = 0;
    for (final p in await r.seriePorDia(Periodo.de(TipoPeriodo.anio, '2026-06-01'))) {
      sumaDias += p.ingresos - p.egresos;
    }
    expect(sumaDias, anio.balance);
  });

  test('avisa a las pantallas cuando algo cambia', () async {
    var avisos = 0;
    r.addListener(() => avisos++);
    final id = await r.agregarMovimiento(gasto(1000, '2026-11-25'));
    await r.eliminarMovimiento(id);
    await r.restaurarMovimiento(id);
    expect(avisos, 3);
  });
}
