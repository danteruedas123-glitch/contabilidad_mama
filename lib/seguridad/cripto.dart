/// Funciones criptográficas usadas por el PIN y las copias de seguridad.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final Random _azar = Random.secure();

Uint8List bytesAleatorios(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _azar.nextInt(256)));

/// PBKDF2-HMAC-SHA256. Se corre en otro hilo (isolate) para que la pantalla
/// no se congele mientras calcula.
Future<Uint8List> derivarClave(String secreto, List<int> sal, int iteraciones, {int bits = 256}) {
  final s = Uint8List.fromList(sal);
  return Isolate.run(() async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iteraciones, bits: bits);
    final k = await pbkdf2.deriveKeyFromPassword(password: secreto, nonce: s);
    return Uint8List.fromList(await k.extractBytes());
  });
}

/// Lo mismo, en el hilo actual (para pruebas con tiempo simulado).
Future<Uint8List> derivarClaveDirecto(String secreto, List<int> sal, int iteraciones, {int bits = 256}) async {
  final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iteraciones, bits: bits);
  final k = await pbkdf2.deriveKeyFromPassword(password: secreto, nonce: sal);
  return Uint8List.fromList(await k.extractBytes());
}

typedef Derivador = Future<Uint8List> Function(String secreto, List<int> sal, int iteraciones);

/// Comparación en tiempo constante (no revela en qué byte difiere).
bool igualesSeguro(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

String b64(List<int> b) => base64Encode(b);
Uint8List deB64(String s) => base64Decode(s);

/// AES-256-GCM: cifra y además detecta cualquier cambio en el archivo.
Future<({Uint8List nonce, Uint8List cifrado})> cifrarAes(List<int> llave, List<int> datos) async {
  final aes = AesGcm.with256bits();
  final nonce = bytesAleatorios(12);
  final caja = await aes.encrypt(datos, secretKey: SecretKey(llave), nonce: nonce);
  return (nonce: nonce, cifrado: Uint8List.fromList(caja.concatenation(nonce: false)));
}

/// Lanza [SecretBoxAuthenticationError] si la llave es otra o el archivo fue alterado.
Future<Uint8List> descifrarAes(List<int> llave, List<int> nonce, List<int> cifradoConMac) async {
  final aes = AesGcm.with256bits();
  if (cifradoConMac.length < 16) throw const FormatException('Archivo incompleto');
  final caja = SecretBox(
    cifradoConMac.sublist(0, cifradoConMac.length - 16),
    nonce: nonce,
    mac: Mac(cifradoConMac.sublist(cifradoConMac.length - 16)),
  );
  return Uint8List.fromList(await aes.decrypt(caja, secretKey: SecretKey(llave)));
}

Future<String> sha256Hex(List<int> datos) async {
  final h = await Sha256().hash(datos);
  return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
