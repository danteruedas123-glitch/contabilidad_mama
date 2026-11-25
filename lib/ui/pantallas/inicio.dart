import 'package:flutter/material.dart';

import '../../core/dinero.dart';
import '../../core/fechas.dart';
import '../../datos/modelos.dart';
import '../../datos/repositorio.dart';
import '../../servicios.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import '../widgets/grafica.dart';
import 'ajustes.dart';
import 'lista.dart';
import 'movimiento.dart';

class _Datos {
  final Periodo periodo;
  final Resumen resumen;
  final Resumen anterior;
  final int saldo;
  final BalanceJuego juego;
  final List<Movimiento> movimientos;
  final List<TotalCategoria> porCategoria;
  final List<PuntoSerie> serie;
  final Map<int, Categoria> categorias;
  final bool recordarCopia;
  const _Datos(this.periodo, this.resumen, this.anterior, this.saldo, this.juego, this.movimientos, this.porCategoria,
      this.serie, this.categorias, this.recordarCopia);
}

enum _Vista { movimientos, categorias, grafica }

const limiteLista = 3000;

class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});
  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  late Periodo _periodo;
  _Datos? _datos;
  _Vista _vista = _Vista.movimientos;
  int _pedido = 0;
  bool _iniciado = false;
  late Repositorio _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final s = context.servicios;
    _periodo = Periodo.de(TipoPeriodo.mes, s.hoy());
    _repo = s.repo..addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    _repo.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final pedido = ++_pedido;
    final s = context.servicios;
    final repo = s.repo;
    final p = _periodo;
    final anterior = p.mover(-1);
    final serieF = p.tipo == TipoPeriodo.dia
        ? Future.value(<PuntoSerie>[])
        : p.tipo == TipoPeriodo.anio
            ? repo.seriePorMes(p.desde.substring(0, 4))
            : repo.seriePorDia(p);
    final r = await Future.wait<Object>([
      repo.resumen(p),
      repo.resumen(anterior),
      repo.saldoHasta(p.hasta.compareTo(s.hoy()) > 0 ? s.hoy() : p.hasta),
      repo.balanceJuego(p),
      repo.movimientos(p, limite: limiteLista),
      repo.totalesPorCategoria(p),
      serieF,
      repo.categorias(incluirArchivadas: true),
      _hayQueRecordarCopia(),
    ]);
    if (!mounted || pedido != _pedido) return; // llegó una consulta más nueva
    setState(() => _datos = _Datos(
          p,
          r[0] as Resumen,
          r[1] as Resumen,
          r[2] as int,
          r[3] as BalanceJuego,
          r[4] as List<Movimiento>,
          r[5] as List<TotalCategoria>,
          r[6] as List<PuntoSerie>,
          {for (final c in r[7] as List<Categoria>) c.id!: c},
          r[8] as bool,
        ));
  }

  /// Recuerda hacer copia si hay datos y la última copia externa tiene más de 15 días.
  Future<bool> _hayQueRecordarCopia() async {
    final repo = context.servicios.repo;
    if (await repo.totalMovimientos() < 5) return false;
    final ultima = DateTime.tryParse(await repo.ajuste('ultima_copia') ?? '');
    return ultima == null || DateTime.now().difference(ultima).inDays >= 15;
  }

  void _cambiarPeriodo(Periodo p) {
    setState(() => _periodo = p);
    _cargar();
  }

  Future<void> _elegirFechas() async {
    final hoyF = aFecha(context.servicios.hoy());
    if (_periodo.tipo == TipoPeriodo.dia) {
      final f = await showDatePicker(
          context: context, initialDate: aFecha(_periodo.desde), firstDate: DateTime(2000), lastDate: DateTime(hoyF.year + 1, 12, 31));
      if (f != null) _cambiarPeriodo(Periodo.de(TipoPeriodo.dia, aTexto(f)));
      return;
    }
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoyF.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: aFecha(_periodo.desde), end: aFecha(_periodo.hasta)),
      helpText: 'Elige desde y hasta',
    );
    if (r != null) _cambiarPeriodo(Periodo.rango(aTexto(r.start), aTexto(r.end)));
  }

  Future<void> _nuevo(TipoMovimiento tipo) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaMovimiento(tipo: tipo)));
  }

  Future<void> _abrir(Movimiento m) async {
    final r = await Navigator.of(context).push<ResultadoMovimiento>(
      MaterialPageRoute(builder: (_) => PantallaMovimiento(tipo: m.tipo, existente: m)),
    );
    if (r == ResultadoMovimiento.eliminado && mounted) {
      final repo = context.servicios.repo;
      avisar(context, 'Enviado a la papelera',
          accion: SnackBarAction(label: 'Deshacer', onPressed: () => repo.restaurarMovimiento(m.id!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Cuentas', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaLista.buscar())),
          ),
          IconButton(
            key: const ValueKey('abrir-ajustes'),
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaAjustes())),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: FloatingActionButton.extended(
              key: const ValueKey('nuevo-ingreso'),
              heroTag: 'ingreso',
              backgroundColor: colorTipo(context, true),
              foregroundColor: Colors.white,
              onPressed: () => _nuevo(TipoMovimiento.ingreso),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Entró', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FloatingActionButton.extended(
              key: const ValueKey('nuevo-egreso'),
              heroTag: 'egreso',
              backgroundColor: colorTipo(context, false),
              foregroundColor: Colors.white,
              onPressed: () => _nuevo(TipoMovimiento.egreso),
              icon: const Icon(Icons.remove_rounded),
              label: const Text('Salió', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _selector()),
                  SliverToBoxAdapter(child: _resumen(d)),
                  if (d.juego.hayDatos) SliverToBoxAdapter(child: _juego(d.juego)),
                  if (d.recordarCopia) SliverToBoxAdapter(child: _recordatorioCopia()),
                  SliverToBoxAdapter(child: _pestanas()),
                  ..._contenido(d),
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),
            ),
    );
  }

  Widget _selector() {
    final hoyT = context.servicios.hoy();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TipoPeriodo>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TipoPeriodo.dia, label: Text('Día')),
              ButtonSegment(value: TipoPeriodo.semana, label: Text('Semana')),
              ButtonSegment(value: TipoPeriodo.mes, label: Text('Mes')),
              ButtonSegment(value: TipoPeriodo.anio, label: Text('Año')),
            ],
            selected: {if (_periodo.tipo != TipoPeriodo.rango) _periodo.tipo},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              // Al cambiar de tipo se queda en la fecha que estaba mirando (o hoy)
              final ref = _periodo.contiene(hoyT) ? hoyT : _periodo.desde;
              _cambiarPeriodo(Periodo.de(s.first, ref));
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
            key: const ValueKey('periodo-anterior'),
            tooltip: 'Anterior',
            onPressed: () => _cambiarPeriodo(_periodo.mover(-1)),
            icon: const Icon(Icons.chevron_left_rounded, size: 32),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: _elegirFechas,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(_periodo.etiqueta(hoyT),
                  key: const ValueKey('etiqueta-periodo'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(
            key: const ValueKey('periodo-siguiente'),
            tooltip: 'Siguiente',
            onPressed: () => _cambiarPeriodo(_periodo.mover(1)),
            icon: const Icon(Icons.chevron_right_rounded, size: 32),
          ),
        ]),
        if (!_periodo.contiene(hoyT))
          TextButton(
            onPressed: () => _cambiarPeriodo(Periodo.de(_periodo.tipo == TipoPeriodo.rango ? TipoPeriodo.mes : _periodo.tipo, hoyT)),
            child: const Text('Volver a hoy'),
          ),
      ]),
    );
  }

  Widget _resumen(_Datos d) {
    final t = Theme.of(context).textTheme;
    final r = d.resumen;
    final positivo = r.balance >= 0;
    String comparacion(int actual, int antes) {
      final v = variacion(actual, antes);
      if (v == null) return '';
      if (v == 0) return 'igual que antes';
      return '${v > 0 ? '▲' : '▼'} ${v.abs().toStringAsFixed(v.abs() < 10 ? 1 : 0).replaceAll('.', ',')} % que el período anterior';
    }

    Widget columna(String titulo, int valor, bool ingreso, String comp) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ingreso ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 18, color: colorTipo(context, ingreso)),
              const SizedBox(width: 4),
              Text(titulo, style: t.titleSmall),
            ]),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatearCOP(valor),
                  key: ValueKey(ingreso ? 'total-ingresos' : 'total-egresos'),
                  style: t.titleLarge?.copyWith(color: colorTipo(context, ingreso), fontWeight: FontWeight.bold)),
            ),
            if (comp.isNotEmpty) Text(comp, style: t.bodySmall),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(positivo ? 'Te quedó' : 'Gastaste de más', style: t.titleMedium),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatearCOP(r.balance),
                key: const ValueKey('balance'),
                style: t.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: colorTipo(context, positivo)),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              columna('Entró', r.ingresos, true, comparacion(r.ingresos, d.anterior.ingresos)),
              const SizedBox(width: 12),
              columna('Salió', r.egresos, false, comparacion(r.egresos, d.anterior.egresos)),
            ]),
            const Divider(height: 28),
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Saldo total hasta ${d.periodo.hasta.compareTo(context.servicios.hoy()) >= 0 ? 'hoy' : fechaCorta(d.periodo.hasta)}')),
              Text(formatearCOP(d.saldo),
                  key: const ValueKey('saldo-total'),
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorTipo(context, d.saldo >= 0))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _juego(BalanceJuego j) {
    final t = Theme.of(context).textTheme;
    final gano = j.neto >= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: const Color(0xFFF9A825).withValues(alpha: 0.14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.casino_rounded, color: Color(0xFFF9A825), size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Juego', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('Ganó ${formatearCOP(j.ganado)} · Jugó ${formatearCOP(j.jugado)}', style: t.bodyMedium),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(gano ? 'Va ganando' : 'Va perdiendo', style: t.bodySmall),
              Text(formatearCOP(j.neto),
                  key: const ValueKey('juego-neto'),
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorTipo(context, gano))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _recordatorioCopia() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: const Text('Guarda una copia de seguridad'),
            subtitle: const Text('Si se pierde o se daña el celular, con la copia recuperas todo.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaCopias())),
          ),
        ),
      );

  Widget _pestanas() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: SegmentedButton<_Vista>(
          segments: const [
            ButtonSegment(value: _Vista.movimientos, label: Text('Lista'), icon: Icon(Icons.list_rounded)),
            ButtonSegment(value: _Vista.categorias, label: Text('Categorías'), icon: Icon(Icons.donut_small_rounded)),
            ButtonSegment(value: _Vista.grafica, label: Text('Gráfica'), icon: Icon(Icons.bar_chart_rounded)),
          ],
          selected: {_vista},
          onSelectionChanged: (s) => setState(() => _vista = s.first),
        ),
      );

  List<Widget> _contenido(_Datos d) {
    switch (_vista) {
      case _Vista.movimientos:
        return _lista(d);
      case _Vista.categorias:
        return [SliverToBoxAdapter(child: _categorias(d))];
      case _Vista.grafica:
        return [SliverToBoxAdapter(child: _grafica(d))];
    }
  }

  List<Widget> _lista(_Datos d) {
    if (d.movimientos.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Vacio(icono: Icons.receipt_long_outlined, texto: 'No hay movimientos en estas fechas.\nToca "Entró" o "Salió" para anotar.'),
        ),
      ];
    }
    // Encabezado por día con su balance + filas. Se arma una lista plana
    // para que SliverList construya solo lo que se ve (rinde con miles).
    final items = <Object>[];
    final totales = <String, int>{};
    for (final m in d.movimientos) {
      totales[m.fecha] = (totales[m.fecha] ?? 0) + m.conSigno;
    }
    String? dia;
    for (final m in d.movimientos) {
      if (m.fecha != dia) {
        dia = m.fecha;
        items.add(dia);
      }
      items.add(m);
    }
    final hoyT = context.servicios.hoy();
    return [
      if (d.movimientos.length >= limiteLista)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Se muestran los $limiteLista más recientes. Los totales de arriba sí incluyen todo.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          if (it is String) {
            final total = totales[it]!;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(children: [
                Expanded(child: Text(encabezadoDia(it, hoyT), style: Theme.of(context).textTheme.titleSmall)),
                Text('${total >= 0 ? '+' : '−'}${formatearCOP(total.abs())}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorTipo(context, total >= 0))),
              ]),
            );
          }
          final m = it as Movimiento;
          return FilaMovimiento(key: ValueKey('mov-${m.id}'), m: m, categoria: d.categorias[m.categoriaId], onTap: () => _abrir(m));
        },
      ),
    ];
  }

  Widget _categorias(_Datos d) {
    if (d.porCategoria.isEmpty) {
      return const Vacio(icono: Icons.donut_small_outlined, texto: 'Aquí verás en qué se va la plata y de dónde entra.');
    }
    Widget bloque(String titulo, TipoMovimiento tipo, int base) {
      final filas = d.porCategoria.where((x) => x.tipo == tipo).toList();
      if (filas.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        for (final f in filas)
          BarraCategoria(
            icono: IconoCategoria(f.categoria, tamano: 40),
            nombre: f.categoria?.nombre ?? 'Sin categoría',
            total: f.total,
            base: base,
            cantidad: f.cantidad,
            ingreso: tipo == TipoMovimiento.ingreso,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PantallaLista.categoria(periodo: d.periodo, categoria: f.categoria, tipo: tipo),
            )),
          ),
      ]);
    }

    return Column(children: [
      bloque('¿En qué se fue?', TipoMovimiento.egreso, d.resumen.egresos),
      bloque('¿De dónde entró?', TipoMovimiento.ingreso, d.resumen.ingresos),
    ]);
  }

  Widget _grafica(_Datos d) {
    final p = d.periodo;
    if (p.tipo == TipoPeriodo.dia) {
      return const Vacio(icono: Icons.bar_chart_rounded, texto: 'Elige Semana, Mes o Año para ver la gráfica.');
    }
    var puntos = d.serie;
    var porMes = p.tipo == TipoPeriodo.anio;
    if (p.tipo == TipoPeriodo.rango && p.dias > 62) {
      // Rangos largos: se agrupan por mes
      final mapa = <String, List<int>>{};
      for (final x in d.serie) {
        final k = x.clave.substring(0, 7);
        final v = mapa.putIfAbsent(k, () => [0, 0]);
        v[0] += x.ingresos;
        v[1] += x.egresos;
      }
      puntos = [for (final e in mapa.entries) PuntoSerie(e.key, e.value[0], e.value[1])];
      porMes = true;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: GraficaBarras(
            puntos: puntos,
            etiqueta: (x) => porMes
                ? mesesCorto[int.parse(x.clave.substring(5, 7)) - 1]
                : (p.tipo == TipoPeriodo.semana ? diasCorto[aFecha(x.clave).weekday - 1] : '${aFecha(x.clave).day}'),
            detalle: (x) => porMes
                ? '${mesesNombre[int.parse(x.clave.substring(5, 7)) - 1]} ${x.clave.substring(0, 4)}'
                : fechaLarga(x.clave),
          ),
        ),
      ),
    );
  }
}
