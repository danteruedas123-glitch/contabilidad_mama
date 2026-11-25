// Recorrido con datos de ejemplo para sacar capturas de pantalla:
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/herramientas/capturas.dart -d emulator-5554
import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/abrir_bd.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/main.dart' as app;
import 'package:contabilidad_mama/ui/widgets/grafica.dart';
import 'package:contabilidad_mama/seguridad/almacen_seguro.dart';
import 'package:contabilidad_mama/seguridad/pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../celular_test.dart' show limpiar;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capturas', (tester) async {
    await limpiar();
    final almacen = AlmacenKeystore();
    await ServicioPin(almacen).configurarPin('2580');
    final db = await abrirBDCifrada(almacen);
    final r = Repositorio(db);
    await r.guardarAjuste('proteger_pantalla', '0'); // solo para las capturas
    await r.guardarAjuste('ultima_copia', DateTime.now().toIso8601String());
    final c = {for (final x in await r.categorias()) x.nombre: x.id};
    final h = hoy();
    String d(int n) => sumarDias(h, -n);
    final datos = <(TipoMovimiento, int, String?, String, int, MedioPago?)>[
      (TipoMovimiento.ingreso, 1300000, 'Trabajo', 'Quincena', 10, MedioPago.banco),
      (TipoMovimiento.ingreso, 180000, 'Ventas', 'Venta de tamales', 6, MedioPago.efectivo),
      (TipoMovimiento.ingreso, 250000, 'Juego', 'Ganó el bingo', 3, MedioPago.efectivo),
      (TipoMovimiento.egreso, 40000, 'Juego', 'Chance', 5, MedioPago.efectivo),
      (TipoMovimiento.egreso, 30000, 'Juego', 'Cartones de bingo', 3, MedioPago.efectivo),
      (TipoMovimiento.egreso, 420000, 'Mercado y comida', 'Mercado del mes', 9, MedioPago.tarjeta),
      (TipoMovimiento.egreso, 95000, 'Servicios', 'Recibo de la luz', 7, MedioPago.nequi),
      (TipoMovimiento.egreso, 60000, 'Servicios', 'Recibo del agua', 7, MedioPago.nequi),
      (TipoMovimiento.egreso, 650000, 'Arriendo', 'Arriendo', 8, MedioPago.banco),
      (TipoMovimiento.egreso, 38000, 'Salud', 'Droguería', 2, MedioPago.efectivo),
      (TipoMovimiento.egreso, 25000, 'Gastos personales', 'Peluquería', 1, MedioPago.efectivo),
      (TipoMovimiento.egreso, 45000, 'Gastos por fuera', 'Almuerzo con las amigas', 1, MedioPago.daviplata),
      (TipoMovimiento.egreso, 6000, 'Transporte', 'Bus', 0, MedioPago.efectivo),
      (TipoMovimiento.egreso, 12000, 'Mercado y comida', 'Pan y leche', 0, MedioPago.efectivo),
    ];
    for (final (t, monto, cat, desc, dias, medio) in datos) {
      await r.agregarMovimiento(Movimiento(tipo: t, monto: monto, categoriaId: c[cat], descripcion: desc, fecha: d(dias), medio: medio));
    }
    await db.close();

    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('1-bloqueo');

    for (final n in '2580'.split('')) {
      await tester.tap(find.byKey(ValueKey('tecla-$n')));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const ValueKey('pin-aceptar')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await binding.takeScreenshot('2-inicio-mes');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('3-lista');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -330));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Categorías').last);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('4-categorias');

    await tester.tap(find.text('Gráfica'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(GraficaBarras)) + const Offset(120, 0));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('5-grafica');

    await tester.tap(find.byKey(const ValueKey('nuevo-egreso')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('campo-monto')), '35000');
    await tester.enterText(find.byKey(const ValueKey('campo-descripcion')), 'Mer');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('6-anotar');
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();
    if (find.text('Salir sin guardar').evaluate().isNotEmpty) {
      await tester.tap(find.text('Salir sin guardar'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('abrir-ajustes')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('7-ajustes');
  });
}
