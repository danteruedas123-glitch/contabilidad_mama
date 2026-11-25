/// Fechas de calendario "YYYY-MM-DD". Toda la aritmética se hace con fechas
/// UTC a medianoche para que nunca haya saltos raros por zona horaria.
library;

const mesesNombre = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const mesesCorto = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const diasNombre = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const diasCorto = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

final _patron = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Fecha de hoy según el reloj del celular (en Colombia, hora de Colombia).
String hoy([DateTime? ahora]) => aTexto(ahora ?? DateTime.now());

String aTexto(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool esFechaValida(String? f) {
  if (f == null || !_patron.hasMatch(f)) return false;
  final d = DateTime.tryParse('${f}T00:00:00Z');
  return d != null && aTexto(d) == f && d.year >= 2000 && d.year <= 2200;
}

DateTime aFecha(String f) {
  if (!esFechaValida(f)) throw FormatException('Fecha inválida: $f');
  return DateTime.parse('${f}T00:00:00Z');
}

String sumarDias(String f, int dias) {
  final d = aFecha(f);
  return aTexto(DateTime.utc(d.year, d.month, d.day + dias));
}

String inicioSemana(String f) => sumarDias(f, -(aFecha(f).weekday - 1)); // lunes
String inicioMes(String f) => '${f.substring(0, 7)}-01';
String finMes(String f) {
  final d = aFecha(f);
  return aTexto(DateTime.utc(d.year, d.month + 1, 0));
}

String sumarMeses(String f, int meses) {
  final d = aFecha(f);
  final destino = DateTime.utc(d.year, d.month + meses, 1);
  final ultimo = DateTime.utc(destino.year, destino.month + 1, 0).day;
  return aTexto(DateTime.utc(destino.year, destino.month, d.day > ultimo ? ultimo : d.day));
}

int diasEntre(String desde, String hasta) => aFecha(hasta).difference(aFecha(desde)).inDays;

enum TipoPeriodo { dia, semana, mes, anio, rango }

/// Un rango de fechas con ambos extremos incluidos.
class Periodo {
  final TipoPeriodo tipo;
  final String desde;
  final String hasta;

  Periodo._(this.tipo, this.desde, this.hasta);

  factory Periodo.de(TipoPeriodo tipo, String referencia) {
    switch (tipo) {
      case TipoPeriodo.dia:
        return Periodo._(tipo, referencia, referencia);
      case TipoPeriodo.semana:
        final l = inicioSemana(referencia);
        return Periodo._(tipo, l, sumarDias(l, 6));
      case TipoPeriodo.mes:
        return Periodo._(tipo, inicioMes(referencia), finMes(referencia));
      case TipoPeriodo.anio:
        final a = referencia.substring(0, 4);
        return Periodo._(tipo, '$a-01-01', '$a-12-31');
      case TipoPeriodo.rango:
        return Periodo._(tipo, referencia, referencia);
    }
  }

  factory Periodo.rango(String desde, String hasta) {
    if (!esFechaValida(desde) || !esFechaValida(hasta)) {
      throw const FormatException('Fechas inválidas');
    }
    return desde.compareTo(hasta) <= 0
        ? Periodo._(TipoPeriodo.rango, desde, hasta)
        : Periodo._(TipoPeriodo.rango, hasta, desde);
  }

  int get dias => diasEntre(desde, hasta) + 1;

  bool contiene(String f) => f.compareTo(desde) >= 0 && f.compareTo(hasta) <= 0;

  /// El período siguiente (+1) o anterior (-1) del mismo tamaño.
  Periodo mover(int pasos) {
    switch (tipo) {
      case TipoPeriodo.dia:
        return Periodo.de(tipo, sumarDias(desde, pasos));
      case TipoPeriodo.semana:
        return Periodo.de(tipo, sumarDias(desde, 7 * pasos));
      case TipoPeriodo.mes:
        return Periodo.de(tipo, sumarMeses(desde, pasos));
      case TipoPeriodo.anio:
        return Periodo.de(tipo, sumarMeses(desde, 12 * pasos));
      case TipoPeriodo.rango:
        return Periodo._(tipo, sumarDias(desde, dias * pasos), sumarDias(hasta, dias * pasos));
    }
  }

  /// Texto para mostrar: "Hoy", "Noviembre 2026", "17 – 23 nov 2026"...
  String etiqueta([String? hoyTexto]) {
    final h = hoyTexto ?? hoy();
    switch (tipo) {
      case TipoPeriodo.dia:
        if (desde == h) return 'Hoy';
        if (desde == sumarDias(h, -1)) return 'Ayer';
        return fechaLarga(desde);
      case TipoPeriodo.semana:
        if (contiene(h)) return 'Esta semana';
        return rangoCorto(desde, hasta);
      case TipoPeriodo.mes:
        final d = aFecha(desde);
        return '${_mayus(mesesNombre[d.month - 1])} ${d.year}';
      case TipoPeriodo.anio:
        return 'Año ${desde.substring(0, 4)}';
      case TipoPeriodo.rango:
        return rangoCorto(desde, hasta);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Periodo && other.tipo == tipo && other.desde == desde && other.hasta == hasta;

  @override
  int get hashCode => Object.hash(tipo, desde, hasta);

  @override
  String toString() => 'Periodo($tipo, $desde..$hasta)';
}

String _mayus(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "martes 25 de noviembre de 2026"
String fechaLarga(String f) {
  final d = aFecha(f);
  return '${diasNombre[d.weekday - 1]} ${d.day} de ${mesesNombre[d.month - 1]} de ${d.year}';
}

/// "25 nov 2026" (sin año si [conAnio] es false)
String fechaCorta(String f, {bool conAnio = true}) {
  final d = aFecha(f);
  return '${d.day} ${mesesCorto[d.month - 1]}${conAnio ? ' ${d.year}' : ''}';
}

String rangoCorto(String desde, String hasta) {
  final a = aFecha(desde);
  final b = aFecha(hasta);
  if (a.year == b.year && a.month == b.month) {
    return '${a.day} – ${b.day} ${mesesCorto[b.month - 1]} ${b.year}';
  }
  if (a.year == b.year) {
    return '${a.day} ${mesesCorto[a.month - 1]} – ${b.day} ${mesesCorto[b.month - 1]} ${b.year}';
  }
  return '${fechaCorta(desde)} – ${fechaCorta(hasta)}';
}

/// Encabezado de un día en la lista de movimientos: "Hoy", "Ayer", "Lunes 24 nov".
String encabezadoDia(String f, [String? hoyTexto]) {
  final h = hoyTexto ?? hoy();
  if (f == h) return 'Hoy';
  if (f == sumarDias(h, -1)) return 'Ayer';
  final d = aFecha(f);
  final base = '${_mayus(diasNombre[d.weekday - 1])} ${d.day} ${mesesCorto[d.month - 1]}';
  return d.year.toString() == h.substring(0, 4) ? base : '$base ${d.year}';
}
