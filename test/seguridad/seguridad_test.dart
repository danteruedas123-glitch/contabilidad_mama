// PRUEBAS DE SEGURIDAD: PIN y fuerza bruta, llave de la base, inyección SQL,
// datos imposibles escritos directamente en la base (saltándose la app).
import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/seguridad/almacen_seguro.dart';
import 'package:contabilidad_mama/seguridad/cripto.dart';
import 'package:contabilidad_mama/seguridad/llave_bd.dart';
import 'package:contabilidad_mama/seguridad/pin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../ayudantes.dart';

void main() {
  group('PIN', () {
    late AlmacenMemoria almacen;
    late DateTime ahora;
    late ServicioPin pin;

    setUp(() {
      almacen = AlmacenMemoria();
      ahora = DateTime(2026, 11, 25, 10);
      pin = ServicioPin(almacen, iteraciones: 1000, reloj: () => ahora);
    });

    test('rechaza PINs fáciles o mal formados', () {
      for (final malo in ['123', '1234567', 'abcd', '12a4', '0000', '1111', '1234', '4321', '123456', '987654', ' 2580', '']) {
        expect(ServicioPin.validarNuevoPin(malo), isNotNull, reason: malo);
      }
      for (final bueno in ['2580', '7391', '190482', '4455']) {
        expect(ServicioPin.validarNuevoPin(bueno), isNull, reason: bueno);
      }
    });

    test('el PIN nunca se guarda en claro: solo sal + huella PBKDF2', () async {
      await pin.configurarPin('7391');
      final todo = almacen.datos.values.join('|');
      expect(todo, isNot(contains('7391')));
      expect(deB64(almacen.datos[ServicioPin.kHash]!).length, 32);
      expect(deB64(almacen.datos[ServicioPin.kSal]!).length, 16);
    });

    test('dos instalaciones con el mismo PIN tienen huellas distintas (sal aleatoria)', () async {
      final otro = AlmacenMemoria();
      await pin.configurarPin('7391');
      await ServicioPin(otro, iteraciones: 1000).configurarPin('7391');
      expect(almacen.datos[ServicioPin.kHash], isNot(otro.datos[ServicioPin.kHash]));
    });

    test('PIN correcto entra; incorrecto no', () async {
      await pin.configurarPin('7391');
      expect((await pin.verificar('7391')).ok, isTrue);
      final r = await pin.verificar('7392');
      expect(r.ok, isFalse);
      expect(r.intentosRestantes, 4);
    });

    test('entradas raras no rompen nada ni entran', () async {
      await pin.configurarPin('7391');
      for (final raro in ['', ' 7391', '7391 ', '٧٣٩١', "7391' OR '1'='1", '7' * 10000, '7391\u0000']) {
        expect((await pin.verificar(raro)).ok, isFalse, reason: raro.length > 20 ? 'largo' : raro);
        ahora = ahora.add(const Duration(hours: 1)); // salta bloqueos
      }
    });

    test('fuerza bruta: tras 5 fallos bloquea 30 s, luego duplica, máximo 15 min', () async {
      await pin.configurarPin('7391');
      for (var i = 0; i < 4; i++) {
        expect((await pin.verificar('0001')).esperar, isNull);
      }
      expect((await pin.verificar('0001')).esperar, const Duration(seconds: 30));
      // Durante el bloqueo ni siquiera el PIN correcto funciona
      expect((await pin.verificar('7391')).ok, isFalse);
      ahora = ahora.add(const Duration(seconds: 31));
      expect((await pin.verificar('0001')).esperar, const Duration(minutes: 1));
      ahora = ahora.add(const Duration(minutes: 2));
      expect((await pin.verificar('0001')).esperar, const Duration(minutes: 2));
      for (var i = 0; i < 10; i++) {
        ahora = ahora.add(const Duration(hours: 1));
        await pin.verificar('0001');
      }
      expect(await pin.tiempoBloqueo(), const Duration(minutes: 15));
    });

    test('probar los 10.000 PINs de 4 dígitos tomaría más de 3 días', () async {
      // Cálculo con la política real: 4 intentos libres y después cada intento
      // cuesta como mínimo la espera máxima.
      var segundos = 0;
      for (var fallo = 5; fallo <= 10000; fallo++) {
        final s = 30 * (1 << (fallo - 5).clamp(0, 10));
        segundos += s > 900 ? 900 : s;
      }
      expect(Duration(seconds: segundos).inDays, greaterThan(3 * 30)); // ~3 meses
    });

    test('el bloqueo sobrevive a cerrar y abrir la app', () async {
      await pin.configurarPin('7391');
      for (var i = 0; i < 5; i++) {
        await pin.verificar('0001');
      }
      final reabierta = ServicioPin(almacen, iteraciones: 1000, reloj: () => ahora);
      expect(await reabierta.tiempoBloqueo(), isNotNull);
    });

    test('atrasar el reloj del celular no alarga ni salta el bloqueo indefinidamente', () async {
      await pin.configurarPin('7391');
      for (var i = 0; i < 5; i++) {
        await pin.verificar('0001');
      }
      ahora = ahora.subtract(const Duration(days: 365));
      expect(await pin.tiempoBloqueo(), ServicioPin.esperaMaxima);
    });

    test('acertar reinicia el contador', () async {
      await pin.configurarPin('7391');
      for (var i = 0; i < 4; i++) {
        await pin.verificar('0001');
      }
      expect((await pin.verificar('7391')).ok, isTrue);
      expect((await pin.verificar('0001')).intentosRestantes, 4);
    });

    test('código de recuperación: funciona una vez escrito con o sin guiones/minúsculas', () async {
      await pin.configurarPin('7391');
      final codigo = await pin.generarCodigoRecuperacion();
      expect(codigo, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(almacen.datos.values.join(), isNot(contains(codigo.replaceAll('-', ''))));
      expect((await pin.verificarRecuperacion(codigo.toLowerCase().replaceAll('-', ' '))).ok, isTrue);
      expect((await pin.verificarRecuperacion('AAAA-BBBB-CCCC')).ok, isFalse);
      // Al generar uno nuevo, el viejo deja de servir
      final nuevo = await pin.generarCodigoRecuperacion();
      expect((await pin.verificarRecuperacion(codigo)).ok, nuevo == codigo);
    });

    test('el código de recuperación comparte el límite de intentos', () async {
      await pin.configurarPin('7391');
      await pin.generarCodigoRecuperacion();
      for (var i = 0; i < 4; i++) {
        await pin.verificarRecuperacion('XXXX-XXXX-XXXX');
      }
      expect((await pin.verificarRecuperacion('XXXX-XXXX-XXXX')).esperar, isNotNull);
    });

    test('comparación en tiempo constante', () {
      expect(igualesSeguro([1, 2, 3], [1, 2, 3]), isTrue);
      expect(igualesSeguro([1, 2, 3], [1, 2, 4]), isFalse);
      expect(igualesSeguro([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('llave de la base de datos', () {
    test('se crea al azar (256 bits) y luego siempre es la misma', () async {
      final a = AlmacenMemoria();
      final k1 = await obtenerLlaveBD(a, existeBD: false);
      expect(k1, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await obtenerLlaveBD(a, existeBD: true), k1);
      expect(await obtenerLlaveBD(AlmacenMemoria(), existeBD: false), isNot(k1));
    });

    test('si la base existe y la llave no aparece, NUNCA crea una nueva encima', () async {
      expect(() => obtenerLlaveBD(AlmacenMemoria(), existeBD: true), throwsA(isA<LlavePerdida>()));
    });

    test('una llave guardada dañada no se usa', () async {
      final a = AlmacenMemoria()..datos[kLlaveBD] = "' OR 1=1 --";
      expect(() => obtenerLlaveBD(a, existeBD: true), throwsA(isA<LlavePerdida>()));
    });
  });

  group('inyección SQL', () {
    late Repositorio r;
    setUp(() async => r = await repoDePrueba());
    tearDown(() => r.db.close());

    const ataques = [
      "'; DROP TABLE movimientos; --",
      "' OR '1'='1",
      'Robert"); DELETE FROM categorias; --',
      "1; UPDATE movimientos SET monto = 1",
      "x' UNION SELECT clave, valor FROM ajustes --",
    ];

    test('textos maliciosos se guardan como texto y no ejecutan nada', () async {
      for (final a in ataques) {
        await r.agregarMovimiento(Movimiento(tipo: TipoMovimiento.egreso, monto: 1000, fecha: '2026-11-25', descripcion: a, nota: a));
      }
      final movs = await r.movimientos(Periodo.de(TipoPeriodo.dia, '2026-11-25'));
      expect(movs.map((m) => m.descripcion).toSet(), ataques.toSet());
      expect((await r.categorias()).length, greaterThan(10));
      expect((await r.resumen(Periodo.de(TipoPeriodo.dia, '2026-11-25'))).egresos, 5000);
    });

    test('la búsqueda con ataques o comodines no devuelve de más', () async {
      await r.agregarMovimiento(gasto(1000, '2026-11-25', desc: 'Pan'));
      await r.agregarMovimiento(gasto(1000, '2026-11-25', desc: '100% algodón'));
      await r.agregarMovimiento(gasto(1000, '2026-11-25', desc: 'mi_cosa'));
      for (final a in ataques) {
        expect(await r.buscar(a), isEmpty, reason: a);
      }
      expect((await r.buscar('%')).single.descripcion, '100% algodón');
      expect((await r.buscar('_')).single.descripcion, 'mi_cosa');
      expect((await r.buscar(r'\')), isEmpty);
    });

    test('nombre de categoría malicioso', () async {
      final c = await r.guardarCategoria(Categoria(nombre: ataques.first.substring(0, 25), tipo: TipoCategoria.egreso, icono: 'otros', color: 1));
      expect((await r.categorias()).any((x) => x.id == c.id), isTrue);
    });
  });

  group('la base rechaza datos imposibles aunque se salten la app', () {
    late Repositorio r;
    setUp(() async => r = await repoDePrueba());
    tearDown(() => r.db.close());

    Future<void> insertar(Map<String, Object?> cambios) => r.db.insert('movimientos', {
          'tipo': 'egreso', 'monto': 1000, 'fecha': '2026-11-25', 'creado_en': 'x', 'actualizado_en': 'x', ...cambios,
        });

    test('dato válido de control sí entra', () async {
      await insertar({});
      expect(await r.totalMovimientos(), 1);
    });

    test('un monto "1000" escrito como texto queda guardado como ENTERO (afinidad de SQLite)', () async {
      await insertar({'monto': '1000'});
      final f = await r.db.rawQuery('SELECT typeof(monto) AS t, monto FROM movimientos');
      expect(f.single, {'t': 'integer', 'monto': 1000});
    });

    final malos = <String, Map<String, Object?>>{
      'monto negativo': {'monto': -1000},
      'monto cero': {'monto': 0},
      'monto con decimales': {'monto': 1000.5},
      'monto como texto no numérico': {'monto': 'mil'},
      'monto como texto con decimales': {'monto': '1000.5'},
      'monto gigante': {'monto': 100000000001},
      'tipo desconocido': {'tipo': 'robo'},
      'fecha imposible': {'fecha': '2026-02-30'},
      'mes 13': {'fecha': '2026-13-01'},
      'fecha con otro formato': {'fecha': '25/11/2026'},
      'fecha con inyección': {'fecha': "2026-11-25' --"},
      'medio desconocido': {'medio': 'bitcoin'},
      'categoría que no existe': {'categoria_id': 99999},
      'descripción gigante': {'descripcion': 'x' * (maxDescripcion + 1)},
      'nota gigante': {'nota': 'x' * (maxNota + 1)},
    };
    malos.forEach((nombre, cambio) {
      test(nombre, () async {
        await expectLater(insertar(cambio), throwsA(isA<DatabaseException>()));
        expect(await r.totalMovimientos(), 0);
      });
    });

    test('la app también valida antes (mensajes claros)', () async {
      for (final m in [
        gasto(0, '2026-11-25'),
        gasto(-5, '2026-11-25'),
        gasto(1000, '2026-02-30'),
        Movimiento(tipo: TipoMovimiento.egreso, monto: 1, fecha: '2026-11-25', descripcion: 'x' * 500),
      ]) {
        expect(() => r.agregarMovimiento(m), throwsA(isA<ErrorDatos>()));
      }
      expect(() => r.agregarMovimiento(gasto(1000, '2026-11-25', cat: 424242)),
          throwsA(isA<ErrorDatos>().having((e) => e.mensaje, 'm', contains('categoría'))));
    });

    test('no se puede borrar una categoría usada ni por SQL directo', () async {
      final id = (await r.categorias()).first.id!;
      await r.agregarMovimiento(gasto(1000, '2026-11-25', cat: id));
      await expectLater(r.db.delete('categorias', where: 'id = ?', whereArgs: [id]), throwsA(isA<DatabaseException>()));
    });

    test('integridad del archivo', () async {
      expect(await r.integridadOk(), isTrue);
    });
  });
}
