import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dinero.dart';
import '../../core/fechas.dart';
import '../../datos/modelos.dart';
import '../../datos/repositorio.dart';
import '../../servicios.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import 'movimiento.dart';

/// Inicial(es) del cliente para su círculo: "Doña Rosa" → "DR".
String iniciales(String nombre) {
  final partes = limpiarNombre(nombre).split(' ').where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  final a = partes.first.characters.first;
  final b = partes.length > 1 ? partes[1].characters.first : '';
  return (a + b).toUpperCase();
}

class AvatarCliente extends StatelessWidget {
  final Cliente cliente;
  final double radio;
  const AvatarCliente(this.cliente, {super.key, this.radio = 22});

  @override
  Widget build(BuildContext context) {
    final e = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radio,
      backgroundColor: e.secondaryContainer,
      child: Text(iniciales(cliente.nombre),
          style: TextStyle(color: e.onSecondaryContainer, fontWeight: FontWeight.bold, fontSize: radio * 0.7)),
    );
  }
}

/// Crea o edita un cliente. Devuelve el cliente guardado o null.
Future<Cliente?> editarCliente(BuildContext context, {Cliente? existente}) => showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditorCliente(existente: existente),
    );

class _EditorCliente extends StatefulWidget {
  final Cliente? existente;
  const _EditorCliente({this.existente});
  @override
  State<_EditorCliente> createState() => _EditorClienteState();
}

class _EditorClienteState extends State<_EditorCliente> {
  late final _nombre = TextEditingController(text: widget.existente?.nombre ?? '');
  late final _telefono = TextEditingController(text: widget.existente?.telefono ?? '');
  late final _nota = TextEditingController(text: widget.existente?.nota ?? '');
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final base = widget.existente ?? const Cliente(nombre: '');
    try {
      final c = await context.servicios.repo.guardarCliente(base.copiar(nombre: _nombre.text, telefono: _telefono.text, nota: _nota.text));
      if (mounted) Navigator.of(context).pop(c);
    } on ErrorDatos catch (e) {
      setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existente == null ? 'Nuevo cliente' : 'Editar cliente', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('nombre-cliente'),
              controller: _nombre,
              autofocus: widget.existente == null,
              maxLength: maxNombreCliente,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Nombre', errorText: _error, prefixIcon: const Icon(Icons.person_rounded)),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('telefono-cliente'),
              controller: _telefono,
              maxLength: maxTelefono,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]'))],
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.phone_rounded)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nota,
              maxLength: maxNotaCliente,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Ej: Vive en el barrio, paga los viernes…',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(key: const ValueKey('guardar-cliente'), onPressed: _guardar, child: const Text('Guardar')),
          ]),
        ),
      ),
    );
  }
}

/// Lo que mamá ha cobrado por su trabajo, y a quién.
class PantallaTrabajo extends StatefulWidget {
  const PantallaTrabajo({super.key});
  @override
  State<PantallaTrabajo> createState() => _PantallaTrabajoState();
}

class _PantallaTrabajoState extends State<PantallaTrabajo> {
  late Periodo _periodo;
  late Repositorio _repo;
  ResumenTrabajo? _resumen;
  ResumenTrabajo? _anterior;
  List<TotalCliente> _clientes = [];
  bool _iniciado = false;
  int _pedido = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    _periodo = Periodo.de(TipoPeriodo.mes, context.servicios.hoy());
    _repo = context.servicios.repo..addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    _repo.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final pedido = ++_pedido;
    final p = _periodo;
    final r = await Future.wait<Object>([_repo.resumenTrabajo(p), _repo.resumenTrabajo(p.mover(-1)), _repo.totalesPorCliente(p)]);
    if (!mounted || pedido != _pedido) return;
    setState(() {
      _resumen = r[0] as ResumenTrabajo;
      _anterior = r[1] as ResumenTrabajo;
      _clientes = r[2] as List<TotalCliente>;
    });
  }

  void _cambiar(Periodo p) {
    setState(() => _periodo = p);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _resumen;
    final hoyT = context.servicios.hoy();
    final v = r == null || _anterior == null ? null : variacion(r.cobrado, _anterior!.cobrado);
    return Scaffold(
      appBar: AppBar(title: const Text('Trabajo'), actions: [
        IconButton(
          key: const ValueKey('abrir-clientes'),
          tooltip: 'Mis clientes',
          icon: const Icon(Icons.groups_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaClientes())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('anotar-cobro'),
        backgroundColor: colorTipo(context, true),
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PantallaMovimiento(tipo: TipoMovimiento.ingreso, deTrabajo: true)),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Anotar cobro', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 100), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: SegmentedButton<TipoPeriodo>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TipoPeriodo.semana, label: Text('Semana')),
                    ButtonSegment(value: TipoPeriodo.mes, label: Text('Mes')),
                    ButtonSegment(value: TipoPeriodo.anio, label: Text('Año')),
                  ],
                  selected: {_periodo.tipo},
                  onSelectionChanged: (s) => _cambiar(Periodo.de(s.first, _periodo.contiene(hoyT) ? hoyT : _periodo.desde)),
                ),
              ),
              Row(children: [
                IconButton(tooltip: 'Anterior', onPressed: () => _cambiar(_periodo.mover(-1)), icon: const Icon(Icons.chevron_left_rounded, size: 32)),
                Expanded(
                  child: Text(_periodo.etiqueta(hoyT),
                      key: const ValueKey('trabajo-periodo'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                IconButton(tooltip: 'Siguiente', onPressed: () => _cambiar(_periodo.mover(1)), icon: const Icon(Icons.chevron_right_rounded, size: 32)),
              ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Cobraste', style: t.titleMedium),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(formatearCOP(r.cobrado),
                            key: const ValueKey('trabajo-cobrado'),
                            style: t.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: colorTipo(context, true))),
                      ),
                      const SizedBox(height: 6),
                      Text('${r.cobros} cobro${r.cobros == 1 ? '' : 's'} · ${r.clientes} cliente${r.clientes == 1 ? '' : 's'}',
                          key: const ValueKey('trabajo-detalle'), style: t.bodyLarge),
                      if (v != null)
                        Text('${v > 0 ? '▲' : v < 0 ? '▼' : ''} ${v.abs().toStringAsFixed(v.abs() < 10 ? 1 : 0).replaceAll('.', ',')} % que el período anterior',
                            style: t.bodySmall),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text('¿Quién te pagó?', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (_clientes.isEmpty)
                const Vacio(
                  icono: Icons.handshake_outlined,
                  texto: 'Aquí verás lo que te paga cada cliente.\nToca "Anotar cobro" y escribe su nombre.',
                )
              else
                for (final c in _clientes)
                  ListTile(
                    key: ValueKey('total-cliente-${c.cliente.nombre}'),
                    leading: AvatarCliente(c.cliente),
                    title: Text(c.cliente.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${c.cobros} cobro${c.cobros == 1 ? '' : 's'}'
                        '${c.ultimaFecha != null ? ' · último ${encabezadoDia(c.ultimaFecha!, hoyT).toLowerCase()}' : ''}'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(formatearCOP(c.total), style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorTipo(context, true))),
                      if (r.cobrado > 0) Text('${(c.total * 100 / r.cobrado).round()} %', style: t.bodySmall),
                    ]),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaCliente(clienteId: c.cliente.id!))),
                  ),
            ]),
    );
  }
}

/// Ficha de un cliente: lo que ha pagado y su historial.
class PantallaCliente extends StatefulWidget {
  final int clienteId;
  const PantallaCliente({super.key, required this.clienteId});
  @override
  State<PantallaCliente> createState() => _PantallaClienteState();
}

class _PantallaClienteState extends State<PantallaCliente> {
  late Repositorio _repo;
  Cliente? _cliente;
  ({int total, int cobros, String? primera, String? ultima})? _historial;
  int _esteMes = 0;
  List<Movimiento> _movs = [];
  Map<int, Categoria> _cats = {};
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    _repo = context.servicios.repo..addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    _repo.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final hoyT = context.servicios.hoy();
    final c = await _repo.cliente(widget.clienteId);
    if (c == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final h = await _repo.historialCliente(widget.clienteId);
    final mes = await _repo.movimientos(Periodo.de(TipoPeriodo.mes, hoyT), clienteId: widget.clienteId, tipo: TipoMovimiento.ingreso);
    final movs = await _repo.movimientos(Periodo.rango('2000-01-01', '2200-12-31'), clienteId: widget.clienteId, limite: 5000);
    final cats = {for (final x in await _repo.categorias(incluirArchivadas: true)) x.id!: x};
    if (!mounted) return;
    setState(() {
      _cliente = c;
      _historial = h;
      _esteMes = mes.fold(0, (s, m) => s + m.monto);
      _movs = movs;
      _cats = cats;
    });
  }

  Future<void> _opciones() async {
    final c = _cliente!;
    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('Editar nombre, teléfono o nota'), onTap: () => Navigator.pop(s, 'editar')),
          ListTile(
            leading: Icon(c.archivado ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(c.archivado ? 'Volver a mostrar' : 'Archivar (dejar de sugerirlo)'),
            subtitle: c.archivado ? null : const Text('Sus cobros se conservan'),
            onTap: () => Navigator.pop(s, 'archivar'),
          ),
          if (_movs.isEmpty)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Eliminar'), onTap: () => Navigator.pop(s, 'eliminar')),
        ]),
      ),
    );
    if (!mounted || accion == null) return;
    try {
      switch (accion) {
        case 'editar':
          await editarCliente(context, existente: c);
        case 'archivar':
          await _repo.archivarCliente(c.id!, archivar: !c.archivado);
        case 'eliminar':
          if (await confirmar(context, titulo: '¿Eliminar a ${c.nombre}?', texto: 'No tiene cobros anotados.', si: 'Eliminar', peligro: true)) {
            await _repo.eliminarCliente(c.id!);
          }
      }
    } on ErrorDatos catch (e) {
      if (mounted) avisar(context, e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cliente;
    final h = _historial;
    final t = Theme.of(context).textTheme;
    if (c == null || h == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    Widget dato(String titulo, String valor, {Key? key}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: t.bodySmall),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor, key: key, style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(c.nombre), actions: [
        IconButton(tooltip: 'Opciones', icon: const Icon(Icons.more_vert), onPressed: _opciones),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('cobrar-a-cliente'),
        backgroundColor: colorTipo(context, true),
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PantallaMovimiento(tipo: TipoMovimiento.ingreso, deTrabajo: true, clienteInicial: c),
        )),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Anotar cobro'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        ListTile(
          leading: AvatarCliente(c, radio: 28),
          title: Text(c.nombre, style: t.titleLarge),
          subtitle: Text([
            if (c.telefono.isNotEmpty) c.telefono,
            if (c.nota.isNotEmpty) c.nota,
            if (c.archivado) 'Archivado',
          ].join('\n')),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  dato('Te ha pagado en total', formatearCOP(h.total), key: const ValueKey('cliente-total')),
                  dato('Este mes', formatearCOP(_esteMes), key: const ValueKey('cliente-mes')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  dato('Cobros', '${h.cobros}'),
                  dato('Último pago', h.ultima == null ? '—' : fechaCorta(h.ultima!)),
                ]),
                if (h.primera != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: Text('Cliente desde ${fechaCorta(h.primera!)}', style: t.bodySmall)),
                ],
              ]),
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('Historial', style: t.titleMedium)),
        if (_movs.isEmpty) const Vacio(icono: Icons.receipt_long_outlined, texto: 'Todavía no hay cobros a este cliente.'),
        for (final m in _movs)
          FilaMovimiento(
            m: m,
            categoria: _cats[m.categoriaId],
            cliente: c,
            mostrarFecha: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaMovimiento(tipo: m.tipo, existente: m))),
          ),
      ]),
    );
  }
}

/// Todos los clientes, para buscarlos, agregarlos o editarlos.
class PantallaClientes extends StatefulWidget {
  const PantallaClientes({super.key});
  @override
  State<PantallaClientes> createState() => _PantallaClientesState();
}

class _PantallaClientesState extends State<PantallaClientes> {
  late Repositorio _repo;
  List<Cliente>? _todos;
  String _filtro = '';
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    _repo = context.servicios.repo..addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    _repo.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final c = await _repo.clientes(incluirArchivados: true);
    if (mounted) setState(() => _todos = c);
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtro.trim().toLowerCase();
    final lista = (_todos ?? []).where((c) => f.isEmpty || c.nombre.toLowerCase().contains(f) || c.telefono.contains(f)).toList();
    final activos = lista.where((c) => !c.archivado).toList();
    final archivados = lista.where((c) => c.archivado).toList();
    Widget fila(Cliente c) => ListTile(
          leading: AvatarCliente(c),
          title: Text(c.nombre),
          subtitle: c.telefono.isEmpty ? null : Text(c.telefono),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaCliente(clienteId: c.id!))),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Mis clientes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('nuevo-cliente'),
        onPressed: () => editarCliente(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo cliente'),
      ),
      body: _todos == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 100), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  maxLength: 60,
                  onChanged: (v) => setState(() => _filtro = v),
                  decoration: const InputDecoration(hintText: 'Buscar cliente', prefixIcon: Icon(Icons.search_rounded), counterText: ''),
                ),
              ),
              if (activos.isEmpty && archivados.isEmpty)
                Vacio(
                  icono: Icons.groups_outlined,
                  texto: _todos!.isEmpty ? 'Todavía no tienes clientes.\nSe agregan solos cuando anotas un cobro.' : 'No se encontró ningún cliente.',
                ),
              for (final c in activos) fila(c),
              if (archivados.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text('Archivados', style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final c in archivados) fila(c),
              ],
            ]),
    );
  }
}
