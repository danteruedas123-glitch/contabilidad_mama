import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dinero.dart';
import '../../core/fechas.dart';
import '../../datos/modelos.dart';
import '../../datos/repositorio.dart';
import '../../servicios.dart';
import '../iconos.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import 'categorias.dart';

/// Resultado al cerrar la pantalla.
enum ResultadoMovimiento { guardado, eliminado }

/// Pone puntos de miles mientras se escriben solo números ("50000" → "50.000").
/// Si escribe letras ("50 mil") no toca nada.
class FormatoMiles extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue viejo, TextEditingValue nuevo) {
    final t = nuevo.text;
    if (!RegExp(r'^[\d.]*$').hasMatch(t)) return nuevo;
    final digitos = t.replaceAll('.', '');
    if (digitos.isEmpty) return nuevo.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    if (digitos.length > 12) return viejo;
    final limpio = digitos.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final b = StringBuffer();
    for (var i = 0; i < limpio.length; i++) {
      if (i > 0 && (limpio.length - i) % 3 == 0) b.write('.');
      b.write(limpio[i]);
    }
    final s = b.toString();
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}

class PantallaMovimiento extends StatefulWidget {
  final TipoMovimiento tipo;
  final Movimiento? existente;
  const PantallaMovimiento({super.key, required this.tipo, this.existente});

  @override
  State<PantallaMovimiento> createState() => _PantallaMovimientoState();
}

class _PantallaMovimientoState extends State<PantallaMovimiento> {
  final _monto = TextEditingController();
  final _desc = TextEditingController();
  final _nota = TextEditingController();
  final _focoMonto = FocusNode();
  final _scroll = ScrollController();

  late TipoMovimiento _tipo;
  int? _categoriaId;
  MedioPago? _medio;
  late String _fecha;
  bool _conLetras = false;
  bool _guardando = false;
  bool _cambio = false;
  bool _intentoGuardar = false;
  String? _errorGeneral;

  List<Categoria> _categorias = [];
  List<Sugerencia> _sugerencias = [];
  Timer? _espera;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _tipo = e?.tipo ?? widget.tipo;
    _fecha = e?.fecha ?? '';
    if (e != null) {
      _monto.text = FormatoMiles().formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: '${e.monto}')).text;
      _desc.text = e.descripcion;
      _nota.text = e.nota;
      _categoriaId = e.categoriaId;
      _medio = e.medio;
    }
    for (final c in [_monto, _desc, _nota]) {
      c.addListener(_marcarCambio);
    }
    _desc.addListener(_pedirSugerencias);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fecha.isEmpty) _fecha = context.servicios.hoy();
    if (_categorias.isEmpty) _cargar();
  }

  Future<void> _cargar() async {
    final repo = context.servicios.repo;
    final cats = await repo.categorias(incluirArchivadas: true);
    if (!mounted) return;
    setState(() => _categorias = cats);
    _pedirSugerencias();
  }

  void _marcarCambio() {
    if (!_cambio) setState(() => _cambio = true);
    setState(() {}); // refresca la vista previa del monto
  }

  void _pedirSugerencias() {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 150), () async {
      final s = await context.servicios.repo.sugerencias(_tipo, prefijo: _desc.text);
      if (mounted) setState(() => _sugerencias = s.where((x) => x.descripcion != _desc.text).toList());
    });
  }

  @override
  void dispose() {
    _espera?.cancel();
    for (final c in [_monto, _desc, _nota]) {
      c.dispose();
    }
    _focoMonto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Categoria> get _visibles => _categorias
      .where((c) => c.tipo.sirvePara(_tipo) && (!c.archivada || c.id == _categoriaId))
      .toList();

  void _cambiarTipo(TipoMovimiento t) {
    setState(() {
      _tipo = t;
      _cambio = true;
      final actual = _categorias.where((c) => c.id == _categoriaId).firstOrNull;
      if (actual != null && !actual.tipo.sirvePara(t)) _categoriaId = null;
    });
    _pedirSugerencias();
  }

  void _sumar(int n) {
    final actual = leerMonto(_monto.text).valor ?? 0;
    final nuevo = (actual + n).clamp(0, montoMaximo);
    _monto.text = FormatoMiles().formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: '$nuevo')).text;
    HapticFeedback.selectionClick();
  }

  Future<void> _elegirFecha() async {
    final hoyF = aFecha(context.servicios.hoy());
    final f = await showDatePicker(
      context: context,
      initialDate: aFecha(_fecha),
      firstDate: DateTime(2000),
      lastDate: DateTime(hoyF.year + 1, 12, 31),
      helpText: 'Fecha del movimiento',
    );
    if (f != null) {
      setState(() {
        _fecha = aTexto(f);
        _cambio = true;
      });
    }
  }

  Future<void> _nuevaCategoria() async {
    final c = await editarCategoria(context, tipoInicial: _tipo == TipoMovimiento.ingreso ? TipoCategoria.ingreso : TipoCategoria.egreso);
    if (c == null) return;
    await _cargar();
    setState(() => _categoriaId = c.id);
  }

  Future<void> _guardar({bool otro = false}) async {
    setState(() => _intentoGuardar = true);
    final monto = leerMonto(_monto.text);
    if (!monto.valido) {
      // El campo del valor está arriba: se sube hasta él para que se vea el error.
      avisar(context, monto.error!);
      await _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      _focoMonto.requestFocus();
      return;
    }
    final m = Movimiento(
      id: widget.existente?.id,
      tipo: _tipo,
      monto: monto.valor!,
      categoriaId: _categoriaId,
      descripcion: _desc.text.trim(),
      nota: _nota.text.trim(),
      medio: _medio,
      fecha: _fecha,
    );
    setState(() {
      _guardando = true;
      _errorGeneral = null;
    });
    final s = context.servicios;
    try {
      if (_editando) {
        await s.repo.actualizarMovimiento(m);
      } else {
        await s.repo.agregarMovimiento(m);
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      if (otro) {
        avisar(context, 'Guardado: ${formatearCOP(m.monto)}');
        setState(() {
          _monto.clear();
          _desc.clear();
          _nota.clear();
          _categoriaId = null;
          _medio = null;
          _cambio = false;
          _intentoGuardar = false;
          _guardando = false;
        });
        _focoMonto.requestFocus();
      } else {
        Navigator.of(context).pop(ResultadoMovimiento.guardado);
      }
    } on ErrorDatos catch (e) {
      setState(() {
        _errorGeneral = e.mensaje;
        _guardando = false;
      });
    }
  }

  Future<void> _eliminar() async {
    final e = widget.existente!;
    final ok = await confirmar(context,
        titulo: '¿Enviar a la papelera?', texto: 'Podrás recuperarlo desde Ajustes → Papelera.', si: 'Enviar a la papelera', peligro: true);
    if (!ok || !mounted) return;
    await context.servicios.repo.eliminarMovimiento(e.id!);
    if (mounted) Navigator.of(context).pop(ResultadoMovimiento.eliminado);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ingreso = _tipo == TipoMovimiento.ingreso;
    final color = colorTipo(context, ingreso);
    final lectura = leerMonto(_monto.text);
    final hoyT = context.servicios.hoy();
    final ayer = sumarDias(hoyT, -1);

    return PopScope(
      canPop: !_cambio || _guardando,
      onPopInvokedWithResult: (salio, _) async {
        if (salio) return;
        final nav = Navigator.of(context);
        if (await confirmar(context, titulo: '¿Salir sin guardar?', texto: 'Lo que escribiste se perderá.', si: 'Salir sin guardar', peligro: true)) {
          setState(() => _cambio = false);
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editando ? 'Editar movimiento' : (ingreso ? 'Anotar lo que entró' : 'Anotar lo que salió')),
          actions: [
            if (_editando)
              IconButton(tooltip: 'Enviar a la papelera', onPressed: _eliminar, icon: const Icon(Icons.delete_outline)),
          ],
        ),
        body: SafeArea(
          child: ListView(
            key: const ValueKey('form-movimiento'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SegmentedButton<TipoMovimiento>(
                segments: const [
                  ButtonSegment(value: TipoMovimiento.ingreso, label: Text('Entró'), icon: Icon(Icons.arrow_downward_rounded)),
                  ButtonSegment(value: TipoMovimiento.egreso, label: Text('Salió'), icon: Icon(Icons.arrow_upward_rounded)),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => _cambiarTipo(s.first),
              ),
              const SizedBox(height: 20),

              // ---------------------------------------------------- valor
              TextField(
                key: const ValueKey('campo-monto'),
                controller: _monto,
                focusNode: _focoMonto,
                autofocus: !_editando,
                keyboardType: _conLetras ? TextInputType.text : TextInputType.number,
                inputFormatters: [LengthLimitingTextInputFormatter(40), FormatoMiles()],
                style: t.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: '¿Cuánto?',
                  prefixText: r'$ ',
                  prefixStyle: t.headlineMedium?.copyWith(color: color),
                  hintText: _conLetras ? 'Ej: 50 mil' : '0',
                  errorText: _intentoGuardar && !lectura.valido ? lectura.error : null,
                  helperText: _monto.text.isNotEmpty && lectura.valido && !RegExp(r'^[\d.]+$').hasMatch(_monto.text)
                      ? '= ${formatearCOP(lectura.valor!)}'
                      : null,
                  suffixIcon: IconButton(
                    tooltip: _conLetras ? 'Usar teclado de números' : 'Escribir con letras (ej: 50 mil)',
                    icon: Icon(_conLetras ? Icons.dialpad_rounded : Icons.keyboard_rounded),
                    onPressed: () {
                      setState(() => _conLetras = !_conLetras);
                      _focoMonto.unfocus();
                      Future.delayed(const Duration(milliseconds: 80), _focoMonto.requestFocus);
                    },
                  ),
                ),
                onSubmitted: (_) => _guardar(),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final n in const [1000, 2000, 5000, 10000, 20000, 50000, 100000])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(label: Text('+${formatearCOP(n)}'), onPressed: () => _sumar(n)),
                    ),
                ]),
              ),
              const SizedBox(height: 20),

              // ---------------------------------------------------- en qué
              TextField(
                key: const ValueKey('campo-descripcion'),
                controller: _desc,
                maxLength: maxDescripcion,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: ingreso ? '¿De qué? (opcional)' : '¿En qué? (opcional)',
                  hintText: ingreso ? 'Ej: Pago de la quincena, ganó el bingo…' : 'Ej: Mercado, pasajes, droguería…',
                  counterText: '',
                ),
              ),
              if (_sugerencias.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 0, children: [
                  for (final s in _sugerencias.take(6))
                    ActionChip(
                      avatar: const Icon(Icons.history_rounded, size: 18),
                      label: Text(s.descripcion),
                      onPressed: () {
                        _desc.text = s.descripcion;
                        if (s.categoriaId != null && _categorias.any((c) => c.id == s.categoriaId && c.tipo.sirvePara(_tipo))) {
                          setState(() => _categoriaId = s.categoriaId);
                        }
                      },
                    ),
                ]),
              ],
              const SizedBox(height: 20),

              // ---------------------------------------------------- categoría
              Text('Categoría (opcional)', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _visibles)
                  ChoiceChip(
                    key: ValueKey('cat-${c.nombre}'),
                    avatar: Icon(iconoDe(c.icono), size: 18, color: Color(c.color)),
                    label: Text(c.nombre),
                    selected: _categoriaId == c.id,
                    onSelected: (s) => setState(() {
                      _categoriaId = s ? c.id : null;
                      _cambio = true;
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Nueva categoría'),
                  onPressed: _nuevaCategoria,
                ),
              ]),
              const SizedBox(height: 20),

              // ---------------------------------------------------- fecha
              Text('Fecha', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('Hoy'), selected: _fecha == hoyT, onSelected: (_) => setState(() => _fecha = hoyT)),
                ChoiceChip(label: const Text('Ayer'), selected: _fecha == ayer, onSelected: (_) => setState(() => _fecha = ayer)),
                ChoiceChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(_fecha != hoyT && _fecha != ayer ? fechaCorta(_fecha) : 'Otra fecha'),
                  selected: _fecha != hoyT && _fecha != ayer,
                  onSelected: (_) => _elegirFecha(),
                ),
              ]),
              const SizedBox(height: 20),

              // ---------------------------------------------------- medio
              Text('¿Cómo? (opcional)', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in MedioPago.values)
                  ChoiceChip(
                    label: Text(m.nombre),
                    selected: _medio == m,
                    onSelected: (s) => setState(() {
                      _medio = s ? m : null;
                      _cambio = true;
                    }),
                  ),
              ]),
              const SizedBox(height: 20),

              TextField(
                controller: _nota,
                maxLength: maxNota,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Cualquier detalle que quieras recordar'),
              ),
              if (_errorGeneral != null) ...[
                const SizedBox(height: 8),
                Text(_errorGeneral!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('guardar'),
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: _guardando ? null : () => _guardar(),
                icon: const Icon(Icons.check_rounded),
                label: Text(_editando ? 'Guardar cambios' : 'Guardar'),
              ),
              if (!_editando) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('guardar-otro'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: _guardando ? null : () => _guardar(otro: true),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Guardar y anotar otro'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
