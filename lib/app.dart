import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'servicios.dart';
import 'ui/pantallas/inicio.dart';
import 'ui/pantallas/pin.dart';
import 'ui/tema.dart';

/// La app ya con sus servicios listos. Las pruebas la crean con servicios en
/// memoria; main.dart con la base cifrada y el Keystore.
class AppMisCuentas extends StatefulWidget {
  final Servicios servicios;
  final bool tienePin;
  const AppMisCuentas({super.key, required this.servicios, required this.tienePin});

  @override
  State<AppMisCuentas> createState() => _AppMisCuentasState();
}

class _AppMisCuentasState extends State<AppMisCuentas> with WidgetsBindingObserver {
  late bool _tienePin = widget.tienePin;
  ControlBloqueo get _bloqueo => widget.servicios.bloqueo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloqueo.addListener(_refrescar);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloqueo.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_tienePin) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _bloqueo.alSalir();
      case AppLifecycleState.resumed:
        _bloqueo.alVolver();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = _tienePin && _bloqueo.bloqueado;
    return Alcance(
      servicios: widget.servicios,
      child: MaterialApp(
        title: 'Mis Cuentas',
        debugShowCheckedModeBanner: false,
        theme: temaApp(Brightness.light),
        darkTheme: temaApp(Brightness.dark),
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: _tienePin
            ? const PantallaInicio()
            : PantallaBienvenida(alTerminar: () {
                _bloqueo.desbloquear();
                setState(() => _tienePin = true);
              }),
        // La pantalla de bloqueo TAPA la app (sin cerrarla): si mamá estaba
        // anotando algo, al desbloquear sigue donde iba.
        builder: (context, child) => Stack(children: [
          ExcludeSemantics(
            excluding: bloqueado,
            child: TickerMode(enabled: !bloqueado, child: Offstage(offstage: bloqueado, child: child!)),
          ),
          if (bloqueado)
            HeroControllerScope.none(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => PantallaDesbloqueo(alDesbloquear: _bloqueo.desbloquear),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
