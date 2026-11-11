# Ficha de Google Play — textos listos para copiar

Todo lo de abajo está escrito contra los límites de Play: **nombre 30**,
**descripción corta 80**, **descripción completa 4.000**. Los conteos están
medidos, no estimados.

> **Antes de gastar los USD 25**: Play **no acepta el APK actual**. Pide un
> `.aab` firmado con una clave de subida propia (el APK de las releases está
> firmado con la clave de debug de Flutter) y, si tu cuenta es personal y nueva,
> una prueba cerrada con **12 testadores durante 14 días continuos** antes de
> poder publicar en producción. Está todo en la sección "Lo que falta", al final.

---

## 1. Nombre de la app

```
Chasqui: chat sin internet
```

26 caracteres. Alternativas medidas: `Chasqui — chat sin internet` (27) o
`Chasqui: chat sin señales` (25). `Chasqui: chat y morse sin señal` son 31 y
**no entra** en el límite de 30.

## 2. Descripción corta

```
Chat por Bluetooth sin internet ni señal, y morse por linterna. Sin cuentas.
```

76 caracteres.

## 3. Descripción completa

```
Chasqui es un chat que funciona cuando no hay internet, ni datos, ni señal de
celular. Los teléfonos se hablan directo por Bluetooth: no hay servidores, no hay
cuentas y no hace falta registrarse.

Sirve para cuando la red no está: cortes de luz, emergencias, zonas rurales,
montaña, festivales o viajes sin cobertura.

QUÉ PUEDE HACER

• Chat de texto de teléfono a teléfono, con estado de enviado y entregado.
• Malla: si dos personas no se ven, un tercer teléfono en medio reenvía el
  mensaje.
• Mensajes cifrados de extremo a extremo.
• Cola de salida: lo que no se pudo entregar se reintenta hasta 24 horas
  después, cuando aparece alguien.
• Canal abierto "Todos" para avisar a cualquiera que esté cerca, sin agregarlo
  como contacto.
• Canales con nombre y contraseña para un grupo, por ejemplo "Refugio Norte".
• Fotos achicadas a unos 40 KB que viajan por la malla en trozos.
• SOS y señales de rescate, con brújula hacia el contacto si los dos comparten
  ubicación.
• Morse por linterna: se escribe una frase y se transmite con el flash.
• Leer morse con la cámara: se apunta a una linterna y aparece el texto.
• Aprender morse: abecedario, práctica y juego de cuatro opciones.

CÓMO FUNCIONA

Cada teléfono con Chasqui es a la vez cliente y repetidor. La app enciende la
radio por ventanas cortas para no comerse la batería y se conecta sola con quien
esté cerca; no hay que emparejar nada.

LO QUE NO HACE

• No reemplaza a WhatsApp cuando hay internet: no sincroniza con la nube ni con
  otras apps.
• El alcance de un salto es de 10 a 30 metros dentro de una casa y hasta 100
  metros a la vista. Más lejos, solo en cadena entre varios teléfonos.
• No se puede escribirle a alguien que no esté cerca o alcanzable por la malla
  en ese momento.
• No tiene llamadas de voz ni video.

PRIVACIDAD

No hay cuentas ni servidores, y la app no se conecta a internet: no recopila ni
envía datos. El historial y las claves se quedan en el teléfono. La ubicación es
opcional y viene apagada.

Chasqui está inspirada en bitchat, la app de malla Bluetooth de Jack Dorsey. Es
un proyecto independiente, en español, pensado para donde la señal no llega.

Requiere Android 7.0 o superior y Bluetooth LE.
```

## 4. Otros campos de la ficha

| Campo | Qué poner |
| --- | --- |
| Categoría | Comunicación |
| Etiquetas | mensajería, sin conexión, Bluetooth, emergencias, morse |
| Correo de contacto | `[TU CORREO]` (Play lo exige y es público) |
| Sitio web | `https://github.com/Chapi-creator/chasqui` |
| Política de privacidad | `https://github.com/Chapi-creator/chasqui/blob/main/docs/publicar/privacidad.md` |
| Gráfico de la ficha | `docs/publicar/grafico-1024x500.png` |
| Icono | `docs/publicar/icono-512.png` |
| Capturas de teléfono | **faltan**: hay que sacarlas en un teléfono real (mínimo 2, máximo 8) |

## 5. Seguridad de los datos (formulario obligatorio)

Respuestas correctas para esta app, que no tiene red:

- **¿Tu app recopila o comparte datos de usuario?** No.
- **¿Los datos se cifran en tránsito?** Marcar "no aplica" (no hay tránsito a
  servidores; el tráfico va cifrado entre teléfonos y no sale de la malla).
- **¿Los usuarios pueden pedir que se borren sus datos?** Sí: se desinstala la
  app o se borra el chat; no hay copia en ningún servidor.
- **¿La app está dirigida a niños?** No.
- **Acceso a la app**: todas las funciones están disponibles sin iniciar sesión.

## 6. Clasificación de contenido

- Violencia, sexo, drogas, apuestas: **ninguna**.
- **Los usuarios pueden comunicarse entre sí**: sí, por Bluetooth, con gente que
  esté físicamente cerca. No hay moderación ni forma de reportar dentro de la
  app (ver "Lo que falta").
- Compras dentro de la app: no. Anuncios: no.

## 7. Lo que falta antes de poder subirla

1. **Un `.aab` firmado con clave de subida.** El APK de las releases está firmado
   con la clave de debug: Play lo rechaza. Hay que crear un keystore propio y
   guardarlo fuera del repo; además, quien ya tenga instalada la versión de
   debug tendrá que desinstalarla para instalar la firmada.
2. **Política de privacidad publicada** con una URL estable: la de arriba sirve
   una vez subida a `main`.
3. **Mínimo 2 capturas de teléfono** (recomendado 5). No se pueden inventar: hay
   que abrir la app en un teléfono y sacarlas.
4. **Reportar y bloquear usuarios.** Play exige que toda app con contenido
   generado por usuarios permita denunciar contenido y bloquear a una persona
   desde la propia app. Chasqui hoy no lo tiene; sin eso la revisión la rechaza.
5. **Prueba cerrada con 12 testadores durante 14 días continuos** si la cuenta es
   personal y se creó después del 13/11/2023. No es un trámite de un día: es
   tiempo de calendario, así que conviene arrancarlo en paralelo a lo demás.
6. **Cuota de inscripción**: USD 25, una sola vez, más verificación de identidad.

## 8. Orden recomendado

1. Sacar las capturas en un teléfono (necesitas una build instalable).
2. Publicar la política de privacidad (ya está en el repo).
3. Crear el keystore y generar el `.aab`.
4. Subir a la pista de **prueba cerrada** con 12 personas y dejarla correr 14 días.
5. Mientras corre: implementar reportar/bloquear.
6. Solicitar acceso a producción con la ficha completa.
