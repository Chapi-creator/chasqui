/// Versión visible en Ajustes.
///
/// Va aparte del `pubspec.yaml` porque la UI no puede leerlo en tiempo de
/// ejecución sin añadir otra dependencia: una sola cadena que hay que subir
/// junto con `version:` en cada release.
const String appVersion = '0.8.0';
