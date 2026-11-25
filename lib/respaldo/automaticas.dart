/// Copias automáticas dentro del celular (carpeta privada de la app).
///
/// Se hace una al abrir la app si la última tiene más de un día, y otra justo
/// antes de restaurar una copia. Se guardan las últimas 7. Van cifradas con
/// una contraseña aleatoria de 256 bits que vive en el Keystore.
///
/// Protegen contra errores (restaurar la copia equivocada, borrar algo); para
/// protegerse de perder o dañar el celular están las copias que mamá guarda
/// afuera (Drive, WhatsApp, correo).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../seguridad/almacen_seguro.dart';
import '../seguridad/cripto.dart';
import 'respaldo.dart';

class CopiaAutomatica {
  final File archivo;
  final DateTime fecha;
  const CopiaAutomatica(this.archivo, this.fecha);
}

class CopiasAutomaticas {
  static const kClave = 'auto.clave';
  static const maximo = 7;
  static final _nombre = RegExp(r'^auto-(\d{8}T\d{6})\.cmama$');

  final ServicioRespaldo respaldo;
  final AlmacenSeguro almacen;
  final Directory carpeta;
  final DateTime Function() _reloj;

  CopiasAutomaticas(this.respaldo, this.almacen, this.carpeta, {DateTime Function()? reloj})
      : _reloj = reloj ?? DateTime.now;

  Future<String> _clave() async {
    final guardada = await almacen.leer(kClave);
    if (guardada != null && guardada.length == 64) return guardada;
    final nueva = bytesAleatorios(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await almacen.escribir(kClave, nueva);
    return nueva;
  }

  Future<List<CopiaAutomatica>> listar() async {
    if (!carpeta.existsSync()) return [];
    final lista = <CopiaAutomatica>[];
    for (final f in carpeta.listSync().whereType<File>()) {
      final m = _nombre.firstMatch(p.basename(f.path));
      if (m == null) continue;
      final t = m[1]!;
      final fecha = DateTime.tryParse('${t.substring(0, 8)}T${t.substring(9)}');
      if (fecha != null) lista.add(CopiaAutomatica(f, fecha));
    }
    lista.sort((a, b) => b.fecha.compareTo(a.fecha));
    return lista;
  }

  /// Hace una copia ahora y borra las más viejas (deja [maximo]).
  Future<CopiaAutomatica> crear() async {
    carpeta.createSync(recursive: true);
    final ahora = _reloj();
    String dos(int n) => n.toString().padLeft(2, '0');
    final sello = '${ahora.year}${dos(ahora.month)}${dos(ahora.day)}T${dos(ahora.hour)}${dos(ahora.minute)}${dos(ahora.second)}';
    final bytes = await respaldo.crear(await _clave(), ahora: ahora);
    final destino = File(p.join(carpeta.path, 'auto-$sello.cmama'));
    // Se escribe a un temporal y luego se renombra: si el celular se apaga a
    // mitad de camino, nunca queda una copia a medias con el nombre bueno.
    final temporal = File('${destino.path}.tmp');
    await temporal.writeAsBytes(bytes, flush: true);
    await temporal.rename(destino.path);
    final todas = await listar();
    for (final vieja in todas.skip(maximo)) {
      try {
        vieja.archivo.deleteSync();
      } catch (_) {}
    }
    return CopiaAutomatica(destino, ahora);
  }

  /// Copia diaria: solo si la última tiene más de [cada] (por defecto un día).
  Future<bool> crearSiHaceFalta({Duration cada = const Duration(days: 1)}) async {
    if (await respaldo.repo.totalMovimientos() == 0) return false;
    final ultima = (await listar()).firstOrNull;
    if (ultima != null && _reloj().difference(ultima.fecha) < cada) return false;
    await crear();
    return true;
  }

  Future<ResumenRespaldo> leer(CopiaAutomatica c) async =>
      (await respaldo.leer(await c.archivo.readAsBytes(), await _clave())).resumen;

  /// Vuelve a una copia automática (antes guarda el estado actual).
  Future<ResumenRespaldo> restaurar(CopiaAutomatica c) async {
    final bytes = await c.archivo.readAsBytes();
    final clave = await _clave();
    await respaldo.leer(bytes, clave); // valida antes de tocar nada
    await crear();
    return respaldo.restaurar(bytes, clave);
  }
}
