# Política de privacidad de Chasqui

**Última actualización: 11 de noviembre de 2026.**

Chasqui es una aplicación para Android que permite enviar mensajes entre
teléfonos cercanos usando Bluetooth, sin internet, sin cuentas y sin servidores.
Esta política explica qué pasa con los datos cuando se usa la app.

## Lo esencial

**Chasqui no recopila datos personales, no los envía a ningún servidor y no tiene
forma de hacerlo: la app no se conecta a internet.**

No hay cuentas, no hay registro, no hay analítica, no hay publicidad y no hay
herramientas de seguimiento de terceros.

## Qué datos se quedan en el teléfono

Todo lo que la app guarda vive únicamente en el almacenamiento del dispositivo:

- **Mensajes e historial** de chats y canales.
- **Tu nombre y tu clave** de identidad, generada en el teléfono.
- **Contactos y canales** que agregaste, con sus claves.
- **Fotos** que recibiste o que enviaste, hasta un máximo de 80.
- **Ajustes** (ritmo de morse, modo de batería, preferencias).

Nada de eso se sube a ningún lado. Si desinstalás la app o borrás sus datos, se
borra todo. No hay copia de respaldo en ningún servidor porque no existe tal
servidor.

## Permisos y para qué se usan

| Permiso | Para qué | Obligatorio |
| --- | --- | --- |
| Bluetooth (cercanía y conexión) | Descubrir teléfonos cercanos y enviar mensajes. | Sí |
| Cámara | Leer códigos QR de contacto y leer morse por destellos. No graba ni guarda imágenes. | No |
| Ubicación | Solo si la activás: compartir tu posición con un contacto y calcular distancia y rumbo. Viene apagada. | No |
| Notificaciones | Avisar de mensajes nuevos y mantener el servicio de radio activo. | No |

Android exige el permiso de ubicación para escanear Bluetooth en algunas
versiones: en ese caso se usa solo para eso y la app no guarda ni transmite tu
posición salvo que actives "compartir ubicación" en un chat, y en ese caso viaja
cifrada y solo a esa persona.

## A quién le llegan tus mensajes

Los mensajes van de teléfono a teléfono por Bluetooth y pueden pasar por
teléfonos intermedios de otras personas que tengan la app (la malla). Esos
teléfonos **reenvían paquetes cifrados que no pueden leer**: el cifrado es de
extremo a extremo (X25519 + AES-256-GCM).

El canal "Todos" y los canales con nombre son distintos: usan una clave de grupo,
así que cualquiera que conozca el nombre y la contraseña del canal puede leer lo
que se escribe ahí. No los uses para información privada.

## Menores

La app no está dirigida a menores de 13 años y no recopila datos de nadie, así
que no hay información de menores que tratar. Los chats son entre personas que
están físicamente cerca y no hay moderación central.

## Cambios

Si en el futuro una versión agregara algo que implique enviar datos (por ejemplo,
un servicio opcional en la nube), esta política se actualizará antes de publicar
esa versión y el cambio se verá en el historial del repositorio.

## Contacto

Dudas sobre esta política: **`[TU CORREO]`** o un issue en
<https://github.com/Chapi-creator/chasqui/issues>.

---

*Chasqui está inspirada en bitchat, la app de malla Bluetooth de Jack Dorsey y
permissionlesstech, de dominio público.*
