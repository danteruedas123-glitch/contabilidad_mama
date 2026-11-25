# Mis Cuentas

App Android (Flutter) para llevar la contabilidad personal de mamá: lo que **entra** y lo que **sale**, por día, semana, mes, año o rango, en pesos colombianos.

## Qué hace

- **Anotar rápido**: solo el valor es obligatorio. Categoría, "¿en qué?", medio de pago (Efectivo, Nequi, Daviplata, banco, tarjeta) y nota son opcionales.
- **El valor se escribe como sea**: `50000`, `50.000`, `$50.000`, `50 mil`, `50k`, `20 lucas`, `1,5 millones`, `2 palos`, `1 millón 200 mil`. Si algo es ambiguo (`15.5`), pregunta en vez de adivinar.
- **Categorías** iniciales (Trabajo, Ventas, **Juego**, Mercado, Servicios, Arriendo, Transporte, Salud, Gastos personales, Gastos por fuera, Hogar, Ropa, Familia, Deudas, Celular, Otros). Se pueden crear, renombrar, archivar y cambiar de ícono y color.
- **Juego**: sirve para entradas (lo que gana) y salidas (lo que juega). Hay una tarjeta aparte con ganado, jugado y si va ganando o perdiendo.
- **Resúmenes**: te quedó / entró / salió, comparación con el período anterior, saldo total acumulado, lista agrupada por día, totales por categoría con porcentaje y gráfica por día o por mes.
- **Sugerencias**: lo que más escribe en "¿en qué?" aparece para tocarlo, y trae su categoría.
- **Búsqueda** en toda la historia.
- **Nada se pierde**: borrar manda a la **papelera** (con "Deshacer"), copias automáticas diarias en el celular (guarda las últimas 7), **copias de seguridad cifradas** para guardar en Drive o WhatsApp y exportación a Excel (CSV).

## Seguridad

| Medida | Dónde |
|---|---|
| Base de datos cifrada (SQLCipher AES-256) con llave aleatoria de 256 bits guardada en el Keystore de Android | `lib/datos/abrir_bd.dart`, `lib/seguridad/llave_bd.dart` |
| PIN guardado como PBKDF2-SHA256 con sal; bloqueo progresivo (30 s → 15 min) que sobrevive a cerrar la app y a atrasar el reloj | `lib/seguridad/pin.dart` |
| Código de recuperación (se muestra una sola vez) y huella opcional | `lib/seguridad/pin.dart`, `lib/servicios.dart` |
| Se bloquea al salir de la app (de una, tras 1 min o tras 5 min) | `ControlBloqueo` |
| **Sin permiso de internet** en release: los datos nunca salen del celular | `AndroidManifest.xml` |
| `allowBackup=false` y reglas de extracción: nada va a la nube de Google | `AndroidManifest.xml`, `res/xml/reglas_extraccion_datos.xml` |
| FLAG_SECURE: no deja tomar capturas y oculta la app en "recientes" (se puede apagar) | `MainActivity.kt` |
| Copias con AES-256-GCM + PBKDF2 (210.000 iteraciones); un byte cambiado se detecta; restaurar es todo o nada y comprueba que las sumas cuadren | `lib/respaldo/respaldo.dart` |
| CHECKs en la base: montos enteros positivos con tope, fechas reales, tipos válidos (aunque alguien se salte la app) | `lib/datos/base_datos.dart` |
| CSV protegido contra inyección de fórmulas de Excel | `lib/respaldo/csv.dart` |
| R8 + Dart ofuscado + firma con llave propia | `android/app/build.gradle.kts` |

El dinero siempre es `int` (pesos enteros) y las sumas las hace SQLite en 64 bits.

## Pruebas

```bash
flutter analyze
flutter test                       # 195 pruebas: unidad, contabilidad, seguridad, rendimiento, estrés, interfaz
flutter test integration_test -d emulator-5554   # en Android: cifrado real + app completa
```

| Carpeta | Qué prueba |
|---|---|
| `test/unit` | Lectura y formato de montos, fechas y períodos |
| `test/datos` | Que la contabilidad cuadre al peso (incluye 2.000 movimientos al azar), papelera, categorías |
| `test/seguridad` | Fuerza bruta del PIN, inyección SQL, datos imposibles en la base, copias manipuladas, inyección CSV, configuración Android |
| `test/rendimiento` | Con 60.000 movimientos: inicio completo en ~20 ms, sugerencias en 5 ms |
| `test/estres` | 500 guardados simultáneos, 3.000 operaciones al azar contra un modelo, montos máximos, fuzzing de montos, fechas y copias |
| `test/widgets` | Flujos de mamá: primer uso, anotar, juego, períodos, papelera, salir sin guardar, bloqueo |
| `integration_test` | En el celular: archivo cifrado ilegible sin llave, Keystore y app de punta a punta |

Herramientas (no son pruebas): `integration_test/herramientas/capturas.dart` (capturas con datos de ejemplo) y `tiempos.dart` (mide PIN y apertura de la base en modo profile).

## Compilar e instalar

```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/simbolos
```

- `app-arm64-v8a-release.apk`: casi todos los celulares de los últimos años.
- `app-armeabi-v7a-release.apk`: celulares viejos de 32 bits.

La firma usa `android/key.properties` (ignorado por git), que apunta a `../llaves/mis-cuentas.jks`. **Sin esa llave no se pueden publicar actualizaciones** de la app ya instalada: guarda una copia de la carpeta `llaves/` en un lugar seguro.
