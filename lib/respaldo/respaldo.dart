/// Copias de seguridad cifradas.
///
/// Archivo `.cmama` = JSON con los datos cifrados con AES-256-GCM, usando una
/// clave derivada (PBKDF2) de la contraseña que mamá elige. GCM detecta
/// cualquier cambio en el archivo: si alguien lo altera, no se restaura.
///
/// Restaurar es todo o nada: se valida cada registro, se reemplaza dentro de
/// una transacción y al final se comprueba que las sumas cuadren con las que
/// quedaron escritas en la copia. Si algo no cuadra, no cambia nada.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:sqflite_sqlcipher/sqlite_api.dart';

import '../datos/base_datos.dart';
import '../datos/modelos.dart';
import '../datos/repositorio.dart';
import '../seguridad/cripto.dart';

const formatoRespaldo = 'contabilidad-mama';
const versionRespaldo = 1;
const tamanoMaximoRespaldo = 40 * 1024 * 1024; // 40 MB
const maxMovimientosRespaldo = 1000000;
const maxCategoriasRespaldo = 1000;
const iteracionesMin = 10000;
const iteracionesMax = 2000000;

class ErrorRespaldo implements Exception {
  final String mensaje;
  const ErrorRespaldo(this.mensaje);
  @override
  String toString() => mensaje;
}

String? validarClaveRespaldo(String clave) {
  if (clave.length < 6) return 'La contraseña de la copia debe tener al menos 6 caracteres';
  if (clave.length > 100) return 'La contraseña es demasiado larga';
  return null;
}

class ResumenRespaldo {
  final int movimientos;
  final int categorias;
  final int ingresos;
  final int egresos;
  final String creado;
  const ResumenRespaldo(this.movimientos, this.categorias, this.ingresos, this.egresos, this.creado);
}

class ServicioRespaldo {
  final Repositorio repo;
  final int iteraciones;
  ServicioRespaldo(this.repo, {this.iteraciones = 210000});

  Database get _db => repo.db;

  /// Crea la copia cifrada (bytes del archivo).
  Future<Uint8List> crear(String clave, {DateTime? ahora}) async {
    final error = validarClaveRespaldo(clave);
    if (error != null) throw ErrorRespaldo(error);

    final cats = await _db.query('categorias', orderBy: 'id');
    final movs = await _db.query('movimientos', orderBy: 'id');
    final sumas = await _sumas(_db);
    final interno = utf8.encode(jsonEncode({
      'version': versionRespaldo,
      'esquema': versionEsquema,
      'creado': (ahora ?? DateTime.now()).toUtc().toIso8601String(),
      'categorias': cats,
      'movimientos': movs,
      'control': sumas,
    }));

    final sal = bytesAleatorios(16);
    final llave = await derivarClave(clave, sal, iteraciones);
    final c = await cifrarAes(llave, interno);
    final externo = {
      'formato': formatoRespaldo,
      'version': versionRespaldo,
      'kdf': {'algoritmo': 'pbkdf2-sha256', 'iteraciones': iteraciones, 'sal': b64(sal)},
      'cifrado': 'aes-256-gcm',
      'nonce': b64(c.nonce),
      'datos': b64(c.cifrado),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(externo)));
  }

  /// Abre y valida una copia SIN tocar la base (para mostrar qué contiene).
  Future<({ResumenRespaldo resumen, Map<String, dynamic> datos})> leer(List<int> archivo, String clave) async {
    if (archivo.length > tamanoMaximoRespaldo) throw const ErrorRespaldo('El archivo es demasiado grande para ser una copia');
    if (archivo.isEmpty) throw const ErrorRespaldo('El archivo está vacío');

    final Object? externo;
    try {
      externo = jsonDecode(utf8.decode(archivo));
    } on FormatException {
      throw const ErrorRespaldo('Este archivo no es una copia de la app');
    }
    if (externo is! Map || externo['formato'] != formatoRespaldo) {
      throw const ErrorRespaldo('Este archivo no es una copia de la app');
    }
    if (externo['version'] is! int || (externo['version'] as int) > versionRespaldo) {
      throw const ErrorRespaldo('La copia es de una versión más nueva de la app. Actualiza la app primero.');
    }
    final kdf = externo['kdf'];
    if (kdf is! Map || kdf['algoritmo'] != 'pbkdf2-sha256' || externo['cifrado'] != 'aes-256-gcm') {
      throw const ErrorRespaldo('La copia está dañada (cifrado desconocido)');
    }
    final iter = kdf['iteraciones'];
    // Un archivo malicioso podría pedir mil millones de iteraciones para
    // congelar el celular: se aceptan solo valores razonables.
    if (iter is! int || iter < iteracionesMin || iter > iteracionesMax) {
      throw const ErrorRespaldo('La copia está dañada (parámetros inválidos)');
    }

    final Uint8List sal, nonce, datos;
    try {
      sal = deB64(kdf['sal'] as String);
      nonce = deB64(externo['nonce'] as String);
      datos = deB64(externo['datos'] as String);
    } catch (_) {
      throw const ErrorRespaldo('La copia está dañada');
    }
    if (sal.length < 16 || nonce.length != 12) throw const ErrorRespaldo('La copia está dañada');

    final llave = await derivarClave(clave, sal, iter);
    final Uint8List plano;
    try {
      plano = await descifrarAes(llave, nonce, datos);
    } on SecretBoxAuthenticationError {
      throw const ErrorRespaldo('Contraseña incorrecta, o el archivo fue modificado');
    } on FormatException {
      throw const ErrorRespaldo('La copia está incompleta');
    }

    final Object? interno;
    try {
      interno = jsonDecode(utf8.decode(plano));
    } catch (_) {
      throw const ErrorRespaldo('La copia está dañada');
    }
    if (interno is! Map<String, dynamic>) throw const ErrorRespaldo('La copia está dañada');
    final r = _validarContenido(interno);
    return (resumen: r, datos: interno);
  }

  /// Reemplaza TODOS los datos actuales por los de la copia.
  Future<ResumenRespaldo> restaurar(List<int> archivo, String clave) async {
    final leido = await leer(archivo, clave);
    final d = leido.datos;
    final control = (d['control'] as Map).cast<String, dynamic>();

    try {
      await _restaurarEnTransaccion(d, control);
    } on DatabaseException {
      throw const ErrorRespaldo('La copia tiene datos que no son válidos. No se cambió nada.');
    }
    repo.avisarCambio();
    return leido.resumen;
  }

  Future<void> _restaurarEnTransaccion(Map<String, dynamic> d, Map<String, dynamic> control) async {
    await _db.transaction((txn) async {
      await txn.delete('movimientos');
      await txn.delete('categorias');
      await txn.delete('sqlite_sequence', where: "name IN ('movimientos','categorias')");
      final b = txn.batch();
      for (final c in (d['categorias'] as List)) {
        b.insert('categorias', _soloColumnas(c as Map, _colsCategoria));
      }
      for (final m in (d['movimientos'] as List)) {
        b.insert('movimientos', _soloColumnas(m as Map, _colsMovimiento));
      }
      await b.commit(noResult: true);
      final quedo = await _sumas(txn);
      if (quedo['ingresos'] != control['ingresos'] ||
          quedo['egresos'] != control['egresos'] ||
          quedo['cantidad'] != control['cantidad']) {
        // Lanzar aquí deshace la transacción: la base queda como estaba.
        throw const ErrorRespaldo('Las sumas de la copia no cuadran. No se cambió nada.');
      }
    });
  }

  static const _colsCategoria = ['id', 'nombre', 'tipo', 'icono', 'color', 'orden', 'archivada'];
  static const _colsMovimiento = [
    'id', 'tipo', 'monto', 'categoria_id', 'descripcion', 'nota', 'medio', 'fecha',
    'creado_en', 'actualizado_en', 'eliminado_en',
  ];

  Map<String, Object?> _soloColumnas(Map m, List<String> cols) => {for (final c in cols) c: m[c]};

  ResumenRespaldo _validarContenido(Map<String, dynamic> d) {
    final cats = d['categorias'];
    final movs = d['movimientos'];
    final control = d['control'];
    if (cats is! List || movs is! List || control is! Map) throw const ErrorRespaldo('La copia está dañada');
    if (cats.length > maxCategoriasRespaldo || movs.length > maxMovimientosRespaldo) {
      throw const ErrorRespaldo('La copia tiene demasiados datos');
    }

    final idsCat = <int>{};
    final nombres = <String>{};
    for (final c in cats) {
      try {
        if (c is! Map) throw const FormatException();
        final cat = Categoria.deMapa(c.cast<String, Object?>());
        final id = cat.id;
        if (id == null || id <= 0 || !idsCat.add(id)) throw const FormatException();
        if (validarCategoria(cat) != null || !nombres.add(cat.nombre.trim().toLowerCase())) throw const FormatException();
        if (cat.icono.isEmpty || cat.icono.length > 30) throw const FormatException();
      } catch (_) {
        throw const ErrorRespaldo('La copia tiene una categoría dañada');
      }
    }

    var ingresos = 0, egresos = 0, cantidad = 0;
    final idsMov = <int>{};
    for (final m in movs) {
      try {
        if (m is! Map) throw const FormatException();
        final mov = Movimiento.deMapa(m.cast<String, Object?>());
        final id = mov.id;
        if (id == null || id <= 0 || !idsMov.add(id)) throw const FormatException();
        if (validarMovimiento(mov) != null) throw const FormatException();
        if (mov.categoriaId != null && !idsCat.contains(mov.categoriaId)) throw const FormatException();
        for (final k in ['creado_en', 'actualizado_en']) {
          if (m[k] is! String || DateTime.tryParse(m[k] as String) == null) throw const FormatException();
        }
        if (m['eliminado_en'] != null && (m['eliminado_en'] is! String || DateTime.tryParse(m['eliminado_en'] as String) == null)) {
          throw const FormatException();
        }
        if (mov.eliminadoEn == null) {
          cantidad++;
          if (mov.tipo == TipoMovimiento.ingreso) {
            ingresos += mov.monto;
          } else {
            egresos += mov.monto;
          }
        }
      } catch (_) {
        throw const ErrorRespaldo('La copia tiene un movimiento dañado');
      }
    }
    if (control['ingresos'] != ingresos || control['egresos'] != egresos || control['cantidad'] != cantidad) {
      throw const ErrorRespaldo('Las sumas de la copia no cuadran. No se cambió nada.');
    }
    return ResumenRespaldo(cantidad, cats.length, ingresos, egresos, '${d['creado'] ?? ''}');
  }

  static Future<Map<String, int>> _sumas(DatabaseExecutor db) async {
    final f = (await db.rawQuery('''
      SELECT coalesce(sum(CASE WHEN tipo = 'ingreso' THEN monto END), 0) AS ingresos,
             coalesce(sum(CASE WHEN tipo = 'egreso'  THEN monto END), 0) AS egresos,
             count(*) AS cantidad
      FROM movimientos WHERE eliminado_en IS NULL''')).first;
    return {'ingresos': f['ingresos'] as int, 'egresos': f['egresos'] as int, 'cantidad': f['cantidad'] as int};
  }
}
