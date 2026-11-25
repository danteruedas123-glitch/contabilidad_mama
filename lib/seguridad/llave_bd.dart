import 'almacen_seguro.dart';
import 'cripto.dart';

/// La base de datos existe pero su llave no aparece en el almacén seguro.
/// Nunca se crea una base nueva encima: se ofrece restaurar una copia.
class LlavePerdida implements Exception {
  const LlavePerdida();
  @override
  String toString() => 'No se encontró la llave de la base de datos';
}

const kLlaveBD = 'bd.llave';

/// Devuelve la llave (64 caracteres hex = 256 bits) con la que SQLCipher
/// cifra el archivo de la base. Se crea al azar la primera vez.
Future<String> obtenerLlaveBD(AlmacenSeguro almacen, {required bool existeBD}) async {
  final guardada = await almacen.leer(kLlaveBD);
  if (guardada != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(guardada)) return guardada;
  if (existeBD) throw const LlavePerdida();
  final nueva = bytesAleatorios(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await almacen.escribir(kLlaveBD, nueva);
  // Se relee para estar seguros de que quedó guardada antes de cifrar nada.
  if (await almacen.leer(kLlaveBD) != nueva) {
    throw StateError('No se pudo guardar la llave de forma segura');
  }
  return nueva;
}
