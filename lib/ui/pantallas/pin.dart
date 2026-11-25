import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../seguridad/pin.dart';
import '../../servicios.dart';

/// Teclado numérico grande con puntos que muestran cuántos números van.
class TecladoPin extends StatelessWidget {
  final int largo;
  final bool habilitado;
  final ValueChanged<String> alTocar;
  final VoidCallback alBorrar;
  final VoidCallback? alAceptar;
  final Widget? extraIzquierda;

  const TecladoPin({
    super.key,
    required this.largo,
    required this.alTocar,
    required this.alBorrar,
    this.alAceptar,
    this.habilitado = true,
    this.extraIzquierda,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    Widget tecla(String n) => _Tecla(
          key: ValueKey('tecla-$n'),
          onTap: habilitado ? () => alTocar(n) : null,
          child: Text(n, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500)),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '$largo números escritos',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final lleno = i < largo;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lleno ? esquema.primary : Colors.transparent,
                  border: Border.all(color: i < 4 || lleno ? esquema.primary : esquema.outlineVariant, width: 2),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 28),
        for (final fila in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: fila.map(tecla).toList()),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 84, height: 76, child: Center(child: extraIzquierda)),
            tecla('0'),
            _Tecla(
              key: const ValueKey('tecla-borrar'),
              onTap: habilitado && largo > 0 ? alBorrar : null,
              child: const Icon(Icons.backspace_outlined, size: 28, semanticLabel: 'Borrar'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 260,
          child: FilledButton(
            key: const ValueKey('pin-aceptar'),
            onPressed: habilitado && largo >= 4 ? alAceptar : null,
            child: const Text('Aceptar'),
          ),
        ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _Tecla({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 76,
          height: 68,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap!();
                    },
              child: Center(child: child),
            ),
          ),
        ),
      );
}

String _formatoEspera(Duration d) {
  final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
  if (s < 60) return '$s segundos';
  final m = (s / 60).ceil();
  return '$m minuto${m == 1 ? '' : 's'}';
}

/// Pantalla de bloqueo: tapa todo hasta que se escriba el PIN o la huella.
class PantallaDesbloqueo extends StatefulWidget {
  final VoidCallback alDesbloquear;
  const PantallaDesbloqueo({super.key, required this.alDesbloquear});

  @override
  State<PantallaDesbloqueo> createState() => _PantallaDesbloqueoState();
}

class _PantallaDesbloqueoState extends State<PantallaDesbloqueo> {
  String _pin = '';
  String? _mensaje;
  bool _verificando = false;
  bool _huella = false;
  Duration? _espera;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final s = context.servicios;
    final espera = await s.pin.tiempoBloqueo();
    final huella = await s.pin.huellaActiva() && await s.biometria.disponible();
    if (!mounted) return;
    setState(() => _huella = huella);
    if (espera != null) {
      _empezarEspera(espera);
    } else if (huella) {
      _usarHuella();
    }
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _empezarEspera(Duration d) {
    _reloj?.cancel();
    setState(() => _espera = d);
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      final falta = (_espera ?? Duration.zero) - const Duration(seconds: 1);
      if (!mounted) return t.cancel();
      if (falta <= Duration.zero) {
        t.cancel();
        setState(() {
          _espera = null;
          _mensaje = null;
        });
      } else {
        setState(() => _espera = falta);
      }
    });
  }

  Future<void> _usarHuella() async {
    final ok = await context.servicios.biometria.autenticar('Desbloquear Mis Cuentas');
    if (ok && mounted) widget.alDesbloquear();
  }

  Future<void> _verificar() async {
    if (_verificando) return;
    setState(() => _verificando = true);
    final r = await context.servicios.pin.verificar(_pin);
    if (!mounted) return;
    setState(() {
      _verificando = false;
      _pin = '';
    });
    if (r.ok) {
      widget.alDesbloquear();
    } else if (r.esperar != null) {
      HapticFeedback.heavyImpact();
      setState(() => _mensaje = 'Demasiados intentos.');
      _empezarEspera(r.esperar!);
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _mensaje = r.intentosRestantes > 0
          ? 'PIN incorrecto. Te quedan ${r.intentosRestantes} intento${r.intentosRestantes == 1 ? '' : 's'} antes de esperar.'
          : 'PIN incorrecto.');
    }
  }

  Future<void> _olvide() async {
    final listo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PantallaRecuperar(), fullscreenDialog: true),
    );
    if (listo == true && mounted) widget.alDesbloquear();
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = _espera != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                Icon(Icons.lock_rounded, size: 44, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('Mis Cuentas', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text('Escribe tu PIN', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: Text(
                    bloqueado ? 'Demasiados intentos. Espera ${_formatoEspera(_espera!)}.' : (_mensaje ?? ''),
                    key: const ValueKey('pin-mensaje'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                TecladoPin(
                  largo: _pin.length,
                  habilitado: !bloqueado && !_verificando,
                  alTocar: (n) => setState(() {
                    if (_pin.length < 6) _pin += n;
                    _mensaje = null;
                  }),
                  alBorrar: () => setState(() => _pin = _pin.substring(0, _pin.length - 1)),
                  alAceptar: _verificar,
                  extraIzquierda: _huella
                      ? IconButton(
                          key: const ValueKey('usar-huella'),
                          iconSize: 34,
                          tooltip: 'Usar huella',
                          onPressed: bloqueado ? null : _usarHuella,
                          icon: const Icon(Icons.fingerprint),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _olvide, child: const Text('Olvidé mi PIN')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Crea un PIN nuevo: lo pide dos veces. Devuelve el PIN con Navigator.pop.
class PantallaCrearPin extends StatefulWidget {
  final String titulo;
  const PantallaCrearPin({super.key, this.titulo = 'Crea tu PIN'});

  @override
  State<PantallaCrearPin> createState() => _PantallaCrearPinState();
}

class _PantallaCrearPinState extends State<PantallaCrearPin> {
  String _pin = '';
  String? _primero;
  String? _error;
  bool _guardando = false;

  Future<void> _aceptar() async {
    if (_primero == null) {
      final e = ServicioPin.validarNuevoPin(_pin);
      setState(() {
        if (e != null) {
          _error = e;
        } else {
          _primero = _pin;
          _error = null;
        }
        _pin = '';
      });
      return;
    }
    if (_pin != _primero) {
      setState(() {
        _error = 'No coinciden. Vuelve a empezar.';
        _primero = null;
        _pin = '';
      });
      return;
    }
    setState(() => _guardando = true);
    await context.servicios.pin.configurarPin(_pin);
    if (mounted) Navigator.of(context).pop(_pin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _primero == null ? 'Escribe un PIN de 4 a 6 números' : 'Escríbelo otra vez para confirmar',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Evita tu fecha de nacimiento o números seguidos.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(_error ?? '',
                        key: const ValueKey('pin-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ),
                TecladoPin(
                  largo: _pin.length,
                  habilitado: !_guardando,
                  alTocar: (n) => setState(() {
                    if (_pin.length < 6) _pin += n;
                    _error = null;
                  }),
                  alBorrar: () => setState(() => _pin = _pin.substring(0, _pin.length - 1)),
                  alAceptar: _aceptar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Muestra el código de recuperación una sola vez.
class PantallaCodigoRecuperacion extends StatefulWidget {
  final String codigo;
  const PantallaCodigoRecuperacion({super.key, required this.codigo});

  @override
  State<PantallaCodigoRecuperacion> createState() => _PantallaCodigoRecuperacionState();
}

class _PantallaCodigoRecuperacionState extends State<PantallaCodigoRecuperacion> {
  bool _anotado = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Código de recuperación'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Si algún día olvidas el PIN, con este código puedes poner uno nuevo sin perder tus cuentas.',
                  style: t.titleMedium),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
                  child: SelectableText(
                    widget.codigo,
                    key: const ValueKey('codigo-recuperacion'),
                    textAlign: TextAlign.center,
                    style: t.headlineMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 2, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Anótalo en un papel y guárdalo en un lugar seguro. No se vuelve a mostrar.', style: t.bodyLarge),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey('ya-lo-anote'),
                value: _anotado,
                onChanged: (v) => setState(() => _anotado = v ?? false),
                title: const Text('Ya lo anoté'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('codigo-continuar'),
                onPressed: _anotado ? () => Navigator.of(context).pop() : null,
                child: const Text('Continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Olvidé mi PIN": pide el código de recuperación y luego un PIN nuevo.
class PantallaRecuperar extends StatefulWidget {
  const PantallaRecuperar({super.key});
  @override
  State<PantallaRecuperar> createState() => _PantallaRecuperarState();
}

class _PantallaRecuperarState extends State<PantallaRecuperar> {
  final _codigo = TextEditingController();
  String? _error;
  bool _verificando = false;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    setState(() => _verificando = true);
    final s = context.servicios;
    final r = await s.pin.verificarRecuperacion(_codigo.text);
    if (!mounted) return;
    setState(() => _verificando = false);
    if (!r.ok) {
      setState(() => _error = r.esperar != null
          ? 'Demasiados intentos. Espera ${_formatoEspera(r.esperar!)}.'
          : 'Ese código no es correcto.');
      return;
    }
    final nav = Navigator.of(context);
    final pin = await nav.push<String>(MaterialPageRoute(builder: (_) => const PantallaCrearPin(titulo: 'PIN nuevo')));
    if (pin == null) return;
    final nuevo = await s.pin.generarCodigoRecuperacion();
    await nav.push(MaterialPageRoute(builder: (_) => PantallaCodigoRecuperacion(codigo: nuevo)));
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Olvidé mi PIN')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Escribe el código de recuperación que anotaste cuando creaste el PIN (por ejemplo ABCD-EFGH-JKLM).'),
          const SizedBox(height: 16),
          TextField(
            controller: _codigo,
            textCapitalization: TextCapitalization.characters,
            maxLength: 20,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: 'Código de recuperación', errorText: _error),
            onSubmitted: (_) => _verificar(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _verificando ? null : _verificar, child: const Text('Verificar')),
        ],
      ),
    );
  }
}

/// Primera vez: bienvenida → PIN → código de recuperación → huella.
class PantallaBienvenida extends StatelessWidget {
  final VoidCallback alTerminar;
  const PantallaBienvenida({super.key, required this.alTerminar});

  Future<void> _empezar(BuildContext context) async {
    final s = context.servicios;
    final nav = Navigator.of(context);
    final pin = await nav.push<String>(MaterialPageRoute(builder: (_) => const PantallaCrearPin()));
    if (pin == null) return;
    final codigo = await s.pin.generarCodigoRecuperacion();
    await nav.push(MaterialPageRoute(builder: (_) => PantallaCodigoRecuperacion(codigo: codigo)));
    final hayHuella = await s.biometria.disponible();
    if (hayHuella && context.mounted) {
      final usar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.fingerprint, size: 40),
          title: const Text('¿Entrar con la huella?'),
          content: const Text('Así no tienes que escribir el PIN cada vez. El PIN sigue funcionando.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ahora no')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, usar huella')),
          ],
        ),
      );
      if (usar == true && await s.biometria.autenticar('Confirma tu huella')) {
        await s.pin.activarHuella(true);
      }
    }
    alTerminar();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Icon(Icons.account_balance_wallet_rounded, size: 72, color: esquema.primary),
            const SizedBox(height: 16),
            Text('Mis Cuentas', style: t.headlineLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Lleva la cuenta de lo que entra y lo que sale, día a día.', style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            for (final (icono, texto) in [
              (Icons.lock_rounded, 'Tus cuentas quedan guardadas solo en este celular, cifradas y con PIN.'),
              (Icons.wifi_off_rounded, 'Funciona sin internet. Nada se envía a ningún lado.'),
              (Icons.backup_rounded, 'Puedes guardar copias de seguridad para no perder nada.'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(children: [
                  Icon(icono, color: esquema.primary),
                  const SizedBox(width: 16),
                  Expanded(child: Text(texto, style: t.bodyLarge)),
                ]),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('empezar'),
              onPressed: () => _empezar(context),
              child: const Text('Empezar'),
            ),
          ],
        ),
      ),
    );
  }
}
