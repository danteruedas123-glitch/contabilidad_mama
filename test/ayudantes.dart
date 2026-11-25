import 'package:contabilidad_mama/datos/base_datos.dart';
import 'package:contabilidad_mama/datos/modelos.dart';
import 'package:contabilidad_mama/datos/repositorio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Base de datos en memoria con el MISMO esquema que la app (sin cifrar:
/// SQLCipher solo existe en el celular; el cifrado se prueba en el emulador).
Future<Repositorio> repoDePrueba({String Function()? ahora, bool sinIsolate = false}) async {
  sqfliteFfiInit();
  final o = opcionesBD();
  // singleInstance: false → cada llamada es un "celular" distinto
  // En pruebas de pantallas (tiempo simulado) la base corre en el mismo hilo.
  final fabrica = sinIsolate ? databaseFactoryFfiNoIsolate : databaseFactoryFfi;
  final db = await fabrica.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: o.version,
      onConfigure: o.onConfigure,
      onCreate: o.onCreate,
      onUpgrade: o.onUpgrade,
      singleInstance: false,
    ),
  );
  return Repositorio(db, ahora: ahora);
}

Future<Map<String, int>> idsCategorias(Repositorio r) async =>
    {for (final c in await r.categorias(incluirArchivadas: true)) c.nombre: c.id!};

Movimiento gasto(int monto, String fecha, {int? cat, String desc = ''}) =>
    Movimiento(tipo: TipoMovimiento.egreso, monto: monto, fecha: fecha, categoriaId: cat, descripcion: desc);

Movimiento ingreso(int monto, String fecha, {int? cat, String desc = ''}) =>
    Movimiento(tipo: TipoMovimiento.ingreso, monto: monto, fecha: fecha, categoriaId: cat, descripcion: desc);
