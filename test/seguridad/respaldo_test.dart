// PRUEBAS DE SEGURIDAD de las copias: cifrado, manipulación, archivos
// maliciosos y restauración todo-o-nada.
import 'dart:convert';
import 'dart:typed_data';

import 'package:contabilidad_mama/core/fechas.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:contabilidad_mama/respaldo/csv.dart';
import 'package:contabilidad_mama/respaldo/respaldo.dart';
import 'package:contabilidad_mama/seguridad/cripto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ayudantes.dart';

const clave = 'mamá-2026';

void main() {
  late Repositorio origen;
  late ServicioRespaldo resp;

  setUp(() async {
    origen = await repoDePrueba();
    resp = ServicioRespaldo(origen, iteraciones: iteracionesMin);
    final c = await idsCategorias(origen);
    await origen.agregarMovimiento(ingreso(1500000, '2026-11-01', cat: c['Trabajo'], desc: 'Quincena'));
    await origen.agregarMovimiento(gasto(350000, '2026-11-02', cat: c['Mercado y comida'], desc: 'Mercado del mes'));
    await origen.agregarMovimiento(ingreso(200000, '2026-11-03', cat: c['Juego'], desc: 'Ganó el chance'));
    final borrado = await origen.agregarMovimiento(gasto(1000, '2026-11-03', desc: 'En papelera'));
    await origen.eliminarMovimiento(borrado);
  });
  tearDown(() => origen.db.close());

  Future<Repositorio> otroCelular() async => repoDePrueba();

  test('copia y restaura en otro celular: todo igual, incluida la papelera', () async {
    final archivo = await resp.crear(clave);
    final destino = await otroCelular();
    await destino.agregarMovimiento(gasto(777, '2020-01-01')); // se reemplaza
    final r = await ServicioRespaldo(destino).restaurar(archivo, clave);
    expect([r.movimientos, r.ingresos, r.egresos], [3, 1700000, 350000]);

    final mes = Periodo.de(TipoPeriodo.mes, '2026-11-01');
    expect((await destino.resumen(mes)).balance, (await origen.resumen(mes)).balance);
    expect((await destino.papelera()).single.descripcion, 'En papelera');
    expect((await destino.balanceJuego(mes)).ganado, 200000);
    expect(await destino.saldoHasta('2020-12-31'), 0);
    // Se puede seguir usando normalmente después de restaurar
    await destino.agregarMovimiento(gasto(5000, '2026-11-04'));
    expect(await destino.totalMovimientos(), 4);
    await destino.db.close();
  });

  test('el archivo no deja leer nada sin la contraseña', () async {
    final archivo = utf8.decode(await resp.crear(clave));
    for (final secreto in ['Quincena', 'Mercado', 'chance', '1500000', 'Trabajo']) {
      expect(archivo, isNot(contains(secreto)));
    }
    // Dos copias de lo mismo se ven totalmente distintas (sal y nonce al azar)
    expect(utf8.decode(await resp.crear(clave)), isNot(archivo));
  });

  test('contraseña incorrecta: no restaura y no toca nada', () async {
    final archivo = await resp.crear(clave);
    final destino = await otroCelular();
    await destino.agregarMovimiento(gasto(777, '2020-01-01'));
    await expectLater(ServicioRespaldo(destino).restaurar(archivo, 'otra-clave'),
        throwsA(isA<ErrorRespaldo>().having((e) => e.mensaje, 'm', contains('Contraseña incorrecta'))));
    expect(await destino.saldoHasta('2030-01-01'), -777);
    await destino.db.close();
  });

  test('contraseña muy corta para crear la copia', () async {
    expect(() => resp.crear('123'), throwsA(isA<ErrorRespaldo>()));
  });

  test('cambiar UN solo byte del archivo se detecta', () async {
    final json = jsonDecode(utf8.decode(await resp.crear(clave))) as Map<String, dynamic>;
    final datos = deB64(json['datos'] as String);
    for (final pos in [0, datos.length ~/ 2, datos.length - 1]) {
      final alterado = Uint8List.fromList(datos)..[pos] ^= 0x01;
      final archivo = utf8.encode(jsonEncode({...json, 'datos': b64(alterado)}));
      await expectLater(resp.leer(archivo, clave), throwsA(isA<ErrorRespaldo>()), reason: 'byte $pos');
    }
  });

  group('archivos maliciosos o dañados', () {
    Future<Map<String, dynamic>> base() async => jsonDecode(utf8.decode(await resp.crear(clave))) as Map<String, dynamic>;
    Future<void> rechaza(Object contenido) async {
      final bytes = contenido is List<int> ? contenido : utf8.encode(contenido is String ? contenido : jsonEncode(contenido));
      await expectLater(resp.leer(bytes, clave), throwsA(isA<ErrorRespaldo>()));
    }

    test('archivo vacío, texto cualquiera, JSON de otra cosa, binario', () async {
      await rechaza(<int>[]);
      await rechaza('hola');
      await rechaza({'a': 1});
      await rechaza([1, 2, 3]);
      await rechaza(List<int>.generate(1000, (i) => i % 256));
      await rechaza('{"formato":"contabilidad-mama"');
    });

    test('archivo gigante se rechaza sin leerlo', () async {
      await rechaza(Uint8List(tamanoMaximoRespaldo + 1));
    });

    test('iteraciones absurdas (ataque para congelar el celular)', () async {
      final b = await base();
      for (final it in [0, 1, 9999, 999999999, -5, '210000', null]) {
        await rechaza({...b, 'kdf': {...(b['kdf'] as Map), 'iteraciones': it}});
      }
    });

    test('versión futura, cifrado desconocido, campos faltantes', () async {
      final b = await base();
      await rechaza({...b, 'version': 99});
      await rechaza({...b, 'cifrado': 'rot13'});
      await rechaza({...b}..remove('nonce'));
      await rechaza({...b, 'nonce': 'no-es-base64!!'});
      await rechaza({...b, 'nonce': b64([1, 2, 3])});
      await rechaza({...b, 'datos': b64([1, 2, 3])});
    });

    /// Crea una copia VÁLIDAMENTE cifrada pero con contenido manipulado,
    /// como haría alguien que conoce la contraseña y quiere meter basura.
    Future<List<int>> cifradaCon(Map<String, dynamic> Function(Map<String, dynamic>) cambiar) async {
      final archivo = await resp.crear(clave);
      final leido = await resp.leer(archivo, clave);
      final interno = cambiar(jsonDecode(jsonEncode(leido.datos)) as Map<String, dynamic>);
      final sal = bytesAleatorios(16);
      final llave = await derivarClave(clave, sal, iteracionesMin);
      final c = await cifrarAes(llave, utf8.encode(jsonEncode(interno)));
      return utf8.encode(jsonEncode({
        'formato': formatoRespaldo, 'version': 1, 'cifrado': 'aes-256-gcm',
        'kdf': {'algoritmo': 'pbkdf2-sha256', 'iteraciones': iteracionesMin, 'sal': b64(sal)},
        'nonce': b64(c.nonce), 'datos': b64(c.cifrado),
      }));
    }

    Map<String, dynamic> mov(Map<String, dynamic> d, int i) => (d['movimientos'] as List)[i] as Map<String, dynamic>;

    final manipulaciones = <String, Map<String, dynamic> Function(Map<String, dynamic>)>{
      'monto negativo': (d) => d..['movimientos'] = [for (final m in d['movimientos'] as List) {...m as Map, 'monto': -5}],
      'monto con decimales': (d) {
        mov(d, 0)['monto'] = 1.5;
        return d;
      },
      'monto inflado sin ajustar el control': (d) {
        mov(d, 0)['monto'] = 99999999;
        return d;
      },
      'movimiento duplicado (mismo id)': (d) => d..['movimientos'] = [...d['movimientos'] as List, (d['movimientos'] as List).first],
      'categoría inexistente': (d) {
        mov(d, 0)['categoria_id'] = 4242;
        return d;
      },
      'fecha imposible': (d) {
        mov(d, 0)['fecha'] = '2026-02-31';
        return d;
      },
      'tipo inventado': (d) {
        mov(d, 0)['tipo'] = 'robo';
        return d;
      },
      'texto gigante': (d) {
        mov(d, 0)['descripcion'] = 'x' * 100000;
        return d;
      },
      'id negativo': (d) {
        mov(d, 0)['id'] = -1;
        return d;
      },
      'categorías con el mismo nombre': (d) {
        final cats = d['categorias'] as List;
        (cats[1] as Map)['nombre'] = (cats[0] as Map)['nombre'];
        return d;
      },
      'sin lista de movimientos': (d) => d..remove('movimientos'),
      'movimientos no es lista': (d) => d..['movimientos'] = 'muchos',
      'control de sumas alterado': (d) => d..['control'] = {...d['control'] as Map, 'ingresos': 1},
      'fecha de creación inválida': (d) {
        mov(d, 0)['creado_en'] = 'ayer';
        return d;
      },
    };

    manipulaciones.forEach((nombre, cambiar) {
      test('contenido manipulado: $nombre → no se restaura nada', () async {
        final archivo = await cifradaCon(cambiar);
        final destino = await otroCelular();
        await destino.agregarMovimiento(gasto(777, '2020-01-01'));
        await expectLater(ServicioRespaldo(destino).restaurar(archivo, clave), throwsA(isA<ErrorRespaldo>()));
        expect(await destino.saldoHasta('2030-01-01'), -777, reason: 'la base debe quedar intacta');
        expect(await destino.totalMovimientos(), 1);
        await destino.db.close();
      });
    });

    test('archivada con valor raro: la base lo rechaza y la transacción se deshace', () async {
      final archivo = await cifradaCon((d) {
        ((d['categorias'] as List)[0] as Map)['archivada'] = 7;
        return d;
      });
      final destino = await otroCelular();
      await destino.agregarMovimiento(gasto(777, '2020-01-01'));
      await expectLater(ServicioRespaldo(destino).restaurar(archivo, clave), throwsA(isA<ErrorRespaldo>()));
      expect(await destino.totalMovimientos(), 1);
      expect((await destino.categorias()).length, greaterThan(10));
      await destino.db.close();
    });
  });

  group('exportar a Excel (CSV)', () {
    test('neutraliza fórmulas (inyección CSV)', () {
      // Tiene comillas, así que además va entre comillas: "'=HYPERLINK(...)"
      expect(celdaSegura('=HYPERLINK("http://malo","clic")'), startsWith('"\'=HYPERLINK'));
      expect(celdaSegura('+cmd|/C calc!A0'), "'+cmd|/C calc!A0");
      expect(celdaSegura('-2+3'), "'-2+3");
      expect(celdaSegura('@SUM(A1)'), "'@SUM(A1)");
      expect(celdaSegura('\t=1'), "'\t=1");
      expect(celdaSegura('Mercado'), 'Mercado');
    });

    test('comillas, punto y coma y saltos de línea no rompen las columnas', () {
      expect(celdaSegura('a;b'), '"a;b"');
      expect(celdaSegura('dijo "hola"'), '"dijo ""hola"""');
      expect(celdaSegura('línea1\nlínea2'), '"línea1\nlínea2"');
    });

    test('genera filas con signo correcto y tildes legibles', () async {
      final movs = await origen.movimientos(Periodo.de(TipoPeriodo.mes, '2026-11-01'));
      final cats = {for (final c in await origen.categorias(incluirArchivadas: true)) c.id!: c};
      final bytes = generarCsv(movs, cats);
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]); // BOM: Excel lee bien las tildes
      final texto = utf8.decode(bytes);
      expect(texto, contains('Fecha;Tipo;Valor;Valor con signo;Categoría'));
      expect(texto, contains('2026-11-02;Salió;350000;-350000;Mercado y comida;Mercado del mes'));
      expect(texto, contains('2026-11-01;Entró;1500000;1500000;Trabajo;Quincena'));
      expect(texto, isNot(contains('En papelera')));
      final m = Movimiento(tipo: TipoMovimiento.egreso, monto: 1, fecha: '2026-11-01', descripcion: '=1+1');
      expect(utf8.decode(generarCsv([m], cats)), contains(";'=1+1;"));
    });
  });
}
