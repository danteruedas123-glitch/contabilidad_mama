// PRUEBAS DE SEGURIDAD de clientes: datos imposibles en la base, inyección,
// copias de seguridad viejas (v1) y manipuladas, y Excel.
import 'dart:convert';

import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/respaldo/csv.dart';
import 'package:contabilidad_mama/respaldo/respaldo.dart';
import 'package:contabilidad_mama/seguridad/cripto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../ayudantes.dart';

const clave = 'clave-de-mama';

/// Cifra un contenido arbitrario como lo haría la app (para simular copias
/// viejas o manipuladas por alguien que conoce la contraseña).
Future<List<int>> cifrar(Map<String, dynamic> interno, {int version = 2}) async {
  final sal = bytesAleatorios(16);
  final llave = await derivarClave(clave, sal, iteracionesMin);
  final c = await cifrarAes(llave, utf8.encode(jsonEncode(interno)));
  return utf8.encode(jsonEncode({
    'formato': formatoRespaldo, 'version': version, 'cifrado': 'aes-256-gcm',
    'kdf': {'algoritmo': 'pbkdf2-sha256', 'iteraciones': iteracionesMin, 'sal': b64(sal)},
    'nonce': b64(c.nonce), 'datos': b64(c.cifrado),
  }));
}

void main() {
  late Repositorio r;
  late int rosa;
  setUp(() async {
    r = await repoDePrueba();
    rosa = (await r.clienteParaNombre('Doña Rosa')).id!;
    await r.agregarMovimiento(Movimiento(tipo: TipoMovimiento.ingreso, monto: 80000, fecha: '2026-11-05', clienteId: rosa, descripcion: 'Arreglo'));
    await r.agregarMovimiento(gasto(20000, '2026-11-06', desc: 'Hilo'));
  });
  tearDown(() => r.db.close());

  group('la base rechaza clientes imposibles aunque se salten la app', () {
    Future<void> insertar(Map<String, Object?> c) =>
        r.db.insert('clientes', {'nombre': 'X', 'clave': 'x', 'creado_en': 'hoy', ...c});
    final malos = <String, Map<String, Object?>>{
      'nombre vacío': {'nombre': '   ', 'clave': 'vacio'},
      'nombre gigante': {'nombre': 'x' * (maxNombreCliente + 1), 'clave': 'gigante'},
      'clave repetida (mismo cliente)': {'nombre': 'DOÑA ROSA', 'clave': 'dona rosa'},
      'clave vacía': {'nombre': 'Ana', 'clave': ''},
      'teléfono gigante': {'nombre': 'Ana', 'clave': 'ana', 'telefono': '1' * (maxTelefono + 1)},
      'archivado raro': {'nombre': 'Ana', 'clave': 'ana', 'archivado': 5},
    };
    malos.forEach((n, c) {
      test(n, () async {
        await expectLater(insertar(c), throwsA(isA<DatabaseException>()));
      });
    });

    test('no se puede borrar un cliente con cobros ni por SQL directo', () async {
      await expectLater(r.db.delete('clientes', where: 'id = ?', whereArgs: [rosa]), throwsA(isA<DatabaseException>()));
    });
  });

  test('nombres de cliente maliciosos se guardan como texto y la búsqueda no se rompe', () async {
    const ataques = ["'; DROP TABLE clientes; --", "x' OR '1'='1", '%', '_', r'\'];
    for (final a in ataques) {
      final c = await r.clienteParaNombre(a);
      await r.agregarMovimiento(Movimiento(tipo: TipoMovimiento.ingreso, monto: 1, fecha: '2026-11-07', clienteId: c.id));
    }
    expect((await r.clientes()).length, ataques.length + 1);
    expect((await r.buscar('%')).single.monto, 1);
    expect((await r.clientesRecientes(prefijo: '_')).single.nombre, '_');
    expect((await r.resumenTrabajo(Periodo.de(TipoPeriodo.mes, '2026-11-01'))).cobrado, 80000 + ataques.length);
  });

  group('copias de seguridad con clientes', () {
    test('ida y vuelta: los clientes y a quién se le cobró se conservan', () async {
      final archivo = await ServicioRespaldo(r, iteraciones: iteracionesMin).crear(clave);
      final otro = await repoDePrueba();
      await ServicioRespaldo(otro).restaurar(archivo, clave);
      final c = (await otro.clientes()).single;
      expect(c.nombre, 'Doña Rosa');
      final t = await otro.totalesPorCliente(Periodo.de(TipoPeriodo.mes, '2026-11-01'));
      expect([t.single.cliente.nombre, t.single.total], ['Doña Rosa', 80000]);
      // Y se puede seguir usando: escribir "doña rosa" encuentra al mismo cliente
      expect((await otro.clienteParaNombre('doña rosa')).id, c.id);
      await otro.db.close();
    });

    test('una copia VIEJA (v1, sin clientes) se sigue pudiendo restaurar', () async {
      final interno = {
        'version': 1, 'esquema': 1, 'creado': '2026-11-01T00:00:00Z',
        'categorias': await r.db.query('categorias'),
        'movimientos': [
          {'id': 1, 'tipo': 'ingreso', 'monto': 500000, 'categoria_id': null, 'descripcion': 'Quincena', 'nota': '',
            'medio': null, 'fecha': '2026-10-15', 'creado_en': '2026-10-15T00:00:00Z', 'actualizado_en': '2026-10-15T00:00:00Z', 'eliminado_en': null},
        ],
        'control': {'ingresos': 500000, 'egresos': 0, 'cantidad': 1},
      };
      final res = await ServicioRespaldo(r).restaurar(await cifrar(interno, version: 1), clave);
      expect(res.movimientos, 1);
      expect(await r.clientes(), isEmpty);
      expect(await r.saldoHasta('2030-01-01'), 500000);
    });

    Future<Map<String, dynamic>> contenido() async {
      final archivo = await ServicioRespaldo(r, iteraciones: iteracionesMin).crear(clave);
      return jsonDecode(jsonEncode((await ServicioRespaldo(r).leer(archivo, clave)).datos)) as Map<String, dynamic>;
    }

    final manipulaciones = <String, void Function(Map<String, dynamic>)>{
      'cobro a un cliente que no existe': (d) => ((d['movimientos'] as List).first as Map)['cliente_id'] = 999,
      'dos clientes con el mismo id': (d) => d['clientes'] = [...d['clientes'] as List, (d['clientes'] as List).first],
      'dos clientes que son el mismo (DOÑA ROSA / doña rosa)': (d) =>
          d['clientes'] = [...d['clientes'] as List, {...(d['clientes'] as List).first as Map, 'id': 77, 'nombre': 'DOÑA ROSA'}],
      'cliente sin nombre': (d) => ((d['clientes'] as List).first as Map)['nombre'] = '   ',
      'teléfono con letras': (d) => ((d['clientes'] as List).first as Map)['telefono'] = 'llámame',
      'clientes no es lista': (d) => d['clientes'] = 'muchos',
      'cliente con fecha inválida': (d) => ((d['clientes'] as List).first as Map)['creado_en'] = 'ayer',
    };
    manipulaciones.forEach((nombre, cambiar) {
      test('manipulada: $nombre → no se restaura nada', () async {
        final d = await contenido();
        cambiar(d);
        final destino = await repoDePrueba();
        await destino.agregarMovimiento(gasto(777, '2020-01-01'));
        await expectLater(ServicioRespaldo(destino).restaurar(await cifrar(d), clave), throwsA(isA<ErrorRespaldo>()));
        expect(await destino.saldoHasta('2030-01-01'), -777);
        expect(await destino.clientes(), isEmpty);
        await destino.db.close();
      });
    });

    test('una clave falsa dentro del archivo se ignora y se recalcula', () async {
      final d = await contenido();
      ((d['clientes'] as List).first as Map)['clave'] = 'otra cosa';
      await ServicioRespaldo(r).restaurar(await cifrar(d), clave);
      expect((await r.clienteParaNombre('Doña Rosa')).id, rosa);
      expect((await r.clientes()).length, 1);
    });
  });

  test('Excel: columna Cliente con fórmulas neutralizadas', () async {
    final malo = await r.clienteParaNombre('=HYPERLINK("http://x")');
    await r.agregarMovimiento(Movimiento(tipo: TipoMovimiento.ingreso, monto: 5, fecha: '2026-11-08', clienteId: malo.id));
    final movs = await r.movimientos(Periodo.de(TipoPeriodo.mes, '2026-11-01'));
    final cats = {for (final c in await r.categorias(incluirArchivadas: true)) c.id!: c};
    final clientes = {for (final c in await r.clientes(incluirArchivados: true)) c.id!: c};
    final texto = utf8.decode(generarCsv(movs, cats, clientes: clientes));
    expect(texto, contains(';Doña Rosa;Arreglo;'));
    expect(texto, contains('"\'=HYPERLINK(""http://x"")"'));
  });
}
