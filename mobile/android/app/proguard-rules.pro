# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# SQLCipher and SQLite
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-keep class org.sqlite.** { *; }
-dontwarn net.sqlcipher.**

# Cryptography & Local Auth
-keep class com.cryptography.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }

# Native SW-budget Services & Broadcast Receivers
-keep class com.swbudget.app.** { *; }
