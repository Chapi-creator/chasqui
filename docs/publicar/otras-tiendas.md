# Otras tiendas — textos listos para copiar

Estas tiendas **aceptan el APK tal cual**, sin `.aab` ni clave de subida nueva.
Todas tienen revisión manual, así que la ficha importa: sin capturas ni
descripción, la rechazan o la dejan sin visibilidad.

Lo que conviene tener a mano en todas: `dist/Chasqui-1.1.2.apk`, el icono
`docs/publicar/icono-512.png`, el gráfico `docs/publicar/grafico-1024x500.png`, y
capturas sacadas en un teléfono (mínimo 2).

---

## 1. Textos base (reutilizables)

### Línea corta (para campos de 1 línea)

```
Chat y morse por Bluetooth, sin internet ni señal, sin cuentas ni servidores.
```

77 caracteres.

### Párrafo corto (para fichas que piden una descripción breve)

```
Chasqui es un chat que funciona sin internet, sin datos y sin señal de celular:
los teléfonos se hablan directo por Bluetooth y se reenvían los mensajes entre
ellos. Trae además morse por linterna, para transmitir y leer mensajes con el
flash y la cámara. No tiene cuentas, no usa servidores y la ubicación es opcional.
```

### Descripción larga

Usar la misma de Google Play (sección 3 de `google-play.md`): no tiene límite más
chico en estas tiendas.

### Novedades de la 1.1.2 (para "What's new")

```
Corrige un fallo del lector de morse que inventaba un destello al empezar y hacía
leer mal el mensaje a cualquier velocidad (SOS salía HOS). El acierto medido sube
de 74,5 % a 83,5 % en las pruebas simuladas: a ritmo lento ya no falla ninguna
lectura ni con cámaras de 10 imágenes por segundo.
```

---

## 2. Uptodown

1. Entrar a la zona de desarrolladores: <https://en.uptodown.com/developers-zone>.
2. Subir el APK y completar: nombre, categoría **Comunicación**, descripción
   corta y larga, icono, capturas.
3. Adjuntar la captura de pantalla no aplica: Uptodown toma las capturas del
   formulario.

Campos:

| Campo | Valor |
| --- | --- |
| Nombre | `Chasqui: chat sin internet` |
| Categoría | Comunicación |
| Descripción corta | la "línea corta" de arriba |
| Descripción | la larga de Google Play |
| Licencia | MIT (código abierto) |
| Web | `https://github.com/Chapi-creator/chasqui` |

## 3. APKPure

1. Crear cuenta en <https://apkpure.com/submit-apk> (gratis).
2. Subir el `.apk` (acepta hasta 2 GB) y esperar la revisión manual.
3. Desde el Developer Console se actualiza con cada versión.

Campos: nombre, la "línea corta", la descripción larga, el bloque de novedades,
categoría **Comunicación**, icono y capturas.

## 4. Aptoide

1. Alta en Aptoide Connect (<https://www.aptoide.com/>, sección desarrolladores).
2. Subir el APK; Aptoide firma aparte su propio canal si se quiere.
3. Igual que las anteriores: nombre, descripción corta y larga, capturas.

Ojo: Aptoide muestra la firma del APK. Si es la de debug, avisa; conviene subir
la versión firmada con la clave propia cuando exista.

## 5. Amazon Appstore

1. Cuenta de desarrollador en <https://developer.amazon.com/apps-and-games>
   (sin cuota de inscripción al momento de escribir esto; confirmar en el alta).
2. Subir el APK, **desactivar "Apply Amazon DRM"** para que no interfiera con
   Bluetooth ni con el servicio en primer plano.
3. Misma ficha: nombre, descripción corta y larga, categoría Comunicación.

## 6. F-Droid (para más adelante)

No acepta APKs subidos a mano: **compila desde el código fuente y firma con su
propia clave**. Para entrar hace falta:

- Que todo sea software libre (Chasqui es MIT; hay que revisar que ninguna
  dependencia traiga binarios propietarios).
- Una receta de compilación (metadatos `fdroiddata`) con la versión, el commit y
  el comando de build.
- Cumplir sus reglas: sin rastreo, sin publicidad, sin dependencias que llamen a
  servicios propietarios.

Es la tienda que más confianza da a quien busca apps sin nube, pero es trabajo de
mantenimiento: cada versión necesita su receta.

---

## 7. Antes de subir a cualquiera: lo que conviene arreglar

- **Firma**: el APK actual está firmado con la clave de debug. Las tiendas
  alternativas lo aceptan, pero Play Protect avisa "aplicación no reconocida" y
  cada actualización mantiene ese aviso. Con una clave propia el aviso desaparece.
- **Capturas**: sin capturas, estas tiendas suelen rechazar la ficha.
- **Política de privacidad**: publicar `privacidad.md` y pegar su URL. Es
  obligatoria en varias de ellas y ayuda en todas.
- **Número de versión**: cada subida necesita `versionCode` mayor. Ya está en 22.
