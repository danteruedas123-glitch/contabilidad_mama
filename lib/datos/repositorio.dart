/// Acceso a los datos. Toda la plata se suma dentro de SQLite con enteros de
/// 64 bits: la interfaz solo muestra lo que la base calcula.
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

import '../core/fechas.dart';
import 'modelos.dart';

/// Error con un mensaje que se le puede mostrar a la persona tal cual.
class ErrorDatos implements Exception {
  final String mensaje;
  const ErrorDatos(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Sugerencia para el campo "¿en qué?": lo que ya ha escrito antes.
class Sugerencia {
  final String descripcion;
  final int? categoriaId;
  final int veces;
  const Sugerencia(this.descripcion, this.categoriaId, this.veces);
}

class Repositorio extends ChangeNotifier {
  final Database db;
  final String Function() _ahora;

  Repositorio(this.db, {String Function()? ahora})
      : _ahora = ahora ?? (() => DateTime.now().toUtc().toIso8601String());

  /// Sube cada vez que algo cambia; las pantallas lo usan para recargar.
  int revision = 0;

  void _cambio() {
    revision++;
    notifyListeners();
  }

  // ------------------------------------------------------------ categorías

  Future<List<Categoria>> categorias({bool incluirArchivadas = false}) async {
    final filas = await db.query(
      'categorias',
      where: incluirArchivadas ? null : 'archivada = 0',
      orderBy: 'orden, nombre COLLATE NOCASE',
    );
    return filas.map(Categoria.deMapa).toList();
  }

  Future<Categoria> guardarCategoria(Categoria c) async {
    final limpia = c.copiar(nombre: c.nombre.trim().replaceAll(RegExp(r'\s+'), ' '));
    final error = validarCategoria(limpia);
    if (error != null) throw ErrorDatos(error);
    try {
      if (limpia.id == null) {
        final orden = _primerEntero(await db.rawQuery('SELECT coalesce(max(orden), 0) + 1 FROM categorias WHERE orden < 99')) ?? 50;
        final nueva = limpia.copiar(orden: limpia.orden == 0 ? orden : limpia.orden);
        final id = await db.insert('categorias', nueva.aMapa());
        _cambio();
        return Categoria.deMapa({...nueva.aMapa(), 'id': id});
      }
      final n = await db.update('categorias', limpia.aMapa(), where: 'id = ?', whereArgs: [limpia.id]);
      if (n == 0) throw const ErrorDatos('Esa categoría ya no existe');
      _cambio();
      return limpia;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw ErrorDatos('Ya existe una categoría llamada "${limpia.nombre}"');
      rethrow;
    }
  }

  Future<void> archivarCategoria(int id, {bool archivar = true}) async {
    await db.update('categorias', {'archivada': archivar ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    _cambio();
  }

  /// Solo se puede borrar una categoría que nunca se ha usado; si tiene
  /// movimientos, se archiva (se esconde) para no perder la historia.
  Future<void> eliminarCategoria(int id) async {
    final usos = _primerEntero(await db.rawQuery('SELECT count(*) FROM movimientos WHERE categoria_id = ?', [id])) ?? 0;
    if (usos > 0) {
      throw ErrorDatos('Esta categoría tiene $usos movimiento${usos == 1 ? '' : 's'}. Puedes archivarla para que no salga más.');
    }
    await db.delete('categorias', where: 'id = ?', whereArgs: [id]);
    _cambio();
  }

  Future<int> usosCategoria(int id) async =>
      _primerEntero(await db.rawQuery('SELECT count(*) FROM movimientos WHERE categoria_id = ? AND eliminado_en IS NULL', [id])) ?? 0;

  // ------------------------------------------------------------ movimientos

  Future<int> agregarMovimiento(Movimiento m) async {
    _validar(m);
    final ahora = _ahora();
    try {
      final id = await db.insert('movimientos', {
        ...m.aMapa()..remove('id'),
        'creado_en': ahora,
        'actualizado_en': ahora,
      });
      _cambio();
      return id;
    } on DatabaseException catch (e) {
      throw _traducir(e);
    }
  }

  Future<void> actualizarMovimiento(Movimiento m) async {
    if (m.id == null) throw const ErrorDatos('Movimiento sin identificador');
    _validar(m);
    try {
      final n = await db.update(
        'movimientos',
        {...m.aMapa()..remove('id'), 'actualizado_en': _ahora()},
        where: 'id = ? AND eliminado_en IS NULL',
        whereArgs: [m.id],
      );
      if (n == 0) throw const ErrorDatos('Ese movimiento ya no existe o está en la papelera');
      _cambio();
    } on DatabaseException catch (e) {
      throw _traducir(e);
    }
  }

  /// Manda el movimiento a la papelera (no se borra de verdad).
  Future<void> eliminarMovimiento(int id) async {
    await db.update('movimientos', {'eliminado_en': _ahora()}, where: 'id = ? AND eliminado_en IS NULL', whereArgs: [id]);
    _cambio();
  }

  Future<void> restaurarMovimiento(int id) async {
    await db.update('movimientos', {'eliminado_en': null, 'actualizado_en': _ahora()}, where: 'id = ?', whereArgs: [id]);
    _cambio();
  }

  /// Borrado definitivo: solo para lo que ya está en la papelera.
  Future<void> eliminarDefinitivo(int id) async {
    await db.delete('movimientos', where: 'id = ? AND eliminado_en IS NOT NULL', whereArgs: [id]);
    _cambio();
  }

  Future<int> vaciarPapelera() async {
    final n = await db.delete('movimientos', where: 'eliminado_en IS NOT NULL');
    _cambio();
    return n;
  }

  Future<List<Movimiento>> papelera() async {
    final filas = await db.query('movimientos', where: 'eliminado_en IS NOT NULL', orderBy: 'eliminado_en DESC', limit: 500);
    return filas.map(Movimiento.deMapa).toList();
  }

  Future<Movimiento?> movimiento(int id) async {
    final f = await db.query('movimientos', where: 'id = ?', whereArgs: [id], limit: 1);
    return f.isEmpty ? null : Movimiento.deMapa(f.first);
  }

  /// Movimientos de un período, del más nuevo al más viejo.
  Future<List<Movimiento>> movimientos(
    Periodo p, {
    TipoMovimiento? tipo,
    int? categoriaId,
    String? texto,
    int limite = 2000,
  }) async {
    final where = <String>['eliminado_en IS NULL', 'fecha BETWEEN ? AND ?'];
    final args = <Object?>[p.desde, p.hasta];
    _filtros(where, args, tipo: tipo, categoriaId: categoriaId, texto: texto);
    final filas = await db.query(
      'movimientos',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'fecha DESC, id DESC',
      limit: limite.clamp(1, 20000),
    );
    return filas.map(Movimiento.deMapa).toList();
  }

  /// Búsqueda en toda la historia por lo escrito en "¿en qué?" o en la nota.
  Future<List<Movimiento>> buscar(String texto, {int limite = 300}) async {
    final where = <String>['eliminado_en IS NULL'];
    final args = <Object?>[];
    _filtros(where, args, texto: texto);
    final filas = await db.query('movimientos',
        where: where.join(' AND '), whereArgs: args, orderBy: 'fecha DESC, id DESC', limit: limite.clamp(1, 2000));
    return filas.map(Movimiento.deMapa).toList();
  }

  void _filtros(List<String> where, List<Object?> args, {TipoMovimiento? tipo, int? categoriaId, String? texto}) {
    if (tipo != null) {
      where.add('tipo = ?');
      args.add(tipo.clave);
    }
    if (categoriaId != null) {
      where.add('categoria_id = ?');
      args.add(categoriaId);
    }
    final t = texto?.trim() ?? '';
    if (t.isNotEmpty) {
      // Los comodines de LIKE se escapan: buscar "%" encuentra un "%" de verdad.
      final seguro = t.substring(0, t.length.clamp(0, 60)).replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      where.add(r"(descripcion LIKE ? ESCAPE '\' OR nota LIKE ? ESCAPE '\')");
      args..add('%$seguro%')..add('%$seguro%');
    }
  }

  // ------------------------------------------------------------ reportes

  Future<Resumen> resumen(Periodo p) async {
    final f = (await db.rawQuery('''
      SELECT coalesce(sum(CASE WHEN tipo = 'ingreso' THEN monto END), 0) AS ingresos,
             coalesce(sum(CASE WHEN tipo = 'egreso'  THEN monto END), 0) AS egresos,
             count(*) AS cantidad
      FROM movimientos
      WHERE eliminado_en IS NULL AND fecha BETWEEN ? AND ?''', [p.desde, p.hasta])).first;
    return Resumen(ingresos: f['ingresos'] as int, egresos: f['egresos'] as int, cantidad: f['cantidad'] as int);
  }

  /// Saldo acumulado de toda la historia hasta [hasta] (incluida).
  Future<int> saldoHasta(String hasta) async {
    final v = _primerEntero(await db.rawQuery('''
      SELECT coalesce(sum(CASE WHEN tipo = 'ingreso' THEN monto ELSE -monto END), 0)
      FROM movimientos WHERE eliminado_en IS NULL AND fecha <= ?''', [hasta]));
    return v ?? 0;
  }

  Future<List<TotalCategoria>> totalesPorCategoria(Periodo p) async {
    final cats = {for (final c in await categorias(incluirArchivadas: true)) c.id: c};
    final filas = await db.rawQuery('''
      SELECT categoria_id, tipo, sum(monto) AS total, count(*) AS cantidad
      FROM movimientos
      WHERE eliminado_en IS NULL AND fecha BETWEEN ? AND ?
      GROUP BY categoria_id, tipo
      ORDER BY total DESC''', [p.desde, p.hasta]);
    return filas
        .map((f) => TotalCategoria(
              categoria: cats[f['categoria_id']],
              tipo: TipoMovimiento.desde(f['tipo'] as String),
              total: f['total'] as int,
              cantidad: f['cantidad'] as int,
            ))
        .toList();
  }

  /// Totales por día (para semana y mes) — incluye los días sin movimientos.
  Future<List<PuntoSerie>> seriePorDia(Periodo p) async {
    final filas = await db.rawQuery('''
      SELECT fecha,
             coalesce(sum(CASE WHEN tipo = 'ingreso' THEN monto END), 0) AS i,
             coalesce(sum(CASE WHEN tipo = 'egreso'  THEN monto END), 0) AS e
      FROM movimientos
      WHERE eliminado_en IS NULL AND fecha BETWEEN ? AND ?
      GROUP BY fecha''', [p.desde, p.hasta]);
    final mapa = {for (final f in filas) f['fecha'] as String: f};
    final dias = p.dias.clamp(1, 400);
    return [
      for (var i = 0; i < dias; i++)
        () {
          final d = sumarDias(p.desde, i);
          final f = mapa[d];
          return PuntoSerie(d, (f?['i'] as int?) ?? 0, (f?['e'] as int?) ?? 0);
        }(),
    ];
  }

  /// Totales por mes de un año (12 puntos).
  Future<List<PuntoSerie>> seriePorMes(String anio) async {
    final filas = await db.rawQuery('''
      SELECT substr(fecha, 1, 7) AS mes,
             coalesce(sum(CASE WHEN tipo = 'ingreso' THEN monto END), 0) AS i,
             coalesce(sum(CASE WHEN tipo = 'egreso'  THEN monto END), 0) AS e
      FROM movimientos
      WHERE eliminado_en IS NULL AND fecha BETWEEN ? AND ?
      GROUP BY mes''', ['$anio-01-01', '$anio-12-31']);
    final mapa = {for (final f in filas) f['mes'] as String: f};
    return [
      for (var m = 1; m <= 12; m++)
        () {
          final clave = '$anio-${m.toString().padLeft(2, '0')}';
          final f = mapa[clave];
          return PuntoSerie(clave, (f?['i'] as int?) ?? 0, (f?['e'] as int?) ?? 0);
        }(),
    ];
  }

  /// Lo que ganó jugando contra lo que jugó, en el período.
  Future<BalanceJuego> balanceJuego(Periodo p) async {
    final f = (await db.rawQuery('''
      SELECT coalesce(sum(CASE WHEN m.tipo = 'ingreso' THEN m.monto END), 0) AS ganado,
             coalesce(sum(CASE WHEN m.tipo = 'egreso'  THEN m.monto END), 0) AS jugado
      FROM movimientos m JOIN categorias c ON c.id = m.categoria_id
      WHERE m.eliminado_en IS NULL AND m.fecha BETWEEN ? AND ?
        AND (c.icono = 'juego' OR lower(c.nombre) = 'juego')''', [p.desde, p.hasta])).first;
    return BalanceJuego(f['ganado'] as int, f['jugado'] as int);
  }

  /// Lo que más ha escrito antes en "¿en qué?", para no tener que escribirlo otra vez.
  Future<List<Sugerencia>> sugerencias(TipoMovimiento tipo, {String prefijo = '', int limite = 8}) async {
    final p = prefijo.trim();
    final seguro = p.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    // Una sola pasada: en SQLite, con max(id) las demás columnas salen de esa
    // misma fila, así que categoria_id es la del uso más reciente.
    final filas = await db.rawQuery(r'''
      SELECT descripcion, count(*) AS veces, max(id) AS ultimo, categoria_id
      FROM movimientos INDEXED BY ix_mov_desc
      WHERE eliminado_en IS NULL AND tipo = ? AND descripcion <> '' AND descripcion LIKE ? ESCAPE '\'
      GROUP BY descripcion
      ORDER BY veces DESC, ultimo DESC
      LIMIT ?''', [tipo.clave, '$seguro%', limite]);
    return filas.map((f) => Sugerencia(f['descripcion'] as String, f['categoria_id'] as int?, f['veces'] as int)).toList();
  }

  Future<int> totalMovimientos() async =>
      _primerEntero(await db.rawQuery('SELECT count(*) FROM movimientos WHERE eliminado_en IS NULL')) ?? 0;

  // ------------------------------------------------------------ ajustes

  Future<String?> ajuste(String clave) async {
    final f = await db.query('ajustes', where: 'clave = ?', whereArgs: [clave], limit: 1);
    return f.isEmpty ? null : f.first['valor'] as String;
  }

  Future<void> guardarAjuste(String clave, String valor) async {
    await db.insert('ajustes', {'clave': clave, 'valor': valor}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Revisa que el archivo de la base no esté dañado.
  Future<bool> integridadOk() async {
    final f = await db.rawQuery('PRAGMA quick_check');
    return f.length == 1 && f.first.values.first == 'ok';
  }

  // ------------------------------------------------------------ internos

  void _validar(Movimiento m) {
    final error = validarMovimiento(m);
    if (error != null) throw ErrorDatos(error);
  }

  ErrorDatos _traducir(DatabaseException e) {
    final t = e.toString();
    if (t.contains('FOREIGN KEY')) return const ErrorDatos('La categoría elegida ya no existe');
    if (t.contains('CHECK')) return const ErrorDatos('Algún dato no es válido. Revisa el valor y la fecha.');
    return ErrorDatos('No se pudo guardar: ${e.runtimeType}');
  }

  /// Lo usa la restauración de copias para que las pantallas recarguen.
  void avisarCambio() => _cambio();
}

int? _primerEntero(List<Map<String, Object?>> filas) {
  if (filas.isEmpty || filas.first.isEmpty) return null;
  final v = filas.first.values.first;
  return v is int ? v : (v is num ? v.toInt() : null);
}
