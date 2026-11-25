# SQLCipher usa JNI: R8 no puede renombrar ni quitar sus clases.
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }
-keep class com.davidmartos96.sqflite_sqlcipher.** { *; }
-dontwarn net.sqlcipher.**
-dontwarn net.zetetic.**
