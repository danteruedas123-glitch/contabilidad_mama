// Mide en el celular (correr en modo profile, que se comporta como release):
//   flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/herramientas/tiempos.dart -d <dispositivo>
import 'package:contabilidad_mama/datos/abrir_bd.dart';
import 'package:contabilidad_mama/seguridad/almacen_seguro.dart';
import 'package:contabilidad_mama/seguridad/cripto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('tiempos', (tester) async {
    final res = <String, int>{};
    for (final it in [30000, 210000]) {
      final sw = Stopwatch()..start();
      await derivarClave('2580', bytesAleatorios(16), it);
      res['pbkdf2_$it'] = sw.elapsedMilliseconds;
    }
    final sw = Stopwatch()..start();
    final db = await abrirBDCifrada(AlmacenKeystore());
    res['abrir_bd_cifrada'] = sw.elapsedMilliseconds;
    await db.close();
    binding.reportData = res;
  });
}
