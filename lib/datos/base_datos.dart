/// Esquema de la base de datos local.
///
/// Defensa en capas: además de que la app valida todo antes de guardar, la
/// propia base de datos rechaza con CHECKs cualquier dato imposible (montos
/// negativos o gigantes, fechas mal escritas, tipos desconocidos). Así, ni un
/// error de programación puede dejar la contabilidad descuadrada.
library;

import 'package:sqflite_sqlcipher/sqlite_api.dart';

import '../core/dinero.dart';
import 'categorias_iniciales.dart';
import 'modelos.dart';

/// v1: categorías, movimientos, ajustes.
/// v2: clientes (trabajo) y movimientos.cliente_id.
const versionEsquema = 2;

Future<void> configurarBD(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

/// Instalación nueva: se crea la v1 y se aplican las mismas migraciones que
/// recibe un celular que actualiza. Así el esquema es idéntico en ambos casos.
Future<void> crearBD(Database db, int version) async {
  await crearEsquemaV1(db);
  await actualizarBD(db, 1, version);
}

/// Esquema de la versión 1.0.0 (no cambiar: lo usan las pruebas de migración).
Future<void> crearEsquemaV1(Database db) async {
  final b = db.batch();
  b.execute('''
    CREATE TABLE categorias (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre    TEXT    NOT NULL CHECK (length(trim(nombre)) BETWEEN 1 AND $maxNombreCategoria),
      tipo      TEXT    NOT NULL CHECK (tipo IN ('ingreso','egreso','ambos')),
      icono     TEXT    NOT NULL CHECK (length(icono) BETWEEN 1 AND 30),
      color     INTEGER NOT NULL,
      orden     INTEGER NOT NULL DEFAULT 0,
      archivada INTEGER NOT NULL DEFAULT 0 CHECK (archivada IN (0,1))
    )''');
  b.execute('CREATE UNIQUE INDEX ux_categorias_nombre ON categorias (lower(trim(nombre)))');
  b.execute('''
    CREATE TABLE movimientos (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      tipo           TEXT    NOT NULL CHECK (tipo IN ('ingreso','egreso')),
      monto          INTEGER NOT NULL CHECK (typeof(monto) = 'integer' AND monto > 0 AND monto <= $montoMaximo),
      categoria_id   INTEGER REFERENCES categorias(id) ON DELETE RESTRICT,
      descripcion    TEXT    NOT NULL DEFAULT '' CHECK (length(descripcion) <= $maxDescripcion),
      nota           TEXT    NOT NULL DEFAULT '' CHECK (length(nota) <= $maxNota),
      medio          TEXT    CHECK (medio IS NULL OR medio IN ('efectivo','nequi','daviplata','banco','tarjeta','otro')),
      fecha          TEXT    NOT NULL CHECK (fecha GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]' AND coalesce(date(fecha), '') = fecha),
      creado_en      TEXT    NOT NULL,
      actualizado_en TEXT    NOT NULL,
      eliminado_en   TEXT
    )''');
  // Los reportes siempre filtran por "no eliminado" + rango de fechas.
  b.execute('CREATE INDEX ix_mov_fecha ON movimientos (eliminado_en, fecha)');
  b.execute('CREATE INDEX ix_mov_categoria ON movimientos (categoria_id, fecha)');
  // Sugerencias de "¿en qué?": agrupar por descripción sin ordenar toda la tabla.
  b.execute("CREATE INDEX ix_mov_desc ON movimientos (tipo, descripcion) WHERE eliminado_en IS NULL AND descripcion <> ''");
  b.execute('''
    CREATE TABLE ajustes (
      clave TEXT PRIMARY KEY CHECK (length(clave) <= 50),
      valor TEXT NOT NULL CHECK (length(valor) <= 500)
    )''');
  for (final c in categoriasIniciales) {
    b.insert('categorias', c.aMapa());
  }
  await b.commit(noResult: true);
}

/// Migraciones. Regla: solo se AGREGA (tablas, columnas, índices); nunca se
/// borra ni se reescribe un dato de mamá. sqflite corre esto dentro de una
/// transacción: si algo falla, la base queda como estaba.
Future<void> actualizarBD(Database db, int anterior, int nueva) async {
  if (anterior < 2) await _migrarAV2(db);
}

Future<void> _migrarAV2(Database db) async {
  await db.execute('''
    CREATE TABLE clientes (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre    TEXT    NOT NULL CHECK (length(trim(nombre)) BETWEEN 1 AND $maxNombreCliente),
      clave     TEXT    NOT NULL UNIQUE CHECK (length(clave) BETWEEN 1 AND $maxNombreCliente),
      telefono  TEXT    NOT NULL DEFAULT '' CHECK (length(telefono) <= $maxTelefono),
      nota      TEXT    NOT NULL DEFAULT '' CHECK (length(nota) <= $maxNotaCliente),
      archivado INTEGER NOT NULL DEFAULT 0 CHECK (archivado IN (0,1)),
      creado_en TEXT    NOT NULL
    )''');
  // "clave" = nombre normalizado en Dart (minúsculas Unicode y sin tildes):
  // lower() de SQLite no entiende la Ñ ni las tildes.
  await db.execute('ALTER TABLE movimientos ADD COLUMN cliente_id INTEGER REFERENCES clientes(id) ON DELETE RESTRICT');
  await db.execute('CREATE INDEX ix_mov_cliente ON movimientos (cliente_id, fecha)');
}

/// Opciones comunes para abrir la base (las usa la app y las pruebas).
OpenDatabaseOptions opcionesBD() => OpenDatabaseOptions(
      version: versionEsquema,
      onConfigure: configurarBD,
      onCreate: crearBD,
      onUpgrade: actualizarBD,
    );
