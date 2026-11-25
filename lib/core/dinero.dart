/// Dinero en pesos colombianos ENTEROS (sin centavos), igual que en
/// Quechimba: los montos viajan y se guardan como `int`, nunca como `double`,
/// para que las sumas nunca pierdan ni un peso por redondeo.
library;

/// Monto máximo de un solo movimiento: $100.000.000.000 (cien mil millones).
/// Evita errores de dedo (un cero de más) y desbordes en las sumas.
const int montoMaximo = 100000000000;

/// "$1.250.000" · "-$5.000"
String formatearCOP(int valor) {
  final negativo = valor < 0;
  final texto = _conPuntos(valor.abs());
  return '${negativo ? '-' : ''}\$$texto';
}

/// Versión corta para gráficas: "$850 mil", "$1,2 M", "$3.400 M".
String formatearCorto(int valor) {
  final n = valor.abs();
  final signo = valor < 0 ? '-' : '';
  if (n >= 1000000) {
    final millones = n / 1000000;
    final texto = millones >= 100
        ? _conPuntos(millones.round())
        : millones.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '');
    return '$signo\$$texto M';
  }
  if (n >= 1000) return '$signo\$${_conPuntos((n / 1000).round())} mil';
  return '$signo\$$n';
}

String _conPuntos(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Resultado de interpretar lo que la persona escribió como monto.
class MontoLeido {
  final int? valor;
  final String? error;
  const MontoLeido.ok(int this.valor) : error = null;
  const MontoLeido.error(String this.error) : valor = null;
  bool get valido => valor != null;
}

const _multiplicadores = <String, int>{
  'mil': 1000,
  'k': 1000,
  'luca': 1000,
  'lucas': 1000,
  'millon': 1000000,
  'millones': 1000000,
  'mill': 1000000,
  'm': 1000000,
  'palo': 1000000,
  'palos': 1000000,
};

/// Lee un monto escrito de forma flexible, como lo escribiría cualquiera:
///
/// - `50000`, `50.000`, `$ 50.000`, `50.000,00`
/// - `50 mil`, `50mil`, `50k`, `50 lucas`
/// - `1,5 millones`, `1.5M`, `2 palos`
/// - `1 millón 200 mil` → 1.200.000
///
/// Si algo es ambiguo (por ejemplo `15.5`: ¿15 pesos con 50 o 15.500?) se
/// rechaza con un mensaje claro en vez de adivinar: es mejor preguntar que
/// guardar una plata equivocada.
MontoLeido leerMonto(String? entrada) {
  if (entrada == null) return const MontoLeido.error('Escribe cuánto fue');
  if (entrada.length > 60) return const MontoLeido.error('Ese valor es demasiado largo');
  var t = entrada.toLowerCase().trim();
  t = t
      .replaceAll('ó', 'o')
      .replaceAll(RegExp(r'\$|cop|pesos?'), ' ')
      .replaceAll(RegExp(r'\s+y\s+'), ' ')
      .trim();
  if (t.isEmpty) return const MontoLeido.error('Escribe cuánto fue');
  if (t.startsWith('-')) {
    return const MontoLeido.error('Escribe el valor sin signo menos; elige arriba si entró o salió');
  }

  // Separa números de palabras: "1,5millones" → "1,5 millones"
  t = t.replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}');
  final partes = t
      .split(RegExp(r'\s+'))
      .map((p) => p == 'un' || p == 'una' ? '1' : p)
      .toList();

  var total = 0;
  var i = 0;
  var huboNumero = false;
  while (i < partes.length) {
    final numTexto = partes[i];
    if (!RegExp(r'^[\d.,]+$').hasMatch(numTexto)) {
      return MontoLeido.error('No entiendo "$numTexto". Escribe por ejemplo 50.000 o 50 mil');
    }
    int? mult;
    // Admite "mil millones" (1.000.000.000)
    if (i + 1 < partes.length && _multiplicadores.containsKey(partes[i + 1])) {
      mult = _multiplicadores[partes[i + 1]];
      if (partes[i + 1] == 'mil' && i + 2 < partes.length && _millones(partes[i + 2])) {
        mult = 1000000000;
        i++;
      }
      i++;
    }
    final valor = mult == null ? _numeroPlano(numTexto) : _numeroConMultiplicador(numTexto, mult);
    if (valor.error != null) return valor;
    total += valor.valor!;
    if (total > montoMaximo) {
      return MontoLeido.error('El máximo por movimiento es ${formatearCOP(montoMaximo)}');
    }
    huboNumero = true;
    i++;
  }
  if (!huboNumero || total <= 0) return const MontoLeido.error('El valor debe ser mayor que cero');
  return MontoLeido.ok(total);
}

bool _millones(String p) => p == 'millones' || p == 'millon' || p == 'm' || p == 'mill';

MontoLeido _numeroPlano(String s) {
  if (RegExp(r'^\d+$').hasMatch(s)) return _entero(s);
  // Miles con punto o coma bien ubicados: 1.250.000 / 1,250,000
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s) || RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(s)) {
    return _entero(s.replaceAll(RegExp(r'[.,]'), ''));
  }
  // Con centavos: 50.000,00 · 50000.00 · 1.250.000,50
  final m = RegExp(r'^(\d{1,3}(?:[.,]\d{3})*|\d+)[.,](\d{1,2})$').firstMatch(s);
  if (m != null) {
    final enteros = m[1]!.replaceAll(RegExp(r'[.,]'), '');
    if (int.parse(m[2]!) == 0) return _entero(enteros);
    return MontoLeido.error('Los pesos no llevan centavos. ¿Quisiste decir ${formatearCOP(_estimado(s))}?');
  }
  return MontoLeido.error('No entiendo "$s". Escribe por ejemplo 50.000');
}

/// Sugerencia para "15.5" → 15.500 (lo más probable en Colombia).
int _estimado(String s) {
  final m = RegExp(r'^([\d.,]*?)[.,](\d{1,2})$').firstMatch(s)!;
  final ent = int.tryParse(m[1]!.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
  return ent * 1000 + int.parse(m[2]!.padRight(3, '0'));
}

MontoLeido _numeroConMultiplicador(String s, int mult) {
  // "1.250 mil" en Colombia es 1.250 × 1.000 (el punto separa miles)
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    final r = BigInt.parse(s.replaceAll('.', '')) * BigInt.from(mult);
    if (r > BigInt.from(montoMaximo)) {
      return MontoLeido.error('El máximo por movimiento es ${formatearCOP(montoMaximo)}');
    }
    return MontoLeido.ok(r.toInt());
  }
  final m =RegExp(r'^(\d+)(?:[.,](\d{1,6}))?$').firstMatch(s);
  if (m == null) return MontoLeido.error('No entiendo "$s"');
  final ent = BigInt.parse(m[1]!);
  final dec = m[2] ?? '';
  final escala = BigInt.from(10).pow(dec.length);
  final numerador = (ent * escala + BigInt.parse(dec.isEmpty ? '0' : dec)) * BigInt.from(mult);
  if (numerador % escala != BigInt.zero) {
    return MontoLeido.error('"$s" no da pesos exactos');
  }
  final r = numerador ~/ escala;
  if (r > BigInt.from(montoMaximo)) {
    return MontoLeido.error('El máximo por movimiento es ${formatearCOP(montoMaximo)}');
  }
  return MontoLeido.ok(r.toInt());
}

MontoLeido _entero(String digitos) {
  if (digitos.length > 12) {
    return MontoLeido.error('El máximo por movimiento es ${formatearCOP(montoMaximo)}');
  }
  final n = int.parse(digitos);
  if (n > montoMaximo) {
    return MontoLeido.error('El máximo por movimiento es ${formatearCOP(montoMaximo)}');
  }
  return MontoLeido.ok(n);
}

/// Variación porcentual redondeada a 1 decimal; null si no hay base.
double? variacion(int actual, int anterior) {
  if (anterior == 0) return null;
  return ((actual - anterior) / anterior * 1000).round() / 10;
}
