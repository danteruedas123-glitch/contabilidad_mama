import 'package:contabilidad_mama/core/fechas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('valida fechas de calendario reales', () {
    expect(esFechaValida('2026-11-25'), isTrue);
    expect(esFechaValida('2028-02-29'), isTrue); // bisiesto
    expect(esFechaValida('2026-02-29'), isFalse);
    expect(esFechaValida('2026-13-01'), isFalse);
    expect(esFechaValida('2026-11-31'), isFalse);
    expect(esFechaValida('26-11-25'), isFalse);
    expect(esFechaValida('2026/11/25'), isFalse);
    expect(esFechaValida("2026-11-25' OR 1=1"), isFalse);
    expect(esFechaValida(null), isFalse);
  });

  test('sumar días y meses cruza meses y años', () {
    expect(sumarDias('2026-12-31', 1), '2027-01-01');
    expect(sumarDias('2026-03-01', -1), '2026-02-28');
    expect(sumarMeses('2026-01-31', 1), '2026-02-28');
    expect(sumarMeses('2026-12-15', 1), '2027-01-15');
    expect(sumarMeses('2026-03-31', -1), '2026-02-28');
  });

  group('periodos', () {
    const h = '2026-11-25'; // miércoles

    test('día', () {
      final p = Periodo.de(TipoPeriodo.dia, h);
      expect([p.desde, p.hasta], [h, h]);
      expect(p.etiqueta(h), 'Hoy');
      expect(p.mover(-1).etiqueta(h), 'Ayer');
    });

    test('semana de lunes a domingo', () {
      final p = Periodo.de(TipoPeriodo.semana, h);
      expect([p.desde, p.hasta], ['2026-11-23', '2026-11-29']);
      expect(p.dias, 7);
      expect(p.etiqueta(h), 'Esta semana');
      expect(p.mover(-1).desde, '2026-11-16');
      // Un domingo pertenece a la semana que empezó el lunes anterior
      expect(Periodo.de(TipoPeriodo.semana, '2026-11-29').desde, '2026-11-23');
    });

    test('mes, incluido febrero bisiesto', () {
      final p = Periodo.de(TipoPeriodo.mes, h);
      expect([p.desde, p.hasta], ['2026-11-01', '2026-11-30']);
      expect(p.etiqueta(h), 'Noviembre 2026');
      expect(p.mover(1).hasta, '2026-12-31');
      expect(p.mover(3).hasta, '2027-02-28');
      expect(Periodo.de(TipoPeriodo.mes, '2028-02-10').hasta, '2028-02-29');
    });

    test('año', () {
      final p = Periodo.de(TipoPeriodo.anio, h);
      expect([p.desde, p.hasta], ['2026-01-01', '2026-12-31']);
      expect(p.mover(-1).desde, '2025-01-01');
      expect(p.dias, 365);
    });

    test('rango se ordena solo y se mueve en bloques del mismo tamaño', () {
      final p = Periodo.rango('2026-11-10', '2026-11-01');
      expect([p.desde, p.hasta], ['2026-11-01', '2026-11-10']);
      expect(p.dias, 10);
      expect(p.mover(1).desde, '2026-11-11');
      expect(() => Periodo.rango('x', '2026-11-01'), throwsFormatException);
    });

    test('mover 12 meses seguidos vuelve al mismo mes del otro año', () {
      var p = Periodo.de(TipoPeriodo.mes, '2026-01-31');
      for (var i = 0; i < 12; i++) {
        p = p.mover(1);
      }
      expect(p.desde, '2027-01-01');
      expect(p.hasta, '2027-01-31');
    });
  });

  test('textos en español', () {
    expect(fechaLarga('2026-11-25'), 'miércoles 25 de noviembre de 2026');
    expect(fechaCorta('2026-11-25'), '25 nov 2026');
    expect(encabezadoDia('2026-11-24', '2026-11-25'), 'Ayer');
    expect(encabezadoDia('2026-11-20', '2026-11-25'), 'Viernes 20 nov');
    expect(encabezadoDia('2025-11-20', '2026-11-25'), 'Jueves 20 nov 2025');
    expect(rangoCorto('2026-11-23', '2026-11-29'), '23 – 29 nov 2026');
    expect(rangoCorto('2026-10-27', '2026-11-02'), '27 oct – 2 nov 2026');
  });
}
