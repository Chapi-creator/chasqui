# Descargar Chasqui

**`Chasqui.apk`** es la última versión de la app, lista para instalar.
No hace falta compilar nada ni tener Flutter: bajá el archivo y pasalo al
teléfono.

- **Versión**: 1.1.1 (versionCode 21)
- **Tamaño**: 71,8 MB (todas las arquitecturas; el escáner de QR es lo que más
  pesa)
- **SHA-256**: `e736c10ef3b35471eea3634f9c2d37b633e2daa1d8ea7a3bd70080547839824f`
- **Requisitos**: Android 7.0 o más (API 24) con Bluetooth LE

## Cómo instalarlo

1. Abrí `Chasqui.apk` en la página de GitHub y tocá **Download** (o el ícono de
   descarga). Si estás en el teléfono, se baja directo al teléfono.
2. Abrilo desde las descargas. Android va a avisar que es de origen
   desconocido: permití **"Instalar apps desconocidas"** para el navegador o
   para Archivos, solo esa vez.
3. Al abrir la app, poné tu nombre (es obligatorio: es lo que ven los demás en
   la malla) y seguí la introducción.

Si ya tenías una versión anterior de Chasqui, se actualiza encima y conserva
tus contactos, chats y canales. Si venías de **SinRed** (el nombre viejo, con
otro identificador), hay que desinstalarla o convivir con las dos.

## Qué tiene esta versión

Nombre obligatorio al instalar, guía de uso completa dentro de la app, canales
con nombre (cualquiera crea uno y los demás entran con el mismo nombre, con
clave opcional) y **fotos por la malla**. La 1.1.1 agrega un aviso de velocidad
en el morse: a 120 ms por punto hace falta que la otra cámara vea 30 imágenes
por segundo. El detalle está en el
[README](../README.md#10-qué-cambió-en-la-110).

**Importante**: los canales con nombre y las fotos solo funcionan entre
teléfonos con la 1.1.0 o mayor. Un teléfono con una versión vieja descarta esos
mensajes. La malla, los chats privados y el canal "Todos" siguen funcionando
entre versiones.

## Notas

- Está firmado con la clave de debug de Flutter: sirve para probar y compartir,
  no para publicar en Play Store.
- Este archivo se reemplaza en cada versión: el enlace es siempre el mismo y
  baja lo último. El SHA-256 de arriba identifica exactamente esta compilación;
  si querés comprobar que la descarga no se corrompió, calculalo en el teléfono
  o en la computadora y compará.
- Las versiones anteriores quedan como adjuntos en
  [Releases](https://github.com/Chapi-creator/chasqui/releases).
