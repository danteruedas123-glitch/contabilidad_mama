/// PIN de la app.
///
/// - El PIN nunca se guarda: se guarda su huella PBKDF2 (con sal aleatoria)
///   dentro del almacén seguro del sistema.
/// - Después de 5 intentos fallidos hay que esperar 30 s, luego 1 min, 2 min…
///   hasta 15 min. El contador sobrevive aunque se cierre la app.
/// - Nunca se borran los datos por intentos fallidos: perder la contabilidad
///   sería peor que el riesgo que se evita.
/// - El código de recuperación (se muestra una sola vez) permite poner un PIN
///   nuevo si se olvida el actual.
library;

import 'almacen_seguro.dart';
import 'cripto.dart';

class ResultadoPin {
  final bool ok;
  final Duration? esperar; // si está bloqueado, cuánto falta
  final int intentosRestantes; // antes del próximo bloqueo
  const ResultadoPin._(this.ok, this.esperar, this.intentosRestantes);
  const ResultadoPin.correcto() : this._(true, null, 0);
  const ResultadoPin.incorrecto(int restantes) : this._(false, null, restantes);
  const ResultadoPin.bloqueado(Duration d) : this._(false, d, 0);
}

class ServicioPin {
  static const kHash = 'pin.hash';
  static const kSal = 'pin.sal';
  static const kIter = 'pin.iter';
  static const kFallos = 'pin.fallos';
  static const kHasta = 'pin.bloqueado_hasta';
  static const kRecHash = 'rec.hash';
  static const kRecSal = 'rec.sal';
  static const kRecIter = 'rec.iter';
  static const kBio = 'bio.activa';

  static const intentosLibres = 5;
  static const esperaInicial = Duration(seconds: 30);
  static const esperaMaxima = Duration(minutes: 15);

  final AlmacenSeguro almacen;
  final int iteraciones;
  final DateTime Function() _reloj;
  final Derivador _derivar;

  ServicioPin(this.almacen, {this.iteraciones = 30000, DateTime Function()? reloj, Derivador? derivar})
      : _reloj = reloj ?? DateTime.now,
        _derivar = derivar ?? ((s, sal, it) => derivarClave(s, sal, it));

  Future<bool> tienePin() async => (await almacen.leer(kHash)) != null;

  /// Devuelve un mensaje si el PIN no sirve, o null si está bien.
  static String? validarNuevoPin(String pin) {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return 'El PIN debe tener de 4 a 6 números';
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return 'Ese PIN es muy fácil de adivinar (todos iguales)';
    const sube = '01234567890';
    const baja = '09876543210';
    if (sube.contains(pin) || baja.contains(pin)) return 'Ese PIN es muy fácil de adivinar (números seguidos)';
    return null;
  }

  Future<void> configurarPin(String pin) async {
    final error = validarNuevoPin(pin);
    if (error != null) throw ArgumentError(error);
    final sal = bytesAleatorios(16);
    final hash = await _derivar(pin, sal, iteraciones);
    await almacen.escribir(kSal, b64(sal));
    await almacen.escribir(kIter, '$iteraciones');
    await almacen.escribir(kHash, b64(hash));
    await _reiniciarFallos();
  }

  Future<Duration?> tiempoBloqueo() async {
    final hasta = int.tryParse(await almacen.leer(kHasta) ?? '');
    if (hasta == null) return null;
    final falta = DateTime.fromMillisecondsSinceEpoch(hasta).difference(_reloj());
    // Si alguien atrasa el reloj del celular para saltarse la espera, la
    // espera no puede ser mayor que la máxima: se recorta y se mantiene.
    if (falta > esperaMaxima) {
      await almacen.escribir(kHasta, '${_reloj().add(esperaMaxima).millisecondsSinceEpoch}');
      return esperaMaxima;
    }
    return falta.isNegative || falta == Duration.zero ? null : falta;
  }

  Future<ResultadoPin> verificar(String pin) async {
    final espera = await tiempoBloqueo();
    if (espera != null) return ResultadoPin.bloqueado(espera);

    final hashGuardado = await almacen.leer(kHash);
    final sal = await almacen.leer(kSal);
    final iter = int.tryParse(await almacen.leer(kIter) ?? '');
    if (hashGuardado == null || sal == null || iter == null) return const ResultadoPin.incorrecto(0);

    // Mismo trabajo aunque el formato sea raro: no se revela nada por tiempo.
    final entrada = pin.length > 12 ? pin.substring(0, 12) : pin;
    final calculado = await _derivar(entrada, deB64(sal), iter);
    if (RegExp(r'^\d{4,6}$').hasMatch(pin) && igualesSeguro(calculado, deB64(hashGuardado))) {
      await _reiniciarFallos();
      return const ResultadoPin.correcto();
    }
    return _registrarFallo();
  }

  Future<ResultadoPin> _registrarFallo() async {
    final fallos = (int.tryParse(await almacen.leer(kFallos) ?? '') ?? 0) + 1;
    await almacen.escribir(kFallos, '$fallos');
    if (fallos >= intentosLibres) {
      final extra = fallos - intentosLibres; // 0, 1, 2...
      var espera = esperaInicial * (1 << extra.clamp(0, 10));
      if (espera > esperaMaxima) espera = esperaMaxima;
      await almacen.escribir(kHasta, '${_reloj().add(espera).millisecondsSinceEpoch}');
      return ResultadoPin.bloqueado(espera);
    }
    return ResultadoPin.incorrecto(intentosLibres - fallos);
  }

  Future<void> _reiniciarFallos() async {
    await almacen.borrar(kFallos);
    await almacen.borrar(kHasta);
  }

  // ------------------------------------------------------------ recuperación

  static const _alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0/O ni 1/I

  /// Crea un código nuevo (reemplaza el anterior) y lo devuelve UNA sola vez.
  Future<String> generarCodigoRecuperacion() async {
    final b = bytesAleatorios(12);
    final crudo = String.fromCharCodes(b.map((x) => _alfabeto.codeUnitAt(x % _alfabeto.length)));
    final codigo = '${crudo.substring(0, 4)}-${crudo.substring(4, 8)}-${crudo.substring(8, 12)}';
    final sal = bytesAleatorios(16);
    final hash = await _derivar(_normalizarCodigo(codigo), sal, iteraciones);
    await almacen.escribir(kRecSal, b64(sal));
    await almacen.escribir(kRecIter, '$iteraciones');
    await almacen.escribir(kRecHash, b64(hash));
    return codigo;
  }

  static String _normalizarCodigo(String c) =>
      c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').replaceAll('O', '0').replaceAll('I', '1');

  /// Verifica el código de recuperación (con el mismo límite de intentos).
  Future<ResultadoPin> verificarRecuperacion(String codigo) async {
    final espera = await tiempoBloqueo();
    if (espera != null) return ResultadoPin.bloqueado(espera);
    final hash = await almacen.leer(kRecHash);
    final sal = await almacen.leer(kRecSal);
    if (hash == null || sal == null) return _registrarFallo();
    final normal = _normalizarCodigo(codigo.length > 40 ? codigo.substring(0, 40) : codigo);
    final iter = int.tryParse(await almacen.leer(kRecIter) ?? '') ?? iteraciones;
    final calc = await _derivar(normal, deB64(sal), iter);
    if (normal.length == 12 && igualesSeguro(calc, deB64(hash))) {
      await _reiniciarFallos();
      return const ResultadoPin.correcto();
    }
    return _registrarFallo();
  }

  // ------------------------------------------------------------ huella

  Future<bool> huellaActiva() async => (await almacen.leer(kBio)) == '1';
  Future<void> activarHuella(bool activa) => activa ? almacen.escribir(kBio, '1') : almacen.borrar(kBio);

  /// Solo para diagnóstico en pruebas: nunca expone el PIN.
  Future<Map<String, String>> estadoPublico() async => {
        'tienePin': '${await tienePin()}',
        'fallos': await almacen.leer(kFallos) ?? '0',
      };
}
