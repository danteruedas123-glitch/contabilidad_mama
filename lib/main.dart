import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/fechas.dart';
import 'datos/abrir_bd.dart';
import 'datos/repositorio.dart';
import 'respaldo/automaticas.dart';
import 'respaldo/respaldo.dart';
import 'seguridad/almacen_seguro.dart';
import 'seguridad/llave_bd.dart';
import 'seguridad/pin.dart';
import 'servicios.dart';
import 'ui/tema.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Arranque());
}

class _Listo {
  final Servicios servicios;
  final bool tienePin;
  const _Listo(this.servicios, this.tienePin);
}

/// Abre la base cifrada y prepara todo. Si algo falla, lo explica sin borrar nada.
class Arranque extends StatefulWidget {
  const Arranque({super.key});
  @override
  State<Arranque> createState() => _ArranqueState();
}

class _ArranqueState extends State<Arranque> {
  late Future<_Listo> _futuro = _iniciar();

  Future<_Listo> _iniciar() async {
    final almacen = AlmacenKeystore();
    final db = await abrirBDCifrada(almacen);
    final repo = Repositorio(db);
    final pin = ServicioPin(almacen);
    final respaldo = ServicioRespaldo(repo);
    final soporte = await getApplicationSupportDirectory();
    final automaticas = CopiasAutomaticas(respaldo, almacen, Directory(p.join(soporte.path, 'copias')));
    final pantalla = ProteccionPantalla();
    await pantalla.aplicar(await repo.ajuste('proteger_pantalla') != '0');
    final segundos = int.tryParse(await repo.ajuste('bloqueo_segundos') ?? '') ?? 60;
    final tienePin = await pin.tienePin();

    // Copia automática del día, sin hacer esperar a nadie.
    unawaited(automaticas.crearSiHaceFalta().catchError((_) => false));

    return _Listo(
      Servicios(
        repo: repo,
        pin: pin,
        respaldo: respaldo,
        automaticas: automaticas,
        biometria: BiometriaSistema(),
        pantalla: pantalla,
        bloqueo: ControlBloqueo(tiempo: Duration(seconds: segundos), bloqueado: tienePin),
        hoy: hoy,
      ),
      tienePin,
    );
  }

  /// La llave no aparece (pasa muy rara vez, p. ej. tras restaurar el
  /// celular de fábrica a medias). El archivo viejo NO se borra: se aparta
  /// con otro nombre y se empieza una base nueva para restaurar una copia.
  Future<void> _empezarDeNuevo() async {
    final ruta = await rutaBD();
    final viejo = File(ruta);
    if (viejo.existsSync()) {
      await viejo.rename('$ruta.ilegible-${DateTime.now().millisecondsSinceEpoch}');
    }
    setState(() => _futuro = _iniciar());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Listo>(
      future: _futuro,
      builder: (context, s) {
        if (s.hasData) return AppMisCuentas(servicios: s.data!.servicios, tienePin: s.data!.tienePin);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaApp(Brightness.light),
          darkTheme: temaApp(Brightness.dark),
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: s.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline, size: 56),
                          const SizedBox(height: 12),
                          Text(
                            s.error is LlavePerdida
                                ? 'No se pudo abrir la información guardada (falta su llave de seguridad).\n\n'
                                    'Puedes empezar de nuevo y luego recuperar tus cuentas desde una copia de seguridad '
                                    '(Ajustes → Copias de seguridad). El archivo anterior no se borra.'
                                : 'No se pudo abrir la app. Intenta de nuevo.\n(${s.error.runtimeType})',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          if (s.error is LlavePerdida)
                            FilledButton(onPressed: _empezarDeNuevo, child: const Text('Empezar de nuevo'))
                          else
                            FilledButton(onPressed: () => setState(() => _futuro = _iniciar()), child: const Text('Reintentar')),
                        ]),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        );
      },
    );
  }
}
