/// Modelos de la contabilidad. Todo el dinero es `int` (pesos enteros).
library;

import '../core/dinero.dart';
import '../core/fechas.dart';

enum TipoMovimiento {
  ingreso('ingreso', 'Entró'),
  egreso('egreso', 'Salió');

  final String clave;
  final String nombre;
  const TipoMovimiento(this.clave, this.nombre);

  static TipoMovimiento desde(String s) =>
      values.firstWhere((t) => t.clave == s, orElse: () => throw FormatException('Tipo inválido: $s'));
}

/// A qué tipo de movimiento aplica una categoría. "Juego" es de ambos:
/// cuando gana es un ingreso y lo que juega es un gasto.
enum TipoCategoria {
  ingreso('ingreso'),
  egreso('egreso'),
  ambos('ambos');

  final String clave;
  const TipoCategoria(this.clave);

  bool sirvePara(TipoMovimiento t) =>
      this == ambos || (this == ingreso ? t == TipoMovimiento.ingreso : t == TipoMovimiento.egreso);

  static TipoCategoria desde(String s) =>
      values.firstWhere((t) => t.clave == s, orElse: () => throw FormatException('Tipo de categoría inválido: $s'));
}

/// Medios de pago comunes en Colombia. Es opcional.
enum MedioPago {
  efectivo('efectivo', 'Efectivo'),
  nequi('nequi', 'Nequi'),
  daviplata('daviplata', 'Daviplata'),
  banco('banco', 'Banco / transferencia'),
  tarjeta('tarjeta', 'Tarjeta'),
  otro('otro', 'Otro');

  final String clave;
  final String nombre;
  const MedioPago(this.clave, this.nombre);

  static MedioPago? desde(String? s) {
    if (s == null) return null;
    for (final m in values) {
      if (m.clave == s) return m;
    }
    throw FormatException('Medio de pago inválido: $s');
  }
}

class Categoria {
  final int? id;
  final String nombre;
  final TipoCategoria tipo;
  final String icono; // clave del catálogo de íconos (ui/iconos.dart)
  final int color; // ARGB
  final int orden;
  final bool archivada;

  const Categoria({
    this.id,
    required this.nombre,
    required this.tipo,
    required this.icono,
    required this.color,
    this.orden = 0,
    this.archivada = false,
  });

  /// Las categorías de juego se muestran aparte (ganado vs. jugado).
  bool get esJuego => nombre.toLowerCase() == 'juego';

  Categoria copiar({String? nombre, TipoCategoria? tipo, String? icono, int? color, int? orden, bool? archivada}) =>
      Categoria(
        id: id,
        nombre: nombre ?? this.nombre,
        tipo: tipo ?? this.tipo,
        icono: icono ?? this.icono,
        color: color ?? this.color,
        orden: orden ?? this.orden,
        archivada: archivada ?? this.archivada,
      );

  Map<String, Object?> aMapa() => {
        if (id != null) 'id': id,
        'nombre': nombre,
        'tipo': tipo.clave,
        'icono': icono,
        'color': color,
        'orden': orden,
        'archivada': archivada ? 1 : 0,
      };

  factory Categoria.deMapa(Map<String, Object?> m) => Categoria(
        id: m['id'] as int?,
        nombre: m['nombre'] as String,
        tipo: TipoCategoria.desde(m['tipo'] as String),
        icono: m['icono'] as String,
        color: m['color'] as int,
        orden: (m['orden'] as int?) ?? 0,
        archivada: (m['archivada'] as int? ?? 0) == 1,
      );
}

class Movimiento {
  final int? id;
  final TipoMovimiento tipo;
  final int monto; // pesos enteros, siempre > 0
  final int? categoriaId;
  final String descripcion; // "¿en qué?" — libre
  final String nota;
  final MedioPago? medio;
  final String fecha; // YYYY-MM-DD
  final String? creadoEn;
  final String? actualizadoEn;
  final String? eliminadoEn;

  const Movimiento({
    this.id,
    required this.tipo,
    required this.monto,
    this.categoriaId,
    this.descripcion = '',
    this.nota = '',
    this.medio,
    required this.fecha,
    this.creadoEn,
    this.actualizadoEn,
    this.eliminadoEn,
  });

  /// Monto con signo: + si entró, − si salió.
  int get conSigno => tipo == TipoMovimiento.ingreso ? monto : -monto;

  Movimiento copiar({
    TipoMovimiento? tipo,
    int? monto,
    int? categoriaId,
    bool quitarCategoria = false,
    String? descripcion,
    String? nota,
    MedioPago? medio,
    bool quitarMedio = false,
    String? fecha,
  }) =>
      Movimiento(
        id: id,
        tipo: tipo ?? this.tipo,
        monto: monto ?? this.monto,
        categoriaId: quitarCategoria ? null : (categoriaId ?? this.categoriaId),
        descripcion: descripcion ?? this.descripcion,
        nota: nota ?? this.nota,
        medio: quitarMedio ? null : (medio ?? this.medio),
        fecha: fecha ?? this.fecha,
        creadoEn: creadoEn,
        actualizadoEn: actualizadoEn,
        eliminadoEn: eliminadoEn,
      );

  Map<String, Object?> aMapa() => {
        if (id != null) 'id': id,
        'tipo': tipo.clave,
        'monto': monto,
        'categoria_id': categoriaId,
        'descripcion': descripcion,
        'nota': nota,
        'medio': medio?.clave,
        'fecha': fecha,
      };

  factory Movimiento.deMapa(Map<String, Object?> m) => Movimiento(
        id: m['id'] as int?,
        tipo: TipoMovimiento.desde(m['tipo'] as String),
        monto: m['monto'] as int,
        categoriaId: m['categoria_id'] as int?,
        descripcion: (m['descripcion'] as String?) ?? '',
        nota: (m['nota'] as String?) ?? '',
        medio: MedioPago.desde(m['medio'] as String?),
        fecha: m['fecha'] as String,
        creadoEn: m['creado_en'] as String?,
        actualizadoEn: m['actualizado_en'] as String?,
        eliminadoEn: m['eliminado_en'] as String?,
      );
}

/// Límites de texto: evitan que un pegado gigante llene el celular.
const maxDescripcion = 120;
const maxNota = 500;
const maxNombreCategoria = 30;

/// Revisa un movimiento antes de guardarlo. Devuelve el error o null.
/// La base de datos vuelve a revisar lo mismo con CHECKs (defensa en capas).
String? validarMovimiento(Movimiento m) {
  if (m.monto <= 0) return 'El valor debe ser mayor que cero';
  if (m.monto > montoMaximo) return 'El máximo por movimiento es ${formatearCOP(montoMaximo)}';
  if (!esFechaValida(m.fecha)) return 'La fecha no es válida';
  if (m.descripcion.length > maxDescripcion) return 'La descripción es muy larga (máximo $maxDescripcion letras)';
  if (m.nota.length > maxNota) return 'La nota es muy larga (máximo $maxNota letras)';
  return null;
}

String? validarCategoria(Categoria c) {
  final n = c.nombre.trim();
  if (n.isEmpty) return 'Ponle un nombre a la categoría';
  if (n.length > maxNombreCategoria) return 'El nombre es muy largo (máximo $maxNombreCategoria letras)';
  return null;
}

/// Totales de un período.
class Resumen {
  final int ingresos;
  final int egresos;
  final int cantidad;
  const Resumen({required this.ingresos, required this.egresos, required this.cantidad});
  static const vacio = Resumen(ingresos: 0, egresos: 0, cantidad: 0);
  int get balance => ingresos - egresos;
}

/// Total de una categoría en un período.
class TotalCategoria {
  final Categoria? categoria; // null = "Sin categoría"
  final TipoMovimiento tipo;
  final int total;
  final int cantidad;
  const TotalCategoria({required this.categoria, required this.tipo, required this.total, required this.cantidad});
}

/// Total por día o por mes (para las gráficas).
class PuntoSerie {
  final String clave; // YYYY-MM-DD o YYYY-MM
  final int ingresos;
  final int egresos;
  const PuntoSerie(this.clave, this.ingresos, this.egresos);
}

/// Balance del juego: lo que ganó contra lo que jugó.
class BalanceJuego {
  final int ganado;
  final int jugado;
  const BalanceJuego(this.ganado, this.jugado);
  int get neto => ganado - jugado;
  bool get hayDatos => ganado > 0 || jugado > 0;
}
