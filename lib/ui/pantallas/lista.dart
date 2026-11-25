import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dinero.dart';
import '../../core/fechas.dart';
import '../../datos/modelos.dart';
import '../../datos/repositorio.dart';
import '../../servicios.dart';
import '../widgets/comunes.dart';
import 'movimiento.dart';

/// Lista de movimientos: búsqueda por texto en toda la historia, o los de una
/// categoría en un período.
class PantallaLista extends StatefulWidget {
  final Periodo? periodo;
  final Categoria? categoria;
  final TipoMovimiento? tipo;
  final bool esBusqueda;

  const PantallaLista.buscar({super.key})
      : periodo = null,
        categoria = null,
        tipo = null,
        esBusqueda = true;

  const PantallaLista.categoria({super.key, required this.periodo, required this.categoria, required this.tipo})
      : esBusqueda = false;

  @override
  State<PantallaLista> createState() => _PantallaListaState();
}

class _PantallaListaState extends State<PantallaLista> {
  final _texto = TextEditingController();
  List<Movimiento>? _movs;
  Map<int, Categoria> _cats = {};
  Timer? _espera;
  late Repositorio _repo;
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
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final cats = {for (final c in await _repo.categorias(incluirArchivadas: true)) c.id!: c};
    List<Movimiento> movs;
    if (widget.esBusqueda) {
      movs = _texto.text.trim().isEmpty ? [] : await _repo.buscar(_texto.text);
    } else {
      final todos = await _repo.movimientos(widget.periodo!, tipo: widget.tipo, categoriaId: widget.categoria?.id, limite: 20000);
      // "Sin categoría" = categoria_id nulo
      movs = widget.categoria == null ? todos.where((m) => m.categoriaId == null).toList() : todos;
    }
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _movs = movs;
    });
  }

  void _buscar(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), _cargar);
  }

  @override
  Widget build(BuildContext context) {
    final movs = _movs;
    final total = movs?.fold<int>(0, (s, m) => s + m.conSigno) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: widget.esBusqueda
            ? TextField(
                controller: _texto,
                autofocus: true,
                maxLength: 60,
                onChanged: _buscar,
                decoration: const InputDecoration(
                  hintText: 'Buscar: mercado, bingo, Nequi…',
                  border: InputBorder.none,
                  filled: false,
                  counterText: '',
                ),
              )
            : Text(widget.categoria?.nombre ?? 'Sin categoría'),
      ),
      body: movs == null
          ? const Center(child: CircularProgressIndicator())
          : movs.isEmpty
              ? Vacio(
                  icono: widget.esBusqueda ? Icons.search_rounded : Icons.receipt_long_outlined,
                  texto: widget.esBusqueda
                      ? (_texto.text.trim().isEmpty ? 'Escribe lo que buscas.' : 'No se encontró nada.')
                      : 'No hay movimientos.',
                )
              : ListView.builder(
                  itemCount: movs.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return ListTile(
                        title: Text(
                          '${movs.length} movimiento${movs.length == 1 ? '' : 's'}'
                          '${widget.periodo != null ? ' · ${widget.periodo!.etiqueta(context.servicios.hoy())}' : ''}',
                        ),
                        trailing: Text(formatearCOP(total), style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }
                    final m = movs[i - 1];
                    return FilaMovimiento(
                      m: m,
                      categoria: _cats[m.categoriaId],
                      mostrarFecha: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PantallaMovimiento(tipo: m.tipo, existente: m)),
                      ),
                    );
                  },
                ),
    );
  }
}
