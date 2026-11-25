import 'package:flutter/material.dart';

/// Íconos disponibles para las categorías. Se guardan por nombre (no por
/// código) para que Flutter pueda recortar la fuente de íconos del APK.
const iconosCategoria = <String, IconData>{
  'trabajo': Icons.work_rounded,
  'ventas': Icons.storefront_rounded,
  'regalo': Icons.card_giftcard_rounded,
  'prestamo': Icons.handshake_rounded,
  'juego': Icons.casino_rounded,
  'mercado': Icons.shopping_basket_rounded,
  'servicios': Icons.lightbulb_rounded,
  'casa': Icons.house_rounded,
  'transporte': Icons.directions_bus_rounded,
  'salud': Icons.medical_services_rounded,
  'personal': Icons.face_retouching_natural_rounded,
  'salidas': Icons.celebration_rounded,
  'hogar': Icons.chair_rounded,
  'ropa': Icons.checkroom_rounded,
  'familia': Icons.family_restroom_rounded,
  'deuda': Icons.receipt_long_rounded,
  'celular': Icons.smartphone_rounded,
  'otros': Icons.more_horiz_rounded,
  'comida': Icons.restaurant_rounded,
  'cafe': Icons.local_cafe_rounded,
  'mascota': Icons.pets_rounded,
  'educacion': Icons.school_rounded,
  'iglesia': Icons.church_rounded,
  'belleza': Icons.content_cut_rounded,
  'ahorro': Icons.savings_rounded,
  'banco': Icons.account_balance_rounded,
  'moto': Icons.two_wheeler_rounded,
  'carro': Icons.directions_car_rounded,
  'gasolina': Icons.local_gas_station_rounded,
  'farmacia': Icons.local_pharmacy_rounded,
  'deporte': Icons.sports_soccer_rounded,
  'viaje': Icons.flight_rounded,
  'bebe': Icons.child_friendly_rounded,
  'herramienta': Icons.build_rounded,
  'loteria': Icons.confirmation_number_rounded,
  'dinero': Icons.payments_rounded,
  'tienda': Icons.local_grocery_store_rounded,
  'internet': Icons.wifi_rounded,
  'agua': Icons.water_drop_rounded,
  'gas': Icons.local_fire_department_rounded,
};

IconData iconoDe(String clave) => iconosCategoria[clave] ?? Icons.label_rounded;

const coloresCategoria = <int>[
  0xFF2E7D32, 0xFF00897B, 0xFF0277BD, 0xFF1565C0, 0xFF3949AB, 0xFF6A1B9A,
  0xFF8E24AA, 0xFFAD1457, 0xFFD81B60, 0xFFC62828, 0xFFEF6C00, 0xFFF9A825,
  0xFF6D4C41, 0xFF4E342E, 0xFF455A64, 0xFF757575,
];
