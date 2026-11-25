import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import '../seguridad/almacen_seguro.dart';
import '../seguridad/llave_bd.dart';
import 'base_datos.dart';

const nombreArchivoBD = 'contabilidad.db';

Future<String> rutaBD() async {
  final dir = await getApplicationSupportDirectory(); // privado de la app
  return p.join(dir.path, nombreArchivoBD);
}

/// Abre la base cifrada con SQLCipher (AES-256). Si el archivo se copia a
/// otro lado (por ejemplo con el celular rooteado), es ilegible sin la llave
/// que vive en el Keystore.
Future<cipher.Database> abrirBDCifrada(AlmacenSeguro almacen) async {
  final ruta = await rutaBD();
  final llave = await obtenerLlaveBD(almacen, existeBD: File(ruta).existsSync());
  final o = opcionesBD();
  return cipher.openDatabase(
    ruta,
    // Llave cruda de 256 bits (x'...'): ya es aleatoria, así que SQLCipher no
    // necesita derivarla con su propio PBKDF2 y la base abre mucho más rápido.
    password: "x'$llave'",
    version: o.version,
    onConfigure: o.onConfigure,
    onCreate: o.onCreate,
    onUpgrade: o.onUpgrade,
  );
}
