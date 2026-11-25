// PRUEBAS DE INTERFAZ: los flujos que mamá va a hacer, de punta a punta.
import 'package:contabilidad_mama/app.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/respaldo/respaldo.dart';
import 'package:contabilidad_mama/seguridad/almacen_seguro.dart';
import 'package:contabilidad_mama/seguridad/cripto.dart';
import 'package:contabilidad_mama/seguridad/pin.dart';
import 'package:contabilidad_mama/servicios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ayudantes.dart';

const hoyPrueba = '2026-11-25';

class Entorno {
  final Repositorio repo;
  final ServicioPin pin;
  final Servicios servicios;
  Entorno(this.repo, this.pin, this.servicios);
}

Future<Entorno> entorno(WidgetTester tester, {String? pinInicial, bool bloqueado = false}) async {
  late Entorno e;
  await tester.runAsync(() async {
    final repo = await repoDePrueba(sinIsolate: true);
    final pin = ServicioPin(AlmacenMemoria(), iteraciones: 1000, derivar: derivarClaveDirecto);
    if (pinInicial != null) await pin.configurarPin(pinInicial);
    e = Entorno(
      repo,
      pin,
      Servicios(
        repo: repo,
        pin: pin,
        respaldo: ServicioRespaldo(repo, iteraciones: iteracionesMin),
        automaticas: null,
        biometria: SinBiometria(),
        pantalla: ProteccionPantalla(),
        bloqueo: ControlBloqueo(bloqueado: bloqueado),
        hoy: () => hoyPrueba,
      ),
    );
  });
  return e;
}

Future<void> abrir(WidgetTester tester, Entorno e, {bool tienePin = true}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppMisCuentas(servicios: e.servicios, tienePin: tienePin));
  await tester.pumpAndSettle();
}

Future<void> teclearPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('tecla-$d')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('pin-aceptar')));
  await tester.pumpAndSettle();
}

/// Baja en el formulario hasta que [f] se vea (la lista solo construye lo visible).
Future<void> bajarHasta(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250,
      scrollable: find.descendant(of: find.byKey(const ValueKey('form-movimiento')), matching: find.byType(Scrollable)).first);
  await tester.pumpAndSettle();
}

String texto(WidgetTester tester, String clave) => (tester.widget(find.byKey(ValueKey(clave))) as Text).data!;

void main() {
  testWidgets('primer uso: bienvenida → PIN (rechaza uno fácil) → código de recuperación → inicio', (tester) async {
    final e = await entorno(tester);
    await abrir(tester, e, tienePin: false);
    expect(find.text('Mis Cuentas'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empezar')));
    await tester.pumpAndSettle();

    await teclearPin(tester, '1234');
    expect(texto(tester, 'pin-error'), contains('fácil'));
    await teclearPin(tester, '2580');
    expect(find.text('Escríbelo otra vez para confirmar'), findsOneWidget);
    await teclearPin(tester, '2580');

    expect(find.byKey(const ValueKey('codigo-recuperacion')), findsOneWidget);
    // No deja seguir sin marcar que lo anotó
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('codigo-continuar'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('ya-lo-anote')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('codigo-continuar')));
    await tester.pumpAndSettle();

    expect(find.text('Te quedó'), findsOneWidget);
    expect(await tester.runAsync(() => e.pin.tienePin()), isTrue);
  });

  testWidgets('anotar un gasto con categoría y verlo en el resumen del mes', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await abrir(tester, e);
    expect(texto(tester, 'etiqueta-periodo'), 'Noviembre 2026');

    await tester.tap(find.byKey(const ValueKey('nuevo-egreso')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('campo-monto')), '25000');
    await tester.pump();
    // Pone los puntos de miles solo
    expect(find.text('25.000'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('campo-descripcion')), 'Mercado de la semana');
    await bajarHasta(tester, find.byKey(const ValueKey('cat-Mercado y comida')));
    await tester.tap(find.byKey(const ValueKey('cat-Mercado y comida')));
    await tester.pump();
    await bajarHasta(tester, find.byKey(const ValueKey('guardar')));
    await tester.tap(find.byKey(const ValueKey('guardar')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(texto(tester, 'total-egresos'), r'$25.000');
    expect(texto(tester, 'balance'), r'-$25.000');
    expect(find.text('Gastaste de más'), findsOneWidget);
    expect(find.text('Mercado de la semana'), findsOneWidget);
  });

  testWidgets('el valor se puede escribir con palabras: "1 millón 200 mil"', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await abrir(tester, e);
    await tester.tap(find.byKey(const ValueKey('nuevo-ingreso')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('campo-monto')), '1 millón 200 mil');
    await tester.pump();
    expect(find.text(r'= $1.200.000'), findsOneWidget);
    await bajarHasta(tester, find.byKey(const ValueKey('cat-Trabajo')));
    await tester.tap(find.byKey(const ValueKey('cat-Trabajo')));
    await bajarHasta(tester, find.byKey(const ValueKey('guardar')));
    await tester.tap(find.byKey(const ValueKey('guardar')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(texto(tester, 'total-ingresos'), r'$1.200.000');
  });

  testWidgets('valor inválido: no guarda y explica por qué', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await abrir(tester, e);
    await tester.tap(find.byKey(const ValueKey('nuevo-egreso')));
    await tester.pumpAndSettle();
    await bajarHasta(tester, find.byKey(const ValueKey('guardar')));
    await tester.tap(find.byKey(const ValueKey('guardar')));
    await tester.pumpAndSettle();
    expect(find.text('Escribe cuánto fue'), findsNWidgets(2)); // en el campo y en el aviso de abajo
    expect(await tester.runAsync(() => e.repo.totalMovimientos()), 0);
  });

  testWidgets('juego: muestra lo ganado, lo jugado y si va ganando', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await tester.runAsync(() async {
      final c = await idsCategorias(e.repo);
      await e.repo.agregarMovimiento(ingreso(300000, '2026-11-20', cat: c['Juego'], desc: 'Bingo'));
      await e.repo.agregarMovimiento(gasto(50000, '2026-11-21', cat: c['Juego'], desc: 'Chance'));
    });
    await abrir(tester, e);
    expect(texto(tester, 'juego-neto'), r'$250.000');
    expect(find.text('Va ganando'), findsOneWidget);
  });

  testWidgets('día / semana / mes / año y navegar entre períodos', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await tester.runAsync(() async {
      await e.repo.agregarMovimiento(gasto(10000, '2026-11-25'));
      await e.repo.agregarMovimiento(gasto(20000, '2026-11-10'));
      await e.repo.agregarMovimiento(gasto(40000, '2026-10-05'));
    });
    await abrir(tester, e);
    expect(texto(tester, 'total-egresos'), r'$30.000');

    await tester.tap(find.text('Día'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(texto(tester, 'etiqueta-periodo'), 'Hoy');
    expect(texto(tester, 'total-egresos'), r'$10.000');

    await tester.tap(find.text('Año'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(texto(tester, 'total-egresos'), r'$70.000');

    await tester.tap(find.text('Mes'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('periodo-anterior')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(texto(tester, 'etiqueta-periodo'), 'Octubre 2026');
    expect(texto(tester, 'total-egresos'), r'$40.000');
    expect(find.text('Volver a hoy'), findsOneWidget);
  });

  testWidgets('editar y mandar a la papelera, con "Deshacer"', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    late int id;
    await tester.runAsync(() async => id = await e.repo.agregarMovimiento(gasto(15000, hoyPrueba, desc: 'Pasajes')));
    await abrir(tester, e);
    await tester.tap(find.text('Pasajes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Enviar a la papelera'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar a la papelera'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(texto(tester, 'total-egresos'), r'$0');
    expect(find.text('Enviado a la papelera'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(texto(tester, 'total-egresos'), r'$15.000');
    expect((await tester.runAsync(() => e.repo.movimiento(id)))!.eliminadoEn, isNull);
  });

  testWidgets('salir sin guardar pide confirmación (no se pierde lo escrito)', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await abrir(tester, e);
    await tester.tap(find.byKey(const ValueKey('nuevo-egreso')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('campo-monto')), '9000');
    await tester.pump();
    // Botón "atrás" de Android
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('¿Salir sin guardar?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('9.000'), findsOneWidget);
  });

  group('bloqueo', () {
    testWidgets('pide el PIN; uno malo no entra, el bueno sí', (tester) async {
      final e = await entorno(tester, pinInicial: '2580', bloqueado: true);
      await abrir(tester, e);
      expect(find.text('Escribe tu PIN'), findsOneWidget);
      expect(find.text('Te quedó'), findsNothing); // las cuentas no se ven

      await teclearPin(tester, '1111');
      expect(texto(tester, 'pin-mensaje'), contains('PIN incorrecto'));
      expect(find.text('Escribe tu PIN'), findsOneWidget);

      await teclearPin(tester, '2580');
      expect(find.text('Escribe tu PIN'), findsNothing);
      expect(find.text('Te quedó'), findsOneWidget);
    });

    testWidgets('5 intentos malos bloquean el teclado', (tester) async {
      final e = await entorno(tester, pinInicial: '2580', bloqueado: true);
      await abrir(tester, e);
      for (var i = 0; i < 5; i++) {
        await teclearPin(tester, '1111');
      }
      expect(texto(tester, 'pin-mensaje'), contains('Espera'));
      final teclado = tester.widget<FilledButton>(find.byKey(const ValueKey('pin-aceptar')));
      expect(teclado.onPressed, isNull);
    });

    test('al salir de la app más de 1 minuto se bloquea; menos, no', () {
      var ahora = DateTime(2026, 11, 25, 10);
      final b = ControlBloqueo(bloqueado: false, reloj: () => ahora);
      b.alSalir();
      ahora = ahora.add(const Duration(seconds: 30));
      b.alVolver();
      expect(b.bloqueado, isFalse);
      b.alSalir();
      ahora = ahora.add(const Duration(minutes: 2));
      b.alVolver();
      expect(b.bloqueado, isTrue);
    });

    test('mientras se comparte o se elige un archivo no se bloquea', () async {
      var ahora = DateTime(2026, 11, 25, 10);
      final b = ControlBloqueo(bloqueado: false, reloj: () => ahora);
      await b.sinBloquearMientras(() async {
        b.alSalir();
        ahora = ahora.add(const Duration(minutes: 5));
        b.alVolver();
      });
      expect(b.bloqueado, isFalse);
    });
  });

  testWidgets('categoría nueva desde la pantalla de anotar', (tester) async {
    final e = await entorno(tester, pinInicial: '2580');
    await abrir(tester, e);
    await tester.tap(find.byKey(const ValueKey('nuevo-egreso')));
    await tester.pumpAndSettle();
    await bajarHasta(tester, find.text('Nueva categoría'));
    await tester.tap(find.text('Nueva categoría'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('nombre-categoria')), 'Mascotas');
    await tester.ensureVisible(find.byKey(const ValueKey('guardar-categoria')));
    await tester.tap(find.byKey(const ValueKey('guardar-categoria')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final cats = await tester.runAsync(() => e.repo.categorias());
    expect(cats!.any((c) => c.nombre == 'Mascotas' && c.tipo == TipoCategoria.egreso), isTrue);
    expect(find.byKey(const ValueKey('cat-Mascotas')), findsOneWidget);
  });
}
