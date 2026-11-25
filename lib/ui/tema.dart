import 'package:flutter/material.dart';

const colorIngreso = Color(0xFF1B7F3B);
const colorEgreso = Color(0xFFC62828);
const colorMarca = Color(0xFF00695C);

ThemeData temaApp(Brightness brillo) {
  final esquema = ColorScheme.fromSeed(seedColor: colorMarca, brightness: brillo);
  final base = ThemeData(colorScheme: esquema, useMaterial3: true);
  // El tamaño de letra sigue el ajuste del celular (Ajustes → Pantalla).
  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: esquema.surface,
      foregroundColor: esquema.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: esquema.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: esquema.surfaceContainerLowest,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Color del valor según si entró (verde) o salió (rojo), legible en ambos temas.
Color colorTipo(BuildContext context, bool ingreso) {
  final oscuro = Theme.of(context).brightness == Brightness.dark;
  if (ingreso) return oscuro ? const Color(0xFF66BB6A) : colorIngreso;
  return oscuro ? const Color(0xFFEF5350) : colorEgreso;
}
