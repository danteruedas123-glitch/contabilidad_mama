import 'package:flutter/material.dart';

import '../../core/dinero.dart';
import '../../datos/modelos.dart';
import '../iconos.dart';
import '../tema.dart';

class IconoCategoria extends StatelessWidget {
  final Categoria? categoria;
  final double tamano;
  const IconoCategoria(this.categoria, {super.key, this.tamano = 44});

  @override
  Widget build(BuildContext context) {
    final color = categoria == null ? Theme.of(context).colorScheme.outline : Color(categoria!.color);
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(categoria == null ? Icons.help_outline_rounded : iconoDe(categoria!.icono), color: color, size: tamano * 0.55),
    );
  }
}

/// "+$50.000" en verde o "-$20.000" en rojo.
class TextoMonto extends StatelessWidget {
  final int valor;
  final bool ingreso;
  final TextStyle? estilo;
  final bool conSigno;
  const TextoMonto(this.valor, {super.key, required this.ingreso, this.estilo, this.conSigno = true});

  @override
  Widget build(BuildContext context) => Text(
        '${conSigno ? (ingreso ? '+' : '−') : ''}${formatearCOP(valor.abs())}',
        style: (estilo ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
          color: colorTipo(context, ingreso),
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

class FilaMovimiento extends StatelessWidget {
  final Movimiento m;
  final Categoria? categoria;
  final Cliente? cliente;
  final VoidCallback? onTap;
  final bool mostrarFecha;
  const FilaMovimiento({super.key, required this.m, required this.categoria, this.cliente, this.onTap, this.mostrarFecha = false});

  @override
  Widget build(BuildContext context) {
    final nombreCat = categoria?.nombre ?? 'Sin categoría';
    // Título: lo que escribió; si no, el cliente; si no, la categoría.
    final titulo = m.descripcion.isNotEmpty ? m.descripcion : (cliente?.nombre ?? nombreCat);
    final partes = <String>[
      if (titulo != nombreCat) nombreCat,
      if (cliente != null && titulo != cliente!.nombre) cliente!.nombre,
      if (m.medio != null) m.medio!.nombre,
      if (mostrarFecha) m.fecha,
    ];
    return ListTile(
      onTap: onTap,
      leading: IconoCategoria(categoria),
      title: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: partes.isEmpty && m.nota.isEmpty
          ? null
          : Text(
              [partes.join(' · '), if (m.nota.isNotEmpty) m.nota].where((s) => s.isNotEmpty).join('\n'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: TextoMonto(m.monto, ingreso: m.tipo == TipoMovimiento.ingreso),
    );
  }
}

/// Mensaje centrado para listas vacías.
class Vacio extends StatelessWidget {
  final IconData icono;
  final String texto;
  const Vacio({super.key, required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        child: Column(children: [
          Icon(icono, size: 56, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ]),
      );
}

void avisar(BuildContext context, String texto, {SnackBarAction? accion}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto), action: accion, duration: Duration(seconds: accion == null ? 3 : 6)));
}

Future<bool> confirmar(BuildContext context, {required String titulo, required String texto, String si = 'Sí', bool peligro = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: peligro ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(si),
        ),
      ],
    ),
  );
  return r ?? false;
}
