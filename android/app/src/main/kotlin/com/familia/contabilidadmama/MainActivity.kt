package com.familia.contabilidadmama

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity: la necesita la huella (local_auth).
 *
 * FLAG_SECURE (activado por defecto): impide capturas y grabaciones de
 * pantalla y oculta el contenido en la lista de apps recientes, para que
 * nadie vea las cuentas por encima del hombro. Se puede apagar en Ajustes.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "contabilidad/pantalla")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "protegerPantalla" -> {
                        val activo = call.argument<Boolean>("activo") ?: true
                        if (activo) {
                            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(activo)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
