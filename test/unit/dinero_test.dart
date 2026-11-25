import 'package:contabilidad_mama/core/dinero.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatearCOP', () {
    test('pone puntos de miles y signo', () {
      expect(formatearCOP(0), r'$0');
      expect(formatearCOP(950), r'$950');
      expect(formatearCOP(1000), r'$1.000');
      expect(formatearCOP(1250000), r'$1.250.000');
      expect(formatearCOP(-5000), r'-$5.000');
      expect(formatearCOP(montoMaximo), r'$100.000.000.000');
    });

    test('formato corto para gráficas', () {
      expect(formatearCorto(500), r'$500');
      expect(formatearCorto(850000), r'$850 mil');
      expect(formatearCorto(1200000), r'$1,2 M');
      expect(formatearCorto(3000000), r'$3 M');
      expect(formatearCorto(-45000), r'-$45 mil');
    });
  });

  group('leerMonto: formas flexibles de escribir la plata', () {
    final casos = <String, int>{
      '50000': 50000,
      '50.000': 50000,
      r'$50.000': 50000,
      r'$ 50.000': 50000,
      '  50.000  ': 50000,
      '50.000,00': 50000,
      '50000.00': 50000,
      '1.250.000': 1250000,
      '1,250,000': 1250000,
      '50 mil': 50000,
      '50mil': 50000,
      '50 MIL': 50000,
      '50k': 50000,
      '20 lucas': 20000,
      '1 luca': 1000,
      '1,5 millones': 1500000,
      '1.5M': 1500000,
      '2 palos': 2000000,
      '1 millón': 1000000,
      'un millón': 1000000,
      '1 millón 200 mil': 1200000,
      '1 millon y 200 mil': 1200000,
      '2 millones 350 mil 500': 2350500,
      '1.250 mil': 1250000,
      '2,5 mil': 2500,
      '3 mil millones': 3000000000,
      '50.000 pesos': 50000,
      '15000 cop': 15000,
      '1': 1,
    };
    casos.forEach((entrada, esperado) {
      test('"$entrada" → $esperado', () {
        final r = leerMonto(entrada);
        expect(r.error, isNull);
        expect(r.valor, esperado);
      });
    });

    final malos = [
      null, '', '   ', '0', '0,00', '-5000', 'abc', 'cincuenta', '15.5', '1.25', '50.000,50',
      '1,2345 mil', '\$', 'mil', '1.2.3', '12..000', '100000000001', '101 mil millones',
      '999999999999999999999999', '5000 dolares', '=1+1', "'; DROP TABLE movimientos; --",
    ];
    for (final m in malos) {
      test('rechaza ${m == null ? 'null' : '"$m"'}', () {
        final r = leerMonto(m);
        expect(r.valido, isFalse, reason: 'valor leído: ${r.valor}');
        expect(r.error, isNotEmpty);
      });
    }

    test('si es ambiguo sugiere lo más probable', () {
      expect(leerMonto('15.5').error, contains(r'$15.500'));
    });

    test('el máximo exacto sí se acepta', () {
      expect(leerMonto('100.000.000.000').valor, montoMaximo);
      expect(leerMonto('100 mil millones').valor, montoMaximo);
    });

    test('texto enorme se rechaza sin procesarlo', () {
      expect(leerMonto('1' * 10000).valido, isFalse);
    });
  });

  test('variación porcentual', () {
    expect(variacion(150, 100), 50.0);
    expect(variacion(50, 100), -50.0);
    expect(variacion(100, 0), isNull);
    expect(variacion(1, 3), -66.7);
  });
}
