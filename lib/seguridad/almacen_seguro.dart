import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lugar seguro para secretos pequeños (llave de la base, huella del PIN).
/// En Android vive en el Keystore del sistema: otra app no lo puede leer y
/// no sale del celular en copias de seguridad (allowBackup=false).
abstract class AlmacenSeguro {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrar(String clave);
}

class AlmacenKeystore implements AlmacenSeguro {
  final FlutterSecureStorage _s;
  AlmacenKeystore() : _s = const FlutterSecureStorage();

  @override
  Future<String?> leer(String clave) => _s.read(key: clave);
  @override
  Future<void> escribir(String clave, String valor) => _s.write(key: clave, value: valor);
  @override
  Future<void> borrar(String clave) => _s.delete(key: clave);
}

/// Para pruebas: guarda en memoria.
class AlmacenMemoria implements AlmacenSeguro {
  final Map<String, String> datos = {};
  @override
  Future<String?> leer(String clave) async => datos[clave];
  @override
  Future<void> escribir(String clave, String valor) async => datos[clave] = valor;
  @override
  Future<void> borrar(String clave) async => datos.remove(clave);
}
