/// Exportación a CSV para abrir en Excel o Google Sheets.
///
/// Seguridad: una descripción como `=HYPERLINK(...)` o `+cmd|...` se
/// ejecutaría como fórmula al abrir el archivo en Excel ("inyección CSV").
/// Toda celda de texto que empiece por = + - @ tabulador o retorno se
/// neutraliza con un apóstrofo.
library;

import 'dart:convert';

import '../datos/modelos.dart';

const _sep = ';'; // Excel en español (Colombia) separa columnas con punto y coma

String celdaSegura(String valor) {
  var v = valor;
  if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
  if (v.contains(_sep) || v.contains('"') || v.contains('\n') || v.contains('\r')) {
    v = '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// Genera el CSV (con BOM para que Excel lea bien las tildes).
List<int> generarCsv(List<Movimiento> movimientos, Map<int, Categoria> categorias, {Map<int, Cliente> clientes = const {}}) {
  final b = StringBuffer('﻿');
  b.writeln(['Fecha', 'Tipo', 'Valor', 'Valor con signo', 'Categoría', 'Cliente', '¿En qué?', 'Medio de pago', 'Nota'].join(_sep));
  for (final m in movimientos) {
    b.writeln([
      m.fecha,
      m.tipo == TipoMovimiento.ingreso ? 'Entró' : 'Salió',
      '${m.monto}',
      '${m.conSigno}',
      celdaSegura(categorias[m.categoriaId]?.nombre ?? 'Sin categoría'),
      celdaSegura(clientes[m.clienteId]?.nombre ?? ''),
      celdaSegura(m.descripcion),
      celdaSegura(m.medio?.nombre ?? ''),
      celdaSegura(m.nota),
    ].join(_sep));
  }
  return utf8.encode(b.toString());
}
