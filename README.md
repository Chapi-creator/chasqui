# SinRed

Chat tipo WhatsApp que funciona **sin internet, sin operador y sin servidores**.
Los teléfonos hablan entre sí por Bluetooth LE y se reenvían los mensajes unos a
otros, formando una malla (igual que BitChat, pero con la radio encendida solo a
ratos para no comerse la batería).

> Estado: **prototipo funcional (MVP)** para Android. APK release firmado con la
> clave de debug, listo para instalar por sideload (no para Play Store).
> Sin cuentas ni nube: todo vive en el teléfono. El GPS es **opcional** y está
> apagado por defecto.

---

## 1. Qué hace

- Conversaciones 1 a 1 con estados tipo WhatsApp: en cola, enviado, entregado.
- Descubrimiento automático al acercarse, sin escanear en bucle.
- Mensajes cifrados de extremo a extremo (X25519 + AES-256-GCM).
- Multi-salto: si dos personas no se ven, un tercer teléfono en medio reenvía.
- Store-and-forward: lo que no se pudo entregar se reintenta hasta 24 h.
- Funciona en segundo plano mediante un servicio en primer plano de Android.
- **Modo demo** con dos contactos simulados que cifran, confirman y responden:
  sirve para probar la app en el emulador (Bluetooth no existe ahí).
- **Cercanía opcional**: si ambos activan compartir ubicación, el chat muestra
  «≈30 m al NE» y un asistente local explica distancia, rumbo y minutos andando.
- La notificación de «está al alcance» incluye esa distancia y, al tocarla, abre
  el chat de esa persona (donde también se puede agregar a contactos).
- **Botón de ubicación** en el chat para mandar las coordenadas en el momento,
  sin pasar por Ajustes.
- **Canal "Todos"**: un canal abierto para avisar a cualquiera que esté cerca,
  sin agregarlo como contacto. Está fijo arriba en Chats.
- **Estados rápidos**: "Estoy bien", "Necesito ayuda", "Estoy atrapado", con tu
  batería adjunta, en un toque.
- **SOS** con pulsación larga: manda tu posición, se repite y queda en cola
  hasta 24 h por si alguien llega después.
- **Modo repetidor**: deja un teléfono enchufado reenviando lo de los demás.
- **Brújula**: con un chat abierto, una flecha apunta hacia la otra persona.
- **Compartir la app**: manda el APK por Quick Share o Bluetooth, sin internet.

### El canal abierto y el SOS

El chat privado sigue siendo 1 a 1 y cifrado con la clave del destinatario. El
canal "Todos" es otra cosa: va a difusión, lo lee cualquiera que esté en la
malla y se reenvía hasta **5 saltos** (más que un mensaje privado, porque en una
emergencia importa que el aviso cruce toda la cadena).

- Se cifra con una clave de grupo derivada de una constante de la app. No es un
  secreto: sirve para que el texto no viaje legible por el aire, no para ocultarlo
  de quien tiene la app (ese es el propósito del canal).
- El nombre y la batería que ves los **declara el emisor**: no hay firma detrás.
  Si el nodo ya se anunció, su id sí está atado a su clave pública.
- Un aviso normal sin nadie cerca **no se guarda** (un boletín viejo engaña).
  Un estado o un SOS **sí**: se reintenta con backoff hasta 24 h.
- El SOS incluye la última posición conocida y dispara una notificación de
  importancia máxima con vibración; tocarla abre el canal.

### Ubicación: qué se puede y qué no

| Pregunta | Realidad |
|---|---|
| ¿La distancia sale del Bluetooth? | Solo un rango grueso (por intensidad de señal). Con coordenadas del otro teléfono es una distancia real. |
| ¿Y la dirección (N, NE, S…)? | **Necesita coordenadas de ambos.** Con una sola antena BLE es físicamente imposible saber de qué lado está la persona. |
| ¿Hay que dar permiso de ubicación? | Solo si activas **Compartir mi ubicación**. Sin ese interruptor la app no toca el GPS. |
| ¿Se envía a algún servidor? | No hay servidor. Las coordenadas van cifradas y solo a tus contactos. |
| ¿Funciona sin internet? | Sí: usa el GPS del teléfono. Con el cielo tapado tarda más o da ±cientos de metros, y la app lo muestra. |

## 2. La verdad sobre el alcance

Esto es importante antes de instalar:

| Pregunta | Respuesta honesta |
|---|---|
| ¿Alcance por salto? | **10–30 m** en interior con paredes; **hasta 100 m** a la vista y sin obstáculos. |
| ¿Se puede ampliar por software? | Solo con dos palancas: **más saltos** (cadena de teléfonos) y **mensajero** (alguien se lleva la trama y la suelta más lejos). La distancia de un salto la fija la radio: ningún código la estira. |
| ¿"Largas distancias"? | Solo **en cadena**: A → B → C. Cada teléfono intermedio suma ~30–80 m reales, hasta **5 saltos** (7 en el canal abierto) por tramo. |
| ¿Y si no hay nadie en medio? | **Mensajero**: un teléfono con la app recoge el mensaje aunque ya no le queden saltos, camina, y lo suelta al encontrar gente. Ahí el tramo vuelve a empezar. |
| ¿Kilómetros sin repetidores? | **No.** Eso requiere LoRa (1–10 km por salto) o un PHY de largo alcance, que este APK no trae. |
| ¿Sin nadie cerca? | No hay red en ese instante. El mensaje espera en la cola **24 h** y sale al aparecer alguien. |
| ¿Funciona sin abrir la app? | Sí, con el servicio en primer plano activo (notificación permanente). |

BitChat tiene exactamente la misma limitación física: BLE no llega más lejos.
La diferencia aquí es el presupuesto de radio, que hace que aguante todo el día.

### Cómo estirar el alcance de verdad

1. **Saca el teléfono del bolsillo.** El cuerpo se come 10–20 dB: llevarlo en la
   mano o colgado del pecho puede duplicar la distancia útil. En el bolsillo del
   pantalón, con el cuerpo entre los dos equipos, el enlace cae a la mitad.
2. **Altura y línea de vista.** Un segundo piso, una ventana o una loma valen
   más que cualquier ajuste: 2,4 GHz atraviesa mal paredes, chapa y tierra.
3. **Cadena**: cada teléfono con la app abierta (o con el servicio activo) suma
   un salto. Los privados aguantan 5; el canal "Todos" y el SOS, 7.
4. **Modo repetidor** (Ajustes): un teléfono viejo enchufado en la ventana
   escucha casi todo el tiempo en vez de abrir ventanas cortas. Es el nodo que
   más alcance aporta por vatio.
5. **Mensajero**: quien va de un pueblo a otro lleva encima lo que recogió y lo
   suelta al llegar, aunque el mensaje ya hubiera gastado sus saltos. Lo
   acarreado se guarda en disco: un apagón no lo borra (caduca a las 24 h).
6. **No hay ajuste de potencia**: Android no permite subir la potencia de
   emisión de BLE sin root, y el PHY de largo alcance (LE Coded) no lo expone la
   librería que usa la app. Para kilómetros hace falta hardware LoRa.

## 3. Cómo funciona

```
UI (Flutter)  →  MeshNode  →  MeshRouter  →  MeshTransport  →  BLE
                    │                            └── DemoMeshTransport
                    ├── Outbox (reintentos, 24 h)
                    ├── DedupCache (no repetir lo ya visto)
                    ├── RadioScheduler (cuándo escuchar)
                    └── StateStore (JSON en documentos)
```

### Trama (`lib/src/core/frame.dart`)

Cabecera binaria de 47 bytes: magic, versión, tipo (mensaje/ack/presencia/
ubicación), id de 16 bytes, origen (8), destino (8), timestamp, TTL y saltos. El
payload va cifrado. TTL inicial 5 (7 en el canal abierto); cada reenvío resta 1
y suma un salto. Al llegar a 1 la trama no se tira: se guarda para el mensajero.

Las tramas de **ubicación** llevan 18 bytes cifrados: latitud y longitud a 1e7,
precisión en metros y hora. Se mandan a un contacto concreto, igual que un
mensaje; quien repite no puede leerlas. No se encolan: una ubicación de hace
horas no sirve, así que si no hay enlace se marca como fallida.

El `aad` del cifrado autentica la cabecera completa: si alguien cambia el
destino o el TTL, el mensaje no descifra.

### Enrutado (`lib/src/mesh/router.dart`)

Inundación epidémica controlada:

1. Se ignora lo propio y lo ya visto (`DedupCache`, 8.192 entradas / 48 h).
2. Si el destino soy yo: descifro, entrego y devuelvo un **ACK**.
3. Si no: reenvío una sola vez (TTL−1) y guardo copia para el próximo enlace.
4. Si ya no quedan saltos: **no se tira**, se guarda para el mensajero y se
   reemite con 2 saltos frescos al aparecer un nodo (hasta 24 h después).

El ACK viaja con TTL 5 y es la única prueba de entrega; al recibirlo el mensaje
sale de la cola y pasa a "entregado".

### Cola de salida (`lib/src/mesh/outbox.dart`)

- Un mensaje propio vive **24 h**; al restaurar el estado se descarta lo caducado.
- Reintentos a 30 s, 60 s, 120 s y 240 s (tope ×8), contados por mensaje, así
  que un envío fallido no bloquea los demás.
- Se persiste con su fecha de encolado, de modo que cerrar la app no reinicia el
  plazo ni los reintentos.
- El estado se guarda en un archivo temporal y se renombra encima del anterior:
  un corte de luz a mitad de escritura no deja el historial corrupto.

### Identidad y cifrado (`lib/src/core/`)

- Par X25519 estático por instalación, guardado en el teléfono.
- `nodeId` = primeros 8 bytes de SHA-256 de la clave pública (16 hex).
- Clave compartida por ECDH + HKDF-SHA256 (info `sinred/v1/mesh-message`).
- AES-256-GCM con sobre de 28 bytes (12 nonce + 16 tag).
- TOFU: si un id aparece con otra clave pública, el anuncio se descarta.

**Sin forward secrecy**: la clave estática permite descifrar mensajes viejos si
se compromete el teléfono. Para un MVP sin servidores es el intercambio aceptable;
el siguiente paso sería ratchet (Double Ratchet) por conversación.

### Presencia

Al abrir un enlace cada nodo manda un anuncio (~50–90 bytes) con su clave y su
nombre, directamente por ese enlace. No hay escaneo continuo ni ping permanente.

El anuncio se repite cada **5 minutos** mientras la radio está encendida. No es
un ping de presencia (nadie espera respuesta): sirve para que quien llega último
a una cadena conozca a los que ya estaban. En A—B—C, C solo oiría a B si nadie
re-anunciara; el reenvío del anuncio de A (TTL 2) es lo que se lo presenta.

El nombre viaja en UTF-8 y se recorta a 48 bytes sin partir un carácter, así que
"Ñandú 📡" o cualquier emoji llegan intactos.

### Contactos por QR y avisos de alcance (`lib/src/core/contact_code.dart`)

Cada teléfono muestra su código y puede leer el de otro:

- El QR lleva `SINRED1:<id>:<clave pública>:<nombre>`.
- Al leerlo se comprueba que la clave pública derive el id (SHA-256); un QR
  manipulado para suplantar a alguien se rechaza y no se agrega.
- El contacto se guarda en `sinred_state.json` en el mismo instante en que se
  agrega: cerrar la app o reiniciar el teléfono no lo borra.
- La cámara solo se enciende en la pestaña **Escanear**; si no hay cámara o no
  se quiere dar el permiso, el mismo código se puede pegar como texto.

Cuando un contacto de la libreta entra en alcance (enlace directo o anuncio
reciente por la malla), la app avisa: "Ana está al alcance". Dos frenos: como
mucho un aviso por contacto cada **10 minutos**, y ninguno si ese chat está
abierto en pantalla. El aviso usa el permiso de notificaciones que la app pide
al arrancar; sin él, todo lo demás sigue funcionando igual.

#### Código corto (`ABC-DEF`)

Alternativa al QR para dictar por voz o escribir a mano: 6 símbolos derivados del
id, sin los caracteres que se confunden al dictar (0/O y 1/I). Se copia desde **Mi código** y se
usa en **Contactos → Por código**.

Sin servidor, un código de 6 caracteres no puede llevar la clave pública (32
bytes), así que no resuelve a alguien que no esté presente: busca entre los nodos
que ya se anunciaron en la malla y toma la clave que ese nodo ya publicó, que el
router verificó contra su id. Antes de agregar pide confirmación mostrando el
nombre, y si dos nodos comparten código lo rechaza en vez de adivinar. Para
alguien que no está al alcance, el camino es el QR o pegar el código completo.

## 4. Batería: el diseño

El gasto de una malla BLE viene de **escanear**, no de anunciarse. Por eso:

- **Advertising siempre encendido** (baratísimo, permite que te encuentren).
- **Escaneo por ventanas** según `PowerPolicy`:

| Modo | Ventana | Cada | Ciclo activo |
|---|---|---|---|
| Ahorro | 3 s | 120 s | 2,5 % |
| Equilibrado | 4 s | 45 s | 8,9 % |
| Rápido | 5 s | 20 s | 25 % |

- Sin encontrar nodos, el intervalo se duplica hasta 5 minutos (backoff). Lo
  detecta el propio planificador al cerrar una ventana sin ningún anuncio, así
  que funciona sin que nadie tenga que avisar de los barridos vacíos.
- Con batería ≤ 15 % la ventana baja a 2 s y el descanso se alarga.
- Si ya hay un enlace abierto, se escanea la mitad: no hace falta buscar más.
- Cargando, se vuelve agresivo (6 s cada 15 s) para sincronizar rápido.
- Sin GPS, sin wakelocks, sin sondeos de red. El servicio en primer plano solo
  mantiene el proceso vivo; no despierta la CPU a intervalos.

Orden de magnitud esperado: **2–5 % de batería por hora** en modo equilibrado,
frente a 10–20 % de un escaneo BLE continuo. Son estimaciones de diseño, no
mediciones: falta un test de consumo real de 8 h en dispositivo.

## 5. Instalar

Requisitos: Android 7.0+ (API 24) con Bluetooth LE.

```bash
flutter pub get
flutter test
flutter build apk --release
```

APK listo para instalar: **`dist/SinRed-0.5.2.apk`** (65 MB, todas las)
arquitecturas; el escáner de QR con ML Kit es lo que lo engorda). También queda
en `build/app/outputs/flutter-apk/app-release.apk`.

Descarga directa sin compilar nada:
[**SinRed-0.5.2.apk**](https://github.com/Chapi-creator/sinred/releases/download/v0.5.2/SinRed-0.5.2.apk)
(la carpeta `dist/` no va en git: el APK se publica como adjunto del release).
SHA-256: `ab74a10ad2e07290d56079245cc01f770e84f8c9c39a6156f4c50a6e2c5d1fac`.
Cópialo al teléfono e instálalo (permite "instalar apps desconocidas").
Está firmado con la clave de debug de Flutter: sirve para probar, no para
publicar en Play Store.

Al abrir la app pide permisos de Bluetooth y de notificaciones; los de Bluetooth
son obligatorios para que la malla funcione en segundo plano. El de cámara solo
se pide la primera vez que abres la pestaña **Escanear**, y el de ubicación solo
cuando activas **Compartir mi ubicación** en Ajustes o pulsas el botón de
coordenadas de un chat. La radio no arranca hasta que
contesta el diálogo: en Android 14 un servicio en primer plano de tipo
`connectedDevice` sin permiso de Bluetooth lanza `SecurityException` y el
sistema cierra la app. En ajustes hay un acceso directo para excluirla de la
optimización de batería.

### Probar sin dos teléfonos

Ajustes → **Modo demo**. Aparecen Ana y Bruno (repetidor a 2 saltos) que cifran,
confirman y responden con el protocolo real. Es la forma de ver el flujo completo
en un emulador, donde no hay radio BLE.

### Probar con dos teléfonos

1. Instala el APK en ambos y abre la app.
2. Ponles un nombre distinto en Ajustes (por defecto "Yo").
3. En **Contactos → Agregar**, escanea el QR del otro teléfono (o dicta su
   código corto con **Por código**). Queda guardado en la libreta al instante.
4. Acércalos: en unos segundos aparece la notificación de que el contacto está
   al alcance, y también en la lista de nodos.
5. Abre el chat y escribe. La marca cambia a "entregado" cuando llega el ACK.
6. Sin agregar contactos, abre **Todos** y manda un aviso: el otro teléfono lo
   recibe con el nombre de quien escribió. Prueba el SOS manteniendo pulsado el
   botón rojo.

### Repartir la app sin internet

Ajustes → **Compartir la app** abre la hoja de Android con el APK adjunto. Con
Quick Share o Bluetooth pasa a otro teléfono sin datos ni Play Store: es la
forma de que la app llegue a un barrio cuando la red ya no está.

## 6. Estructura del proyecto

```
lib/
  main.dart                     arranque
  src/
    app.dart                    MaterialApp y servicio en primer plano
    core/                       bytes, identidad, trama, cifrado, modelos, QR
    mesh/                       router, outbox, dedup, MeshNode (estado)
    power/                      PowerPolicy y RadioScheduler
    transport/                  interfaz + BLE real + demo + fragmentación
    data/state_store.dart       persistencia JSON
    platform/                   MethodChannel del servicio nativo
    ui/                         chats, contactos, escáner QR, ajustes, widgets
android/app/src/main/kotlin/com/sinred/sinred/
  MainActivity.kt               canal sinred/power
  MeshForegroundService.kt      servicio en primer plano
test/                           protocolo, malla, energía y humo de UI
```

## 7. Límites conocidos

- Solo 1 conversación activa por enlace; el transporte abre hasta **2 enlaces**
  simultáneos para no saturar la radio.
- Fragmentación de 180 bytes por escritura GATT; un mensaje de 500 caracteres
  ocupa varios paquetes y puede tardar segundos. El tope es **1.800 bytes UTF-8**
  por mensaje (no caracteres): el número de trozos se codifica en un solo byte,
  así que un texto mayor no se podría reensamblar en el otro teléfono. La app
  avisa en vez de recortar el mensaje a escondidas.
- El **mensajero** guarda hasta 24 h (máx. 64) tramas ajenas que ya no tenían
  saltos. Quien las lleva no puede leerlas, pero sí ve que existen, entre qué
  dos nodos y de qué tamaño. Una trama acarreada puede además entregarse dos
  veces si su caché de duplicados se vació en ese teléfono; la app deduplica por
  id, no por texto.
- El ACK no va firmado: un nodo malicioso podría confirmar en falso.
- Sin reputación ni lista de bloqueo; cualquiera con la app puede inundar la malla
  (el TTL y la caché lo amortiguan).
- Sin forward secrecy (ver arriba).
- iOS no está soportado: requiere macOS para compilar y el plugin elegido no
  expone periférico en iOS.
- La demo no simula pérdidas ni movilidad: es para ver el flujo, no para medir.
- El aviso de "está al alcance" necesita la malla activa (app abierta o servicio
  en primer plano). Si el sistema detiene el proceso, no hay Bluetooth ni aviso.
- Escanear el QR exige permiso de cámara y ML Kit suma varios MB al APK.
- La dirección (N, NE, S…) es el **rumbo geográfico** hacia la otra persona, no
  hacia dónde apunta tu teléfono. Sin coordenadas del otro solo hay un rango
  por RSSI, que las paredes alteran mucho.
- El GPS necesita cielo abierto: bajo techo la precisión puede ser de cientos de
  metros y la app lo indica con el ±. La última posición se muestra como dato
  fresco solo mientras es reciente.
- Compartir ubicación mantiene el GPS escuchando cada 15 s mientras la app está
  viva; gasta más batería que la malla sola. Se apaga con su interruptor.
- Un contacto agregado por QR queda verificado por su clave, pero nada impide
  que alguien comparta un QR ajeno si lo tiene en la mano: es equivalente a
  enseñar el teléfono.
- El canal "Todos" no tiene firma: cualquiera con la app puede escribir y decir
  que es otro. El nombre y la batería son declarados. No lo uses para órdenes
  oficiales ni para decidir a quién rescatar.
- El SOS no garantiza que alguien lo escuche: si no hay nadie en el radio de la
  malla, el mensaje espera en cola y solo sale cuando aparece un teléfono. No
  sustituye a los servicios de emergencia.
- El modo repetidor escucha el 80 % del tiempo: pensado para un teléfono
  enchufado. Sin cargador se come la batería en horas, no en días.
- La brújula depende del magnetómetro y de que el teléfono esté más o menos
  plano y lejos de metales; si no hay sensor, la app muestra la sigla y sigue.
- El APK declara el permiso `INTERNET`: lo arrastra la librería del escáner de
  QR (ML Kit) en su manifiesto. El código de SinRed no abre ningún socket ni
  llama a ninguna API; se puede comprobar buscando `HttpClient` o `Socket` en
  `lib/`, que no aparecen.
- Compartir el APK depende de que el otro teléfono acepte instalar apps de
  origen desconocido; Quick Share puede pedir confirmación en ambos lados.

## 8. Siguientes pasos razonables

1. Medir consumo real 8 h con la app en segundo plano y ajustar la tabla.
2. Ratchet por conversación y ACK firmado.
3. Puente LoRa (Heltec / T-Beam) como transporte adicional: ahí sí hay km.
4. Envío de fotos y notas de voz por trozos (hoy el canal es solo texto).
5. Descubrimiento por `service data` en el advertising para ahorrar el escaneo.
6. Transferencia directa del APK por Wi-Fi Direct (hoy usa la hoja del sistema).
7. Firma de los avisos del canal con una clave de coordinador de confianza.

## 9. Qué cambió en la 0.5.2

Más alcance real, sin hardware nuevo:

- **Mensajero (store-and-forward)**: cuando a una trama se le acaban los saltos
  ya no se tira. Se guarda en el teléfono y se vuelve a soltar, con saltos
  nuevos, en cuanto aparece otro teléfono con la app. Así un mensaje cruza un
  pueblo entero en dos caminatas, sin repetidores fijos ni internet. Se guarda
  en disco (sobrevive a apagones) y caduca a las 24 h.
- **Más saltos por tramo**: los mensajes privados pasan de 3 a **5 saltos**, el
  canal abierto y el SOS de 5 a **7**, y el ACK viaja tan lejos como el mensaje
  que confirma (antes se quedaba en 4 y el emisor marcaba "enviado" sin
  confirmación real en cadenas largas).
- **Caché de duplicados de 12 a 48 h y 8.192 entradas**: con el mensajero, una
  trama puede reaparecer horas después; sin recordarla se entregaría repetida.
- **Pruebas nuevas** (`test/courier_test.dart`): acarreo sin saltos, reemisión
  con TTL fresco, que soltar dos veces no duplique el mensaje, supervivencia al
  reinicio y caducidad a las 24 h.

Lo que **no** cambia: la distancia de un salto sigue siendo la de la radio
(10–30 m en interior, hasta 100 m a la vista). Para kilómetros hace falta LoRa.

## 10. Qué cambió en la 0.5.1

Repaso de errores reales de la 0.5.0, con su prueba de regresión cuando se
podía reproducir sin teléfono:

- El estado se guarda en **una sola escritura a la vez**: el temporizador de 2 s
  y el cierre de la app podían escribir el mismo archivo temporal a la vez y
  dejar el JSON truncado (es decir, perder identidad, contactos e historial).
- Si caía un enlace del rol periférico, el **escaneo no se reanudaba** cuando se
  había detenido por el máximo de enlaces: la malla dejaba de ver teléfonos
  nuevos hasta reiniciar la app.
- El repetidor **ya no reenvía tramas del canal que no puede descifrar**: con
  TTL 5, cualquier ruido o trama manipulada se multiplicaba por toda la malla.
- Los estados y el SOS tienen **su propia cola de salida** (20 avisos, 24 h):
  antes compartían la cola de 200 con los mensajes privados y una tarde de
  "Estoy bien" podía expulsar mensajes reales sin entregar. Siguen
  sobreviviendo al reinicio.
- El **SOS pide una posición al GPS en el momento** si aún no había ninguna,
  aunque compartir ubicación esté apagado (sin abrir diálogos de permiso a
  mitad de la emergencia: si no está concedido, sale sin coordenadas).
- **Topes de memoria y disco**: 3.000 mensajes de historial y 500 nodos
  conocidos (nunca se descarta un contacto de la libreta). Antes el archivo de
  estado crecía sin límite y se reescribía entero cada 2 s.
- Los permisos de Bluetooth/notificaciones ahora responden **lo que el usuario
  eligió**; el código nativo contestaba "concedido" aunque hubiera denegado.
- La **brújula se comparte** entre chats apilados: cerrar el chat abierto desde
  una notificación ya no congela la flecha del chat de abajo. Y no se acumula
  un callback por rebuild.
- Los contactos alcanzables **solo por 2 saltos** ya no muestran barras de
  señal falsas en la lista.
- Los avatares cortan por **grafemas**: un nombre que empieza con emoji ya no
  deja medio carácter. El diálogo de cambiar nombre libera su controlador.

## 11. Licencia

Código del proyecto: MIT. Dependencias: `bluetooth_low_energy` (MIT),
`cryptography` (Apache-2.0), `mobile_scanner` y `qr_flutter` (BSD-3),
`battery_plus`, `provider`, `path_provider` (BSD-3 de Flutter/Dart). Los permisos
se piden con código nativo del proyecto.
