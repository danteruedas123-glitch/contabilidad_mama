import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dinero.dart';
import '../../datos/modelos.dart';
import '../tema.dart';

/// Barras dobles (verde = entró, rojo = salió) por día o por mes.
/// Tocar una barra muestra sus valores.
class GraficaBarras extends StatefulWidget {
  final List<PuntoSerie> puntos;
  final String Function(PuntoSerie) etiqueta;
  final String Function(PuntoSerie) detalle;
  const GraficaBarras({super.key, required this.puntos, required this.etiqueta, required this.detalle});

  @override
  State<GraficaBarras> createState() => _GraficaBarrasState();
}

class _GraficaBarrasState extends State<GraficaBarras> {
  int? _elegido;

  @override
  void didUpdateWidget(GraficaBarras old) {
    super.didUpdateWidget(old);
    if (old.puntos.length != widget.puntos.length) _elegido = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.puntos;
    final elegido = _elegido != null && _elegido! < p.length ? p[_elegido!] : null;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: elegido == null
              ? Center(child: Text('Toca una barra para ver el detalle', style: t.bodySmall))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(widget.detalle(elegido), style: t.titleSmall),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Entró ${formatearCOP(elegido.ingresos)}', style: TextStyle(color: colorTipo(context, true))),
                    const TextSpan(text: '   '),
                    TextSpan(text: 'Salió ${formatearCOP(elegido.egresos)}', style: TextStyle(color: colorTipo(context, false))),
                  ])),
                ]),
        ),
        LayoutBuilder(builder: (context, c) {
          return GestureDetector(
            onTapDown: (d) {
              if (p.isEmpty) return;
              final i = (d.localPosition.dx / (c.maxWidth / p.length)).floor().clamp(0, p.length - 1);
              setState(() => _elegido = _elegido == i ? null : i);
            },
            child: Semantics(
              label: 'Gráfica de entradas y salidas',
              child: CustomPaint(
                size: Size(c.maxWidth, 200),
                painter: _PintorBarras(
                  puntos: p,
                  etiquetas: [for (final x in p) widget.etiqueta(x)],
                  verde: colorTipo(context, true),
                  rojo: colorTipo(context, false),
                  linea: Theme.of(context).colorScheme.outlineVariant,
                  texto: Theme.of(context).colorScheme.onSurfaceVariant,
                  resaltado: _elegido,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _PintorBarras extends CustomPainter {
  final List<PuntoSerie> puntos;
  final List<String> etiquetas;
  final Color verde, rojo, linea, texto;
  final int? resaltado;

  _PintorBarras({
    required this.puntos,
    required this.etiquetas,
    required this.verde,
    required this.rojo,
    required this.linea,
    required this.texto,
    required this.resaltado,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;
    const abajo = 22.0;
    final alto = size.height - abajo;
    final maximo = puntos.fold<int>(1, (m, p) => math.max(m, math.max(p.ingresos, p.egresos)));
    final ancho = size.width / puntos.length;
    final barra = math.max(1.5, math.min(14.0, ancho * 0.36));

    final pLinea = Paint()
      ..color = linea
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, alto), Offset(size.width, alto), pLinea);

    final pV = Paint()..color = verde;
    final pR = Paint()..color = rojo;
    final cada = (puntos.length / 8).ceil(); // no más de ~8 etiquetas
    for (var i = 0; i < puntos.length; i++) {
      final x = ancho * i + ancho / 2;
      final opaco = resaltado == null || resaltado == i;
      final hi = alto * puntos[i].ingresos / maximo;
      final he = alto * puntos[i].egresos / maximo;
      if (resaltado == i) {
        canvas.drawRect(Rect.fromLTWH(ancho * i, 0, ancho, alto), Paint()..color = linea.withValues(alpha: 0.35));
      }
      pV.color = verde.withValues(alpha: opaco ? 1 : 0.35);
      pR.color = rojo.withValues(alpha: opaco ? 1 : 0.35);
      if (hi > 0) {
        canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x - barra - 1, alto - math.max(hi, 2), barra, math.max(hi, 2)), topLeft: const Radius.circular(3), topRight: const Radius.circular(3)), pV);
      }
      if (he > 0) {
        canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x + 1, alto - math.max(he, 2), barra, math.max(he, 2)), topLeft: const Radius.circular(3), topRight: const Radius.circular(3)), pR);
      }
      if (i % cada == 0) {
        final tp = TextPainter(
          text: TextSpan(text: etiquetas[i], style: TextStyle(color: texto, fontSize: 11)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: ancho * cada);
        tp.paint(canvas, Offset(x - tp.width / 2, alto + 5));
      }
    }
  }

  @override
  bool shouldRepaint(_PintorBarras old) =>
      old.puntos != puntos || old.resaltado != resaltado || old.verde != verde || old.texto != texto;
}

/// Barras horizontales por categoría con porcentaje del total.
class BarraCategoria extends StatelessWidget {
  final Widget icono;
  final String nombre;
  final int total;
  final int base;
  final int cantidad;
  final bool ingreso;
  final VoidCallback? onTap;

  const BarraCategoria({
    super.key,
    required this.icono,
    required this.nombre,
    required this.total,
    required this.base,
    required this.cantidad,
    required this.ingreso,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fraccion = base == 0 ? 0.0 : total / base;
    final pct = (fraccion * 100).toStringAsFixed(fraccion < 0.1 ? 1 : 0).replaceAll('.', ',');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          icono,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                Text(formatearCOP(total), style: TextStyle(fontWeight: FontWeight.w700, color: colorTipo(context, ingreso))),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraccion.clamp(0, 1),
                  minHeight: 8,
                  color: colorTipo(context, ingreso),
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Text('$pct % · $cantidad movimiento${cantidad == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}
