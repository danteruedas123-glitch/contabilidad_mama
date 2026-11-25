// Trabajo y clientes: que cada cobro quede con su cliente, que los totales
// cuadren y que actualizar desde la 1.0.0 no toque ni un dato.
import 'dart:io';

import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/base_datos.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../ayudantes.dart';

Movimiento cobro(int monto, String fecha, int clienteId, {int? cat, String desc = ''}) => Movimiento(
    tipo: TipoMovimiento.ingreso, monto: monto, fecha: fecha, clienteId: clienteId, categoriaId: cat, descripcion: desc);

void main() {
  group('actualizar desde la versión 1.0.0', () {
    late Directory dir;
    setUp(() {
      sqfliteFfiInit();
      dir = Directory.systemTemp.createTempSync('migracion-');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('la migración a v2 conserva TODOS los datos y agrega clientes', () async {
      final ruta = p.join(dir.path, 'contabilidad.db');
      // 1) Un celular con la app 1.0.0 (esquema v1) y datos de mamá
      final v1 = await databaseFactoryFfi.openDatabase(ruta,
          options: OpenDatabaseOptions(version: 1, onConfigure: configurarBD, onCreate: (db, _) => crearEsquemaV1(db), singleInstance: false));
      final r1 = Repositorio(v1);
      final c = await idsCategorias(r1);
      // Repositorio v1 no conoce cliente_id: se inserta como lo hacía la 1.0.0
      Future<void> viejo(String tipo, int monto, String fecha, int? cat, String desc) => v1.insert('movimientos', {
            'tipo': tipo, 'monto': monto, 'fecha': fecha, 'categoria_id': cat, 'descripcion': desc,
            'creado_en': '2026-11-01T10:00:00Z', 'actualizado_en': '2026-11-01T10:00:00Z',
          });
      await viejo('ingreso', 1300000, '2026-11-01', c['Trabajo'], 'Quincena');
      await viejo('egreso', 420000, '2026-11-02', c['Mercado y comida'], 'Mercado');
      await viejo('ingreso', 250000, '2026-11-03', c['Juego'], 'Bingo');
      await v1.insert('ajustes', {'clave': 'proteger_pantalla', 'valor': '0'});
      await v1.update('movimientos', {'eliminado_en': '2026-11-04T00:00:00Z'}, where: "descripcion = 'Bingo'");
      final antes = await v1.rawQuery('SELECT * FROM movimientos ORDER BY id');
      final catsAntes = await v1.rawQuery('SELECT * FROM categorias ORDER BY id');
      await v1.close();

      // 2) Llega la 1.1.0 y abre la misma base
      final v2 = await databaseFactoryFfi.openDatabase(ruta, options: OpenDatabaseOptions(
        version: versionEsquema, onConfigure: configurarBD, onCreate: crearBD, onUpgrade: actualizarBD, singleInstance: false));
      expect(await v2.getVersion(), 2);
      final despues = await v2.rawQuery('SELECT * FROM movimientos ORDER BY id');
      expect(despues.length, antes.length);
      for (var i = 0; i < antes.length; i++) {
        expect({...despues[i]}..remove('cliente_id'), antes[i], reason: 'movimiento ${antes[i]['id']} cambió');
        expect(despues[i]['cliente_id'], isNull);
      }
      expect(await v2.rawQuery('SELECT * FROM categorias ORDER BY id'), catsAntes);
      expect((await v2.query('ajustes')).single['valor'], '0');

      // 3) Y ya se pueden anotar cobros con cliente
      final r2 = Repositorio(v2);
      expect((await r2.resumen(Periodo.de(TipoPeriodo.mes, '2026-11-01'))).balance, 1300000 - 420000);
      final rosa = await r2.clienteParaNombre('Doña Rosa');
      await r2.agregarMovimiento(cobro(80000, '2026-11-05', rosa.id!));
      expect((await r2.resumenTrabajo(Periodo.de(TipoPeriodo.mes, '2026-11-01'))).cobrado, 80000);
      expect(await r2.integridadOk(), isTrue);
      final fk = await v2.rawQuery('PRAGMA foreign_key_check');
      expect(fk, isEmpty);
      await v2.close();
    });

    test('una instalación nueva queda con el mismo esquema que una actualizada', () async {
      Future<List<Map<String, Object?>>> esquema(Database db) =>
          db.rawQuery("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name");
      final nueva = await databaseFactoryFfi.openDatabase(p.join(dir.path, 'nueva.db'), options: opcionesBD());
      final rutaVieja = p.join(dir.path, 'vieja.db');
      final vieja1 = await databaseFactoryFfi.openDatabase(rutaVieja,
          options: OpenDatabaseOptions(version: 1, onConfigure: configurarBD, onCreate: (db, _) => crearEsquemaV1(db), singleInstance: false));
      await vieja1.close();
      final vieja = await databaseFactoryFfi.openDatabase(rutaVieja, options: OpenDatabaseOptions(
          version: versionEsquema, onConfigure: configurarBD, onCreate: crearBD, onUpgrade: actualizarBD, singleInstance: false));
      expect(await esquema(vieja), await esquema(nueva));
      await nueva.close();
      await vieja.close();
    });
  });

  group('clientes', () {
    late Repositorio r;
    late Map<String, int> cat;
    setUp(() async {
      r = await repoDePrueba();
      cat = await idsCategorias(r);
    });
    tearDown(() => r.db.close());

    test('escribir el nombre crea el cliente una sola vez (sin importar mayúsculas ni espacios)', () async {
      final a = await r.clienteParaNombre('  doña   Rosa ');
      final b = await r.clienteParaNombre('DOÑA ROSA');
      final c = await r.clienteParaNombre('Doña Rosa');
      expect(a.nombre, 'doña Rosa');
      final d = await r.clienteParaNombre('Dona rosa'); // sin la ñ
      expect({a.id, b.id, c.id, d.id}.length, 1);
      final maria = await r.clienteParaNombre('María José');
      expect((await r.clienteParaNombre('maria jose')).id, maria.id);
      expect((await r.clientesRecientes(prefijo: 'MARIA')).single.id, maria.id);
      expect((await r.clientes()).length, 2);
    });

    test('nombres repetidos al crear a mano dan un mensaje claro', () async {
      await r.guardarCliente(const Cliente(nombre: 'Pedro'));
      expect(() => r.guardarCliente(const Cliente(nombre: ' pedro ')),
          throwsA(isA<ErrorDatos>().having((e) => e.mensaje, 'm', contains('Ya tienes un cliente'))));
    });

    test('validaciones: nombre vacío, largo, teléfono con letras', () async {
      for (final malo in [
        const Cliente(nombre: '   '),
        Cliente(nombre: 'x' * (maxNombreCliente + 1)),
        const Cliente(nombre: 'Ana', telefono: '300abc'),
        Cliente(nombre: 'Ana', telefono: '3' * (maxTelefono + 1)),
        Cliente(nombre: 'Ana', nota: 'x' * (maxNotaCliente + 1)),
      ]) {
        expect(() => r.guardarCliente(malo), throwsA(isA<ErrorDatos>()), reason: malo.nombre);
      }
      final ok = await r.guardarCliente(const Cliente(nombre: 'Ana', telefono: '+57 300 123-4567', nota: 'Paga los viernes'));
      expect(ok.telefono, '+57 300 123-4567');
    });

    test('totales por cliente, resumen del trabajo e historial cuadran al peso', () async {
      final rosa = (await r.clienteParaNombre('Doña Rosa')).id!;
      final pedro = (await r.clienteParaNombre('Pedro')).id!;
      await r.agregarMovimiento(cobro(80000, '2026-11-05', rosa, cat: cat['Trabajo']));
      await r.agregarMovimiento(cobro(45000, '2026-11-20', rosa, cat: cat['Trabajo']));
      await r.agregarMovimiento(cobro(150000, '2026-11-10', pedro, cat: cat['Trabajo']));
      await r.agregarMovimiento(cobro(30000, '2026-10-28', rosa)); // otro mes
      await r.agregarMovimiento(ingreso(999, '2026-11-11')); // sin cliente: no es cobro
      final borrar = await r.agregarMovimiento(cobro(7000, '2026-11-12', pedro));
      await r.eliminarMovimiento(borrar); // en papelera: no cuenta

      final mes = Periodo.de(TipoPeriodo.mes, '2026-11-15');
      final w = await r.resumenTrabajo(mes);
      expect([w.cobrado, w.cobros, w.clientes], [275000, 3, 2]);
      final t = await r.totalesPorCliente(mes);
      expect(t.map((x) => (x.cliente.nombre, x.total, x.cobros, x.ultimaFecha)).toList(), [
        ('Pedro', 150000, 1, '2026-11-10'),
        ('Doña Rosa', 125000, 2, '2026-11-20'),
      ]);
      final h = await r.historialCliente(rosa);
      expect([h.total, h.cobros, h.primera, h.ultima], [155000, 3, '2026-10-28', '2026-11-20']);
      // El cobro también cuenta en el resumen general
      expect((await r.resumen(mes)).ingresos, 275000 + 999);
    });

    test('filtrar movimientos por cliente y buscar por su nombre', () async {
      final rosa = (await r.clienteParaNombre('Doña Rosa')).id!;
      final pedro = (await r.clienteParaNombre('Pedro Pérez')).id!;
      await r.agregarMovimiento(cobro(1000, '2026-11-05', rosa, desc: 'Arreglo de vestido'));
      await r.agregarMovimiento(cobro(2000, '2026-11-06', pedro));
      final todo = Periodo.rango('2000-01-01', '2200-12-31');
      expect((await r.movimientos(todo, clienteId: rosa)).single.descripcion, 'Arreglo de vestido');
      expect((await r.buscar('pérez')).single.monto, 2000);
      expect((await r.buscar('Rosa')).single.monto, 1000);
    });

    test('sugerencias de clientes: el que pagó más recientemente sale primero', () async {
      final a = (await r.clienteParaNombre('Ana')).id!;
      final b = (await r.clienteParaNombre('Beatriz')).id!;
      await r.clienteParaNombre('Carlos'); // nunca ha pagado: va de último
      await r.agregarMovimiento(cobro(1000, '2026-11-01', a));
      await r.agregarMovimiento(cobro(1000, '2026-11-02', b));
      expect((await r.clientesRecientes()).map((c) => c.nombre).toList(), ['Beatriz', 'Ana', 'Carlos']);
      expect((await r.clientesRecientes(prefijo: 'atr')).single.nombre, 'Beatriz');
      expect(await r.clientesRecientes(prefijo: '%'), isEmpty);
    });

    test('un cliente con cobros no se borra, se archiva; volver a escribirlo lo reactiva', () async {
      final rosa = await r.clienteParaNombre('Rosa');
      await r.agregarMovimiento(cobro(1000, '2026-11-05', rosa.id!));
      expect(() => r.eliminarCliente(rosa.id!), throwsA(isA<ErrorDatos>()));
      await r.archivarCliente(rosa.id!);
      expect(await r.clientes(), isEmpty);
      expect(await r.clientesRecientes(), isEmpty);
      // El cobro sigue contando
      expect((await r.resumenTrabajo(Periodo.de(TipoPeriodo.mes, '2026-11-05'))).cobrado, 1000);
      final otraVez = await r.clienteParaNombre('rosa');
      expect(otraVez.id, rosa.id);
      expect(otraVez.archivado, isFalse);
    });

    test('un cliente sin cobros sí se puede borrar', () async {
      final x = await r.clienteParaNombre('Equivocado');
      await r.eliminarCliente(x.id!);
      expect(await r.cliente(x.id!), isNull);
    });

    test('editar el movimiento puede cambiar o quitar el cliente', () async {
      final a = (await r.clienteParaNombre('Ana')).id!;
      final b = (await r.clienteParaNombre('Beto')).id!;
      final id = await r.agregarMovimiento(cobro(5000, '2026-11-05', a));
      await r.actualizarMovimiento((await r.movimiento(id))!.copiar(clienteId: b));
      expect((await r.movimiento(id))!.clienteId, b);
      await r.actualizarMovimiento((await r.movimiento(id))!.copiar(quitarCliente: true));
      expect((await r.movimiento(id))!.clienteId, isNull);
    });

    test('en un cobro de trabajo, las sugerencias de "¿de qué?" son primero de trabajo', () async {
      for (var i = 0; i < 5; i++) {
        await r.agregarMovimiento(ingreso(1000, '2026-11-0${i + 1}', cat: cat['Juego'], desc: 'Ganó el bingo'));
      }
      await r.agregarMovimiento(ingreso(80000, '2026-11-05', cat: cat['Trabajo'], desc: 'Arreglo de vestido'));
      final sinCategoria = await r.sugerencias(TipoMovimiento.ingreso);
      expect(sinCategoria.first.descripcion, 'Ganó el bingo'); // el más usado
      final enTrabajo = await r.sugerencias(TipoMovimiento.ingreso, categoriaId: cat['Trabajo']);
      expect(enTrabajo.map((s) => s.descripcion).toList(), ['Arreglo de vestido', 'Ganó el bingo']); // no se esconde nada
    });

    test('un cliente que no existe es rechazado por la base', () async {
      expect(() => r.agregarMovimiento(cobro(1000, '2026-11-05', 4242)),
          throwsA(isA<ErrorDatos>().having((e) => e.mensaje, 'm', contains('cliente'))));
    });
  });
}
