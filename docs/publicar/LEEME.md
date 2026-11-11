# Materiales para publicar Chasqui

Todo lo necesario para llenar las fichas de las tiendas. Los textos están
medidos contra los límites de cada una.

| Archivo | Para qué |
| --- | --- |
| [`google-play.md`](google-play.md) | Nombre, descripción corta y larga, campos de la ficha, formulario de datos y clasificación de contenido. Incluye lo que bloquea la subida. |
| [`otras-tiendas.md`](otras-tiendas.md) | Uptodown, APKPure, Aptoide, Amazon y F-Droid: qué pide cada una, con textos cortos y "novedades". |
| [`privacidad.md`](privacidad.md) | Política de privacidad lista para publicar (falta reemplazar `[TU CORREO]`). |
| [`icono-512.png`](icono-512.png) | Ícono 512×512 en PNG con transparencia (lo pide Play). |
| [`grafico-1024x500.png`](grafico-1024x500.png) | Gráfico destacado 1024×500. |

## Lo que falta (no se puede generar desde el repo)

- **Capturas de pantalla** (mínimo 2, ideal 4–6): hay que abrir la app en un
  teléfono real. Sin capturas, las tiendas rechazan o esconden la ficha.
- **`.aab` firmado con clave propia** para Play (el APK de las releases va con la
  clave de debug).
- **Reemplazar `[TU CORREO]`** en la ficha y en la política de privacidad.
- **URL pública de la política**: `https://github.com/Chapi-creator/chasqui/blob/main/docs/publicar/privacidad.md`
  funciona en cuanto el archivo esté en `main`.

## Orden sugerido

1. Copiar `google-play.md` sección por sección en Play Console.
2. Publicar la política de privacidad (ya está en el repo).
3. Sacar las capturas.
4. Subir a prueba cerrada de Play (12 testadores, 14 días) y, en paralelo, subir
   el APK a Uptodown y APKPure, que no exigen nada de eso.
