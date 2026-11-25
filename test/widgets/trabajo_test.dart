// PRUEBAS DE INTERFAZ del trabajo: cobrar a un cliente nuevo, cobrarle otra
// vez con un toque, ver lo cobrado y la ficha del cliente.
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show entorno, abrir, bajarHasta, texto;

Future<void> esperar(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  await tester.pumpAndSettle();
}

Future<void> guardar(WidgetTester tester) async {
  await bajarHasta(tester, find.byKey(const ValueKey('guardar')));
  await tester.tap(find.byKey(const ValueKey('guardar')));
  await esperar(tester);
}

void main() {
  testWidgets('cobro a un cliente nuevo desde el inicio: se crea el cliente y cuenta como Trabajo', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await abrir(tester, e);
    expect(texto(tester, 'inicio-trabajo'), 'Anota lo que te pagan tus clientes');

    await tester.tap(find.byKey(const ValueKey('inicio-anotar-cobro')));
    await esperar(tester);
    expect(find.text('Cobro de trabajo'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('campo-monto')), '80000');
    await tester.enterText(find.byKey(const ValueKey('campo-cliente')), 'Doña Rosa');
    await esperar(tester);
    expect(find.text('Cliente nuevo: se guarda solo al guardar'), findsOneWidget);
    await guardar(tester);

    expect(texto(tester, 'inicio-trabajo'), r'Cobraste $80.000 · 1 cliente');
    expect(texto(tester, 'total-ingresos'), r'$80.000');
    // En la lista sale con el nombre del cliente y la categoría Trabajo
    expect(find.text('Doña Rosa'), findsOneWidget);
    expect(find.text('Trabajo'), findsWidgets);

    final datos = await tester.runAsync(() async {
      final c = await e.repo.clientes();
      final m = (await e.repo.buscar('Rosa')).single;
      final cats = await e.repo.categorias();
      return (c, m, cats);
    });
    final (clientes, mov, cats) = datos!;
    expect(clientes.single.nombre, 'Doña Rosa');
    expect(mov.clienteId, clientes.single.id);
    expect(cats.firstWhere((c) => c.id == mov.categoriaId).nombre, 'Trabajo');
  });

  testWidgets('cobrarle otra vez es un toque: el cliente aparece de sugerencia y no se duplica', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await tester.runAsync(() async {
      final c = await e.repo.clienteParaNombre('Doña Rosa');
      await e.repo.agregarMovimiento(Movimiento(tipo: TipoMovimiento.ingreso, monto: 50000, fecha: '2026-11-20', clienteId: c.id));
    });
    await abrir(tester, e);
    await tester.tap(find.byKey(const ValueKey('nuevo-ingreso')));
    await esperar(tester);
    await tester.enterText(find.byKey(const ValueKey('campo-monto')), '30 mil');
    await tester.tap(find.byKey(const ValueKey('cliente-Doña Rosa')));
    await esperar(tester);
    expect(find.text('Cliente nuevo: se guarda solo al guardar'), findsNothing);
    await guardar(tester);

    final r = await tester.runAsync(() async => (await e.repo.clientes(), await e.repo.historialCliente((await e.repo.clientes()).single.id!)));
    expect(r!.$1.length, 1);
    expect([r.$2.total, r.$2.cobros], [80000, 2]);
  });

  testWidgets('pantalla Trabajo: lo cobrado, quién pagó y la ficha del cliente', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await tester.runAsync(() async {
      final rosa = await e.repo.clienteParaNombre('Doña Rosa');
      final pedro = await e.repo.clienteParaNombre('Pedro');
      for (final (c, v, f) in [(rosa, 80000, '2026-11-05'), (rosa, 45000, '2026-11-20'), (pedro, 150000, '2026-11-10'), (rosa, 10000, '2026-10-01')]) {
        await e.repo.agregarMovimiento(Movimiento(tipo: TipoMovimiento.ingreso, monto: v, fecha: f, clienteId: c.id));
      }
    });
    await abrir(tester, e);
    await tester.tap(find.byKey(const ValueKey('abrir-trabajo')));
    await esperar(tester);

    expect(texto(tester, 'trabajo-periodo'), 'Noviembre 2026');
    expect(texto(tester, 'trabajo-cobrado'), r'$275.000');
    expect(texto(tester, 'trabajo-detalle'), '3 cobros · 2 clientes');
    // Pedro pagó más este mes: sale primero
    final yPedro = tester.getTopLeft(find.byKey(const ValueKey('total-cliente-Pedro'))).dy;
    final yRosa = tester.getTopLeft(find.byKey(const ValueKey('total-cliente-Doña Rosa'))).dy;
    expect(yPedro, lessThan(yRosa));

    await tester.tap(find.byKey(const ValueKey('total-cliente-Doña Rosa')));
    await esperar(tester);
    expect(texto(tester, 'cliente-total'), r'$135.000'); // toda la historia
    expect(texto(tester, 'cliente-mes'), r'$125.000');

    // Cobrarle desde su ficha: ya viene con su nombre
    await tester.tap(find.byKey(const ValueKey('cobrar-a-cliente')));
    await esperar(tester);
    expect(find.widgetWithText(TextField, 'Doña Rosa'), findsOneWidget);
  });

  testWidgets('mis clientes: agregar uno a mano con teléfono', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await abrir(tester, e);
    await tester.tap(find.byKey(const ValueKey('abrir-trabajo')));
    await esperar(tester);
    await tester.tap(find.byKey(const ValueKey('abrir-clientes')));
    await esperar(tester);
    expect(find.textContaining('Todavía no tienes clientes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nuevo-cliente')));
    await esperar(tester);
    await tester.enterText(find.byKey(const ValueKey('nombre-cliente')), 'Lucía');
    await tester.enterText(find.byKey(const ValueKey('telefono-cliente')), '300 abc 123');
    await tester.tap(find.byKey(const ValueKey('guardar-cliente')));
    await esperar(tester);
    final c = (await tester.runAsync(() => e.repo.clientes()))!.single;
    expect([c.nombre, c.telefono], ['Lucía', '300  123']); // las letras ni se dejan escribir
    expect(find.text('Lucía'), findsOneWidget);
  });
}
