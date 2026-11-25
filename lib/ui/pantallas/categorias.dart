import 'package:flutter/material.dart';

import '../../datos/modelos.dart';
import '../../datos/repositorio.dart';
import '../../servicios.dart';
import '../iconos.dart';
import '../widgets/comunes.dart';

/// Crea o edita una categoría. Devuelve la categoría guardada o null.
Future<Categoria?> editarCategoria(BuildContext context, {Categoria? existente, TipoCategoria tipoInicial = TipoCategoria.egreso}) {
  return showModalBottomSheet<Categoria>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditorCategoria(existente: existente, tipoInicial: tipoInicial),
  );
}

class _EditorCategoria extends StatefulWidget {
  final Categoria? existente;
  final TipoCategoria tipoInicial;
  const _EditorCategoria({this.existente, required this.tipoInicial});

  @override
  State<_EditorCategoria> createState() => _EditorCategoriaState();
}

class _EditorCategoriaState extends State<_EditorCategoria> {
  late final _nombre = TextEditingController(text: widget.existente?.nombre ?? '');
  late TipoCategoria _tipo = widget.existente?.tipo ?? widget.tipoInicial;
  late String _icono = widget.existente?.icono ?? 'otros';
  late int _color = widget.existente?.color ?? coloresCategoria[2];
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final base = widget.existente ?? Categoria(nombre: '', tipo: _tipo, icono: _icono, color: _color);
    try {
      final c = await context.servicios.repo.guardarCategoria(base.copiar(nombre: _nombre.text, tipo: _tipo, icono: _icono, color: _color));
      if (mounted) Navigator.of(context).pop(c);
    } on ErrorDatos catch (e) {
      setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existente == null ? 'Nueva categoría' : 'Editar categoría', style: t.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('nombre-categoria'),
              controller: _nombre,
              autofocus: widget.existente == null,
              maxLength: maxNombreCategoria,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Nombre', errorText: _error, hintText: 'Ej: Mascotas, Uñas, Iglesia…'),
            ),
            const SizedBox(height: 8),
            Text('Sirve para', style: t.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<TipoCategoria>(
              segments: const [
                ButtonSegment(value: TipoCategoria.ingreso, label: Text('Entradas')),
                ButtonSegment(value: TipoCategoria.egreso, label: Text('Salidas')),
                ButtonSegment(value: TipoCategoria.ambos, label: Text('Las dos')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 16),
            Text('Ícono', style: t.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in iconosCategoria.entries)
                InkResponse(
                  onTap: () => setState(() => _icono = e.key),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _icono == e.key ? Color(_color).withValues(alpha: 0.2) : null,
                      border: Border.all(color: _icono == e.key ? Color(_color) : Colors.transparent, width: 2),
                    ),
                    child: Icon(e.value, color: Color(_color)),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Text('Color', style: t.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in coloresCategoria)
                InkResponse(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: _color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            FilledButton(key: const ValueKey('guardar-categoria'), onPressed: _guardar, child: const Text('Guardar')),
          ]),
        ),
      ),
    );
  }
}

class PantallaCategorias extends StatefulWidget {
  const PantallaCategorias({super.key});
  @override
  State<PantallaCategorias> createState() => _PantallaCategoriasState();
}

class _PantallaCategoriasState extends State<PantallaCategorias> {
  List<Categoria>? _cats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cargar();
  }

  Future<void> _cargar() async {
    final c = await context.servicios.repo.categorias(incluirArchivadas: true);
    if (mounted) setState(() => _cats = c);
  }

  Future<void> _opciones(Categoria c) async {
    final repo = context.servicios.repo;
    final usos = await repo.usosCategoria(c.id!);
    if (!mounted) return;
    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: IconoCategoria(c), title: Text(c.nombre), subtitle: Text('$usos movimiento${usos == 1 ? '' : 's'}')),
          const Divider(),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Editar nombre, ícono o color'), onTap: () => Navigator.pop(s, 'editar')),
          ListTile(
            leading: Icon(c.archivada ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(c.archivada ? 'Volver a mostrar' : 'Archivar (dejar de mostrarla)'),
            subtitle: c.archivada ? null : const Text('Sus movimientos se conservan'),
            onTap: () => Navigator.pop(s, 'archivar'),
          ),
          if (usos == 0)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Eliminar'), onTap: () => Navigator.pop(s, 'eliminar')),
        ]),
      ),
    );
    if (!mounted || accion == null) return;
    try {
      switch (accion) {
        case 'editar':
          await editarCategoria(context, existente: c);
        case 'archivar':
          await repo.archivarCategoria(c.id!, archivar: !c.archivada);
        case 'eliminar':
          if (await confirmar(context, titulo: '¿Eliminar "${c.nombre}"?', texto: 'No tiene movimientos.', si: 'Eliminar', peligro: true)) {
            await repo.eliminarCategoria(c.id!);
          }
      }
    } on ErrorDatos catch (e) {
      if (mounted) avisar(context, e.mensaje);
    }
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    Widget seccion(String titulo, Iterable<Categoria> lista) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(titulo, style: Theme.of(context).textTheme.titleSmall)),
          for (final c in lista)
            ListTile(
              leading: IconoCategoria(c, tamano: 40),
              title: Text(c.nombre),
              subtitle: c.archivada ? const Text('Archivada') : null,
              trailing: const Icon(Icons.more_vert),
              onTap: () => _opciones(c),
            ),
        ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await editarCategoria(context);
          _cargar();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: cats == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              seccion('Para salidas', cats.where((c) => !c.archivada && c.tipo == TipoCategoria.egreso)),
              seccion('Para entradas', cats.where((c) => !c.archivada && c.tipo == TipoCategoria.ingreso)),
              seccion('Para las dos', cats.where((c) => !c.archivada && c.tipo == TipoCategoria.ambos)),
              if (cats.any((c) => c.archivada)) seccion('Archivadas', cats.where((c) => c.archivada)),
            ]),
    );
  }
}
