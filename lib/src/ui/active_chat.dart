/// Id del nodo cuyo chat está en pantalla ahora mismo.
///
/// Sirve para no disparar la notificación de "está al alcance" justo cuando el
/// usuario ya está escribiéndole.
String? activeChatPeerId;
