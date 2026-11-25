import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import 'datos/repositorio.dart';
import 'respaldo/automaticas.dart';
import 'respaldo/respaldo.dart';
import 'seguridad/pin.dart';

/// Huella / rostro. Interfaz para poder simularla en las pruebas.
abstract class Biometria {
  Future<bool> disponible();
  Future<bool> autenticar(String motivo);
}

class BiometriaSistema implements Biometria {
  final _auth = LocalAuthentication();

  @override
  Future<bool> disponible() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> autenticar(String motivo) async {
    try {
      return await _auth.authenticate(localizedReason: motivo, biometricOnly: true);
    } catch (_) {
      return false; // cancelada, sin huellas, bloqueada por el sistema…
    }
  }
}

class SinBiometria implements Biometria {
  @override
  Future<bool> disponible() async => false;
  @override
  Future<bool> autenticar(String motivo) async => false;
}

/// Activa/desactiva FLAG_SECURE (bloqueo de capturas de pantalla).
class ProteccionPantalla {
  static const _canal = MethodChannel('contabilidad/pantalla');
  Future<void> aplicar(bool activa) async {
    try {
      await _canal.invokeMethod('protegerPantalla', {'activo': activa});
    } on MissingPluginException {
      // En pruebas o en plataformas sin el canal no hay nada que hacer.
    } on PlatformException {
      // idem
    }
  }
}

/// Bloquea la app cuando se sale de ella por más de [tiempo].
class ControlBloqueo extends ChangeNotifier {
  Duration tiempo;
  final DateTime Function() _reloj;
  bool _bloqueado;
  DateTime? _salioEn;
  int _suspendido = 0;

  ControlBloqueo({this.tiempo = const Duration(minutes: 1), bool bloqueado = true, DateTime Function()? reloj})
      // ignore: prefer_initializing_formals (un parámetro con nombre no puede ser privado)
      : _bloqueado = bloqueado,
        _reloj = reloj ?? DateTime.now;

  bool get bloqueado => _bloqueado;

  void bloquear() {
    if (_bloqueado) return;
    _bloqueado = true;
    notifyListeners();
  }

  void desbloquear() {
    _bloqueado = false;
    _salioEn = null;
    notifyListeners();
  }

  void alSalir() {
    if (_suspendido == 0) _salioEn ??= _reloj();
  }

  void alVolver() {
    final s = _salioEn;
    _salioEn = null;
    if (s != null && _reloj().difference(s) >= tiempo) bloquear();
  }

  /// Mientras se elige un archivo o se comparte, salir de la app no bloquea.
  Future<T> sinBloquearMientras<T>(Future<T> Function() accion) async {
    _suspendido++;
    try {
      return await accion();
    } finally {
      _suspendido--;
      _salioEn = null;
    }
  }
}

class Servicios {
  final Repositorio repo;
  final ServicioPin pin;
  final ServicioRespaldo respaldo;
  final CopiasAutomaticas? automaticas;
  final Biometria biometria;
  final ProteccionPantalla pantalla;
  final ControlBloqueo bloqueo;
  final String Function() hoy;

  Servicios({
    required this.repo,
    required this.pin,
    required this.respaldo,
    required this.automaticas,
    required this.biometria,
    required this.pantalla,
    required this.bloqueo,
    required this.hoy,
  });
}

class Alcance extends InheritedWidget {
  final Servicios servicios;
  const Alcance({super.key, required this.servicios, required super.child});

  static Servicios de(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Alcance>()!.servicios;

  @override
  bool updateShouldNotify(Alcance oldWidget) => oldWidget.servicios != servicios;
}

extension AlcanceContexto on BuildContext {
  Servicios get servicios => Alcance.de(this);
}
