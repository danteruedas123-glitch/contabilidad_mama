import 'modelos.dart';

/// Categorías con las que arranca la app. Mamá puede renombrarlas,
/// archivarlas o crear las suyas.
const categoriasIniciales = <Categoria>[
  // Entradas
  Categoria(nombre: 'Trabajo', tipo: TipoCategoria.ingreso, icono: 'trabajo', color: 0xFF2E7D32, orden: 1),
  Categoria(nombre: 'Ventas', tipo: TipoCategoria.ingreso, icono: 'ventas', color: 0xFF00897B, orden: 2),
  Categoria(nombre: 'Regalos y ayudas', tipo: TipoCategoria.ingreso, icono: 'regalo', color: 0xFF8E24AA, orden: 3),
  Categoria(nombre: 'Préstamos recibidos', tipo: TipoCategoria.ingreso, icono: 'prestamo', color: 0xFF5D4037, orden: 4),
  // De los dos lados: lo que gana y lo que juega
  Categoria(nombre: 'Juego', tipo: TipoCategoria.ambos, icono: 'juego', color: 0xFFF9A825, orden: 5),
  // Salidas
  Categoria(nombre: 'Mercado y comida', tipo: TipoCategoria.egreso, icono: 'mercado', color: 0xFFEF6C00, orden: 10),
  Categoria(nombre: 'Servicios', tipo: TipoCategoria.egreso, icono: 'servicios', color: 0xFF1565C0, orden: 11),
  Categoria(nombre: 'Arriendo', tipo: TipoCategoria.egreso, icono: 'casa', color: 0xFF6D4C41, orden: 12),
  Categoria(nombre: 'Transporte', tipo: TipoCategoria.egreso, icono: 'transporte', color: 0xFF455A64, orden: 13),
  Categoria(nombre: 'Salud', tipo: TipoCategoria.egreso, icono: 'salud', color: 0xFFC62828, orden: 14),
  Categoria(nombre: 'Gastos personales', tipo: TipoCategoria.egreso, icono: 'personal', color: 0xFFAD1457, orden: 15),
  Categoria(nombre: 'Gastos por fuera', tipo: TipoCategoria.egreso, icono: 'salidas', color: 0xFF6A1B9A, orden: 16),
  Categoria(nombre: 'Hogar', tipo: TipoCategoria.egreso, icono: 'hogar', color: 0xFF00838F, orden: 17),
  Categoria(nombre: 'Ropa', tipo: TipoCategoria.egreso, icono: 'ropa', color: 0xFFD81B60, orden: 18),
  Categoria(nombre: 'Familia', tipo: TipoCategoria.egreso, icono: 'familia', color: 0xFF3949AB, orden: 19),
  Categoria(nombre: 'Deudas y cuotas', tipo: TipoCategoria.egreso, icono: 'deuda', color: 0xFF4E342E, orden: 20),
  Categoria(nombre: 'Celular e internet', tipo: TipoCategoria.egreso, icono: 'celular', color: 0xFF0277BD, orden: 21),
  // Para lo que no encaja en ninguna
  Categoria(nombre: 'Otros', tipo: TipoCategoria.ambos, icono: 'otros', color: 0xFF757575, orden: 99),
];
