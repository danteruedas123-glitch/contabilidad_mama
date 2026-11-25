import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dinero.dart';
import '../../core/fechas.dart';
import '../../datos/modelos.dart';
import '../../respaldo/automaticas.dart';
import '../../respaldo/csv.dart';
import '../../respaldo/respaldo.dart';
import '../../servicios.dart';
import '../widgets/comunes.dart';
import 'categorias.dart';
import 'pin.dart';

/// Pide el PIN actual antes de algo delicado. Devuelve true si es correcto.
Future<bool> pedirPin(BuildContext context, {String titulo = 'Escribe tu PIN'}) async {
  final ctrl = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          key: const ValueKey('pedir-pin'),
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: 'PIN', errorText: error, counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final r = await context.servicios.pin.verificar(ctrl.text);
              if (r.ok) {
                if (c.mounted) Navigator.pop(c, true);
              } else {
                setState(() => error = r.esperar != null ? 'Demasiados intentos. Espera un momento.' : 'PIN incorrecto');
              }
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return ok ?? false;
}

class PantallaAjustes extends StatefulWidget {
  const PantallaAjustes({super.key});
  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> {
  bool? _huella;
  bool _hayHuella = false;
  bool _proteger = true;
  int _bloqueo = 60;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_huella == null) _cargar();
  }

  Future<void> _cargar() async {
    final s = context.servicios;
    final huella = await s.pin.huellaActiva();
    final hay = await s.biometria.disponible();
    final proteger = await s.repo.ajuste('proteger_pantalla') != '0';
    final bloqueo = int.tryParse(await s.repo.ajuste('bloqueo_segundos') ?? '') ?? 60;
    if (mounted) {
      setState(() {
        _huella = huella;
        _hayHuella = hay;
        _proteger = proteger;
        _bloqueo = bloqueo;
      });
    }
  }

  Future<void> _cambiarPin() async {
    if (!await pedirPin(context, titulo: 'Escribe tu PIN actual') || !mounted) return;
    final nuevo = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const PantallaCrearPin(titulo: 'PIN nuevo')));
    if (nuevo != null && mounted) avisar(context, 'PIN cambiado');
  }

  Future<void> _nuevoCodigo() async {
    if (!await pedirPin(context) || !mounted) return;
    final codigo = await context.servicios.pin.generarCodigoRecuperacion();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaCodigoRecuperacion(codigo: codigo)));
  }

  Future<void> _cambiarHuella(bool v) async {
    final s = context.servicios;
    if (v && !await s.biometria.autenticar('Confirma tu huella')) return;
    await s.pin.activarHuella(v);
    setState(() => _huella = v);
  }

  Future<void> _cambiarProteger(bool v) async {
    final s = context.servicios;
    await s.repo.guardarAjuste('proteger_pantalla', v ? '1' : '0');
    await s.pantalla.aplicar(v);
    setState(() => _proteger = v);
  }

  Future<void> _cambiarBloqueo(int? seg) async {
    if (seg == null) return;
    final s = context.servicios;
    await s.repo.guardarAjuste('bloqueo_segundos', '$seg');
    s.bloqueo.tiempo = Duration(seconds: seg);
    setState(() => _bloqueo = seg);
  }

  Future<void> _exportar() async {
    final s = context.servicios;
    final hoyT = s.hoy();
    final opcion = await showModalBottomSheet<Periodo?>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('¿Qué quieres exportar a Excel?')),
          ListTile(title: const Text('Este mes'), onTap: () => Navigator.pop(c, Periodo.de(TipoPeriodo.mes, hoyT))),
          ListTile(title: const Text('El mes pasado'), onTap: () => Navigator.pop(c, Periodo.de(TipoPeriodo.mes, hoyT).mover(-1))),
          ListTile(title: const Text('Este año'), onTap: () => Navigator.pop(c, Periodo.de(TipoPeriodo.anio, hoyT))),
          ListTile(title: const Text('Todo'), onTap: () => Navigator.pop(c, Periodo.rango('2000-01-01', '${int.parse(hoyT.substring(0, 4)) + 1}-12-31'))),
        ]),
      ),
    );
    if (opcion == null || !mounted) return;
    final movs = await s.repo.movimientos(opcion, limite: 20000);
    final cats = {for (final c in await s.repo.categorias(incluirArchivadas: true)) c.id!: c};
    final clientes = {for (final c in await s.repo.clientes(incluirArchivados: true)) c.id!: c};
    final bytes = Uint8List.fromList(generarCsv(movs.reversed.toList(), cats, clientes: clientes));
    if (!mounted) return;
    await compartirArchivo(context, 'MisCuentas_${opcion.desde}_a_${opcion.hasta}.csv', bytes, 'text/csv',
        aviso: 'El archivo de Excel NO va cifrado: compártelo solo con quien confíes.');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget titulo(String s) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(s, style: t.titleSmall));
    void ir(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(children: [
        titulo('Tus datos'),
        ListTile(
          leading: const Icon(Icons.backup_rounded),
          title: const Text('Copias de seguridad'),
          subtitle: const Text('Guardar o recuperar todas tus cuentas'),
          onTap: () => ir(const PantallaCopias()),
        ),
        ListTile(
          leading: const Icon(Icons.table_view_rounded),
          title: const Text('Exportar a Excel'),
          subtitle: const Text('Para verlo en el computador'),
          onTap: _exportar,
        ),
        ListTile(leading: const Icon(Icons.category_rounded), title: const Text('Categorías'), onTap: () => ir(const PantallaCategorias())),
        ListTile(
          key: const ValueKey('abrir-papelera'),
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text('Papelera'),
          subtitle: const Text('Lo que borraste, por si lo necesitas'),
          onTap: () => ir(const PantallaPapelera()),
        ),
        titulo('Seguridad'),
        ListTile(leading: const Icon(Icons.pin_rounded), title: const Text('Cambiar PIN'), onTap: _cambiarPin),
        if (_hayHuella)
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Entrar con huella'),
            value: _huella ?? false,
            onChanged: _cambiarHuella,
          ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Pedir el PIN al volver a la app'),
          trailing: DropdownButton<int>(
            value: const [0, 60, 300].contains(_bloqueo) ? _bloqueo : 60,
            underline: const SizedBox.shrink(),
            onChanged: _cambiarBloqueo,
            items: const [
              DropdownMenuItem(value: 0, child: Text('De una')),
              DropdownMenuItem(value: 60, child: Text('Tras 1 min')),
              DropdownMenuItem(value: 300, child: Text('Tras 5 min')),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.screenshot_monitor_rounded),
          title: const Text('Ocultar pantalla'),
          subtitle: const Text('No deja tomar capturas y tapa las cuentas en "apps recientes"'),
          value: _proteger,
          onChanged: _cambiarProteger,
        ),
        ListTile(
          leading: const Icon(Icons.key_rounded),
          title: const Text('Nuevo código de recuperación'),
          subtitle: const Text('Si perdiste el papel donde lo anotaste'),
          onTap: _nuevoCodigo,
        ),
        titulo('Acerca de'),
        const ListTile(
          leading: Icon(Icons.wifi_off_rounded),
          title: Text('Funciona sin internet'),
          subtitle: Text('Tus cuentas están cifradas y guardadas solo en este celular. Nada se envía a ningún lado.'),
        ),
        const ListTile(leading: Icon(Icons.info_outline), title: Text('Mis Cuentas'), subtitle: Text('Versión 1.1.0 · Pesos colombianos (COP)')),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Comparte un archivo (WhatsApp, Drive, correo) o lo guarda en el celular.
Future<void> compartirArchivo(BuildContext context, String nombre, Uint8List bytes, String tipo, {String? aviso}) async {
  final s = context.servicios;
  final donde = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (aviso != null) ListTile(leading: const Icon(Icons.info_outline), title: Text(aviso)),
        ListTile(
          leading: const Icon(Icons.share_rounded),
          title: const Text('Enviar o subir'),
          subtitle: const Text('Google Drive, WhatsApp, correo…'),
          onTap: () => Navigator.pop(c, 'compartir'),
        ),
        ListTile(
          leading: const Icon(Icons.save_alt_rounded),
          title: const Text('Guardar en el celular'),
          subtitle: const Text('Elige una carpeta (por ejemplo Descargas)'),
          onTap: () => Navigator.pop(c, 'guardar'),
        ),
      ]),
    ),
  );
  if (donde == null) return;
  try {
    if (donde == 'guardar') {
      final uri = await s.bloqueo.sinBloquearMientras(() => FilePicker.saveFile(fileName: nombre, bytes: bytes));
      if (uri != null && context.mounted) avisar(context, 'Archivo guardado');
      return;
    }
    final dir = await getTemporaryDirectory();
    final archivo = File(p.join(dir.path, nombre));
    await archivo.writeAsBytes(bytes, flush: true);
    try {
      await s.bloqueo.sinBloquearMientras(
        () => SharePlus.instance.share(ShareParams(files: [XFile(archivo.path, mimeType: tipo)], subject: nombre)),
      );
    } finally {
      // El temporal se borra apenas se comparte: no queda nada suelto.
      if (archivo.existsSync()) archivo.deleteSync();
    }
  } catch (e) {
    if (context.mounted) avisar(context, 'No se pudo: ${e.runtimeType}');
  }
}

class PantallaCopias extends StatefulWidget {
  const PantallaCopias({super.key});
  @override
  State<PantallaCopias> createState() => _PantallaCopiasState();
}

class _PantallaCopiasState extends State<PantallaCopias> {
  List<CopiaAutomatica> _auto = [];
  String? _ultima;
  bool _trabajando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cargar();
  }

  Future<void> _cargar() async {
    final s = context.servicios;
    final auto = await s.automaticas?.listar() ?? [];
    final ultima = await s.repo.ajuste('ultima_copia');
    if (mounted) {
      setState(() {
        _auto = auto;
        _ultima = ultima;
      });
    }
  }

  Future<String?> _pedirClave({required bool nueva}) async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? error;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(nueva ? 'Contraseña de la copia' : 'Contraseña de la copia'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(nueva
                  ? 'La copia va cifrada. Sin esta contraseña nadie puede abrirla, ni tú: anótala junto al código de recuperación.'
                  : 'Escribe la contraseña que pusiste cuando hiciste la copia.'),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('clave-copia'),
                controller: a,
                obscureText: true,
                autofocus: true,
                maxLength: 100,
                decoration: InputDecoration(labelText: 'Contraseña (mínimo 6)', errorText: error, counterText: ''),
              ),
              if (nueva)
                TextField(
                  key: const ValueKey('clave-copia-2'),
                  controller: b,
                  obscureText: true,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Repítela', counterText: ''),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final e = nueva ? validarClaveRespaldo(a.text) : (a.text.isEmpty ? 'Escribe la contraseña' : null);
                if (e != null) return setState(() => error = e);
                if (nueva && a.text != b.text) return setState(() => error = 'No coinciden');
                Navigator.pop(c, a.text);
              },
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
    a.dispose();
    b.dispose();
    return r;
  }

  Future<void> _guardarCopia() async {
    final clave = await _pedirClave(nueva: true);
    if (clave == null || !mounted) return;
    final s = context.servicios;
    setState(() => _trabajando = true);
    try {
      final bytes = await s.respaldo.crear(clave);
      if (!mounted) return;
      final nombre = 'MisCuentas_${s.hoy()}.cmama';
      await compartirArchivo(context, nombre, bytes, 'application/octet-stream');
      await s.repo.guardarAjuste('ultima_copia', DateTime.now().toIso8601String());
      s.repo.avisarCambio();
    } on ErrorRespaldo catch (e) {
      if (mounted) avisar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _trabajando = false);
      _cargar();
    }
  }

  Future<bool> _confirmarReemplazo(ResumenRespaldo r) => confirmar(
        context,
        titulo: '¿Reemplazar todo?',
        texto: 'La copia tiene ${r.movimientos} movimientos '
            '(entró ${formatearCOP(r.ingresos)}, salió ${formatearCOP(r.egresos)}).\n\n'
            'Todo lo que hay ahora en la app se reemplaza por la copia. '
            'Antes se guarda una copia automática de lo actual, por si te arrepientes.',
        si: 'Reemplazar',
        peligro: true,
      );

  Future<void> _restaurarArchivo() async {
    final s = context.servicios;
    final archivo = await s.bloqueo.sinBloquearMientras(() => FilePicker.pickFile());
    if (archivo == null || !mounted) return;
    if (await archivo.xFile.length() > tamanoMaximoRespaldo) {
      if (mounted) avisar(context, 'Ese archivo es demasiado grande para ser una copia');
      return;
    }
    final bytes = await archivo.xFile.readAsBytes();
    final clave = await _pedirClave(nueva: false);
    if (clave == null || !mounted) return;
    setState(() => _trabajando = true);
    try {
      final leido = await s.respaldo.leer(bytes, clave);
      if (!mounted || !await _confirmarReemplazo(leido.resumen)) return;
      await s.automaticas?.crear();
      await s.respaldo.restaurar(bytes, clave);
      if (mounted) avisar(context, 'Listo: se recuperaron ${leido.resumen.movimientos} movimientos');
    } on ErrorRespaldo catch (e) {
      if (mounted) avisar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _trabajando = false);
      _cargar();
    }
  }

  Future<void> _restaurarAuto(CopiaAutomatica c) async {
    final auto = context.servicios.automaticas!;
    setState(() => _trabajando = true);
    try {
      final r = await auto.leer(c);
      if (!mounted || !await _confirmarReemplazo(r)) return;
      await auto.restaurar(c);
      if (mounted) avisar(context, 'Listo: volviste a la copia del ${_fechaHora(c.fecha)}');
    } on ErrorRespaldo catch (e) {
      if (mounted) avisar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _trabajando = false);
      _cargar();
    }
  }

  String _fechaHora(DateTime d) =>
      '${fechaCorta(aTexto(d))} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ultima = DateTime.tryParse(_ultima ?? '');
    return Scaffold(
      appBar: AppBar(title: const Text('Copias de seguridad')),
      body: AbsorbPointer(
        absorbing: _trabajando,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_trabajando) const LinearProgressIndicator(),
          Text('Si se pierde, se roba o se daña el celular, con una copia guardada afuera (en tu Google Drive o en tu WhatsApp) recuperas todo en un celular nuevo.',
              style: t.bodyLarge),
          const SizedBox(height: 8),
          Text(ultima == null ? 'Todavía no has guardado ninguna copia.' : 'Última copia: ${_fechaHora(ultima.toLocal())}',
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _guardarCopia, icon: const Icon(Icons.backup_rounded), label: const Text('Guardar una copia')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
            onPressed: _restaurarArchivo,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Recuperar desde una copia'),
          ),
          const SizedBox(height: 28),
          Text('Copias automáticas en este celular', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Se hace una al día. Sirven si borraste algo por error; no sirven si se pierde el celular.', style: t.bodySmall),
          if (_auto.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aún no hay copias automáticas.')),
          for (final c in _auto)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(_fechaHora(c.fecha)),
              trailing: TextButton(onPressed: () => _restaurarAuto(c), child: const Text('Volver a esta')),
            ),
        ]),
      ),
    );
  }
}

class PantallaPapelera extends StatefulWidget {
  const PantallaPapelera({super.key});
  @override
  State<PantallaPapelera> createState() => _PantallaPapeleraState();
}

class _PantallaPapeleraState extends State<PantallaPapelera> {
  List<Movimiento>? _movs;
  Map<int, Categoria> _cats = {};
  Map<int, Cliente> _clientes = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cargar();
  }

  Future<void> _cargar() async {
    final repo = context.servicios.repo;
    final movs = await repo.papelera();
    final cats = {for (final c in await repo.categorias(incluirArchivadas: true)) c.id!: c};
    final clientes = {for (final c in await repo.clientes(incluirArchivados: true)) c.id!: c};
    if (mounted) {
      setState(() {
        _movs = movs;
        _cats = cats;
        _clientes = clientes;
      });
    }
  }

  Future<void> _opciones(Movimiento m) async {
    final repo = context.servicios.repo;
    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('recuperar'),
            leading: const Icon(Icons.restore_rounded),
            title: const Text('Recuperar'),
            onTap: () => Navigator.pop(c, 'recuperar'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Borrar para siempre'),
            onTap: () => Navigator.pop(c, 'borrar'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (accion == 'recuperar') {
      await repo.restaurarMovimiento(m.id!);
      if (mounted) avisar(context, 'Recuperado');
    } else if (accion == 'borrar' &&
        await confirmar(context, titulo: '¿Borrar para siempre?', texto: 'No se podrá recuperar.', si: 'Borrar', peligro: true)) {
      await repo.eliminarDefinitivo(m.id!);
    }
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final movs = _movs;
    return Scaffold(
      appBar: AppBar(title: const Text('Papelera'), actions: [
        if (movs != null && movs.isNotEmpty)
          TextButton(
            onPressed: () async {
              if (await confirmar(context,
                  titulo: '¿Vaciar la papelera?', texto: 'Se borran para siempre ${movs.length} movimientos.', si: 'Vaciar', peligro: true)) {
                if (!context.mounted) return;
                await context.servicios.repo.vaciarPapelera();
                _cargar();
              }
            },
            child: const Text('Vaciar'),
          ),
      ]),
      body: movs == null
          ? const Center(child: CircularProgressIndicator())
          : movs.isEmpty
              ? const Vacio(icono: Icons.delete_outline_rounded, texto: 'La papelera está vacía.')
              : ListView.builder(
                  itemCount: movs.length,
                  itemBuilder: (c, i) => FilaMovimiento(m: movs[i], categoria: _cats[movs[i].categoriaId], cliente: _clientes[movs[i].clienteId], mostrarFecha: true, onTap: () => _opciones(movs[i])),
                ),
    );
  }
}
