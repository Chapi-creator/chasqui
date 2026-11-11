# Puente LoRa — diseño

> **Estado: diseño, no implementación.** Chasqui no tiene una línea de LoRa. Hoy
> solo hay Bluetooth LE. Este documento deja escrito cómo se agregaría, qué
> límites tiene y qué errores hay que evitar, para que el día que haya una placa
> se escriba una vez y bien.

## 1. Por qué LoRa

La malla de Chasqui vive de la radio del teléfono: 10–30 m dentro de una casa y
hasta 100 m a la vista. Para llegar más lejos solo hay dos palancas por software
—más saltos o un mensajero que camine— y ninguna estira el alcance de un salto.

LoRa es otra radio, no otro código: un módulo de ~USD 15–50 transmite a
**1–10 km por salto** con muy poca energía, a cambio de una velocidad ridícula
(cientos de bits por segundo). La idea es que un teléfono con Chasqui le hable a
una placa por Bluetooth y la placa haga el tramo largo.

No reemplaza al Bluetooth: lo extiende. Sin nadie con placa cerca, la malla de
teléfonos sigue funcionando igual que hoy.

## 2. La decisión: nodo Meshtastic por BLE

Hay dos caminos y conviene saber por qué se elige el primero.

| Camino | Qué implica | Veredicto |
| --- | --- | --- |
| **Hablar con un nodo Meshtastic** | La placa ya trae firmware, malla propia y una API de cliente por BLE documentada. Chasqui se conecta como lo hace la app oficial de Meshtastic. | **Elegido**: es el que menos código nuevo pide y el único compatible con radios que la gente ya tiene. |
| Firmware propio | Control total del formato y del cifrado, pero hay que escribir y flashear el firmware, y ninguna otra app entiende los paquetes. | Descartado para empezar. |

Del lado de Meshtastic, lo que hay que respetar (verificado en su documentación
el 11/11/2026):

- Un servicio GATT con tres características: **ToRadio** (se escribe), **FromRadio**
  (se lee) y **FromNum** (avisa cuando hay algo nuevo).
- **Un protobuf por lectura y por escritura.** No hay framing por stream: los
  límites del mensaje los pone GATT.
- **MTU 512 recomendado**, pero no hay que asumirlo: se pregunta cuánto acepta la
  escritura y se trocea según eso.
- **Máximo 233 bytes de payload útil** por paquete (`DATA_PAYLOAD_LEN`), y 7
  saltos como tope del firmware.
- **Los reintentos los hace el firmware**, no el teléfono: una difusión confiable
  se transmite como máximo tres veces.

**Trampa de versiones**: los UUID de servicio y de características **no coinciden
entre la documentación vieja y la nueva** (la del SDK lista
`6BA1B218-15A8-461F-9FA8-5DCAE273EAFD`, las notas de Android listan otro servicio
y otra característica `toradio`). Antes de fijar constantes hay que descubrir el
servicio en el nodo conectado y comprobar la versión de firmware. Escribir UUIDs
de un blog es la forma más rápida de que "no conecte nunca".

## 3. Cómo entra en el código de hoy

`lib/src/transport/transport.dart` ya define el contrato de radio
(`MeshTransport`) con la idea explícita de admitir LoRa sin tocar la malla. Un
`LoRaTransport` tendría que implementar:

| Miembro | Qué significa con una placa LoRa |
| --- | --- |
| `inbound` | Cada paquete que el nodo entrega por `FromRadio` y que sea de Chasqui. |
| `linkEvents` | Conectado / desconectado del nodo por BLE (no "vecino cerca"). |
| `connectedLinks` | 1 mientras haya un nodo emparejado; 0 si no. |
| `send(frame, onlyLink, exceptLink)` | Un `ToRadio` con la trama; `onlyLink` no aplica: la placa difunde. |
| `setDiscoveryEnabled` | Encender o apagar el escaneo del nodo. No cambia el consumo de la placa. |
| `setIdleLinkTimeout` | Soltar el enlace BLE tras un rato sin tráfico (la placa sigue en la malla). |

La malla no cambia: sigue armando tramas, deduplicando por id y contando saltos.
Lo que cambia es el tubo.

## 4. Tamaños: lo que de verdad entra

La cabecera de Chasqui son **47 bytes**. En un paquete LoRa entran 233, así que
quedan **186 bytes útiles** por paquete. Nada de reusar el troceo de 180 bytes del
GATT: el criterio es otro.

## 5. Tiempo de aire (y por qué manda)

Tiempo de un paquete de 233 bytes, calculado con la fórmula de Semtech (preámbulo
16, CRC activo, CR 4/5):

| Configuración | Un paquete de 233 B | Un paquete de 186 B |
| --- | --- | --- |
| SF7 / 125 kHz | 0,38 s | 0,32 s |
| SF9 / 125 kHz | 1,18 s | 0,98 s |
| **SF11 / 250 kHz** ("LongFast", el ajuste típico de Meshtastic) | **1,99 s** | **1,62 s** |
| SF12 / 125 kHz | 8,63 s | 7,06 s |

De ahí salen las cuentas que definen el diseño:

| Qué se manda | Paquetes | Aire a LongFast |
| --- | --- | --- |
| Latido de presencia (60 B) | 1 | 0,68 s |
| Mensaje corto ("estamos bien", 100 B) | 1 | ~1,1 s |
| Mensaje al tope de la app (1.800 B) | 10 | **~20 s** |
| Trozo de foto (3 KB) | 17 | **~34 s** |
| Foto de 40 KB | 221 | **~7 min 20 s** |

Dos consecuencias que no son opinables:

1. **La presencia cada 30 s mata la red.** Diez nodos latiendo cada 30 s ocupan
   el **23 %** del tiempo de aire sin que nadie hable. Por LoRa la presencia tiene
   que espaciarse a minutos, o mandarse solo cuando hay algo que decir.
2. **Las fotos no van por LoRa.** Siete minutos de canal ocupado para una foto no
   es un bug de implementación: es la física del ancho de banda. Si algún día se
   admite, tiene que ser con un botón explícito y avisando cuánto tarda.

## 6. Errores conocidos que hay que evitar desde el diseño

1. **Escrituras grandes cuando la radio está sin buffers.** Está documentado que
   con la placa ocupada fallan escrituras de 512 B mientras pasan las de 8–33 B
   (lo vieron en una Heltec V4). Hay que escribir en trozos chicos y mirar el
   largo máximo real de cada escritura, no el MTU negociado.
2. **Asumir el MTU.** Se pregunta siempre; el sistema puede negociar menos.
3. **ACK explícito para todo.** El ACK de Chasqui es otro paquete: 0,7–2 s de aire
   por cada mensaje. En difusión conviene el ACK implícito (alguien repite la
   trama); el ACK real se reserva para mensajes directos.
4. **No deduplicar.** La malla ya descarta tramas repetidas por id; sin eso, el
   flooding de LoRa multiplica cada mensaje por cada nodo que lo repite.
5. **Saltos de más.** Con 7 saltos, un nodo de las afueras inunda la ciudad y
   agota el presupuesto de todos. En LoRa: 3–4.
6. **Confiar en el orden de llegada.** Los paquetes llegan desordenados y
   repetidos; el armado de mensajes ya tolera eso, pero cualquier código nuevo
   tiene que asumirlo.
7. **Ignorar el ciclo de trabajo.** En Europa la banda de 868 MHz tiene **1 %** de
   ciclo de trabajo: 20 s transmitiendo obligan a esperar ~33 min. En América
   (902–928 MHz) no hay ese límite, pero la radio igual devuelve errores de "canal
   ocupado" que parecen fallos de la app.
8. **Transmitir sin antena.** Regla de hardware: con el módulo sin antena se
   quema la etapa de potencia. Va en la caja y en el LEEME de la placa, no en el
   código, pero se pierde una placa por olvidarlo.

## 7. Presupuesto de radio

Antes de escribir código conviene fijar el número: **cuánto aire por minuto se
permite la app**. Propuesta: presupuesto propio de 10 s de aire por minuto y por
nodo, con cuenta regresiva visible cuando se agota. Eso deja espacio para que
otros nodos (y otras apps) usen el canal, y hace que la app se comporte igual en
Europa que en América.

## 8. Qué se puede probar sin placa

Sí, y conviene hacerlo antes de comprar nada:

- **Codificar y decodificar los protobufs** de Meshtastic (envoltorios `ToRadio`
  y `FromRadio`, paquete de datos) contra tramas de referencia de la
  documentación. En Dart puro, con tests.
- **El troceo a 186 bytes** y el rearmado con paquetes desordenados, repetidos y
  perdidos.
- **El presupuesto de aire**: dado un tamaño y un ajuste (SF/BW), cuánto tarda y
  si cabe en el minuto.

Lo que no se puede probar sin hardware: emparejamiento BLE, alcance real, qué
hace el firmware cuando se queda sin buffers, y la convivencia de varias placas
en el mismo canal.

## 9. Plan por etapas, con criterio de aceptación

1. **Protobufs y troceo** (sin hardware). Aceptado cuando las tramas de
   referencia se decodifican igual que las publicadas y 1.800 bytes se rearman
   completos con 20 % de paquetes perdidos y desordenados.
2. **Presupuesto de aire**. Aceptado cuando la app rechaza o encola lo que no
   cabe en el minuto, con prueba que lo demuestre.
3. **`LoRaTransport` contra un nodo real**. Aceptado cuando un mensaje de 100 B
   viaja de un teléfono a otro con una placa en el medio y el ACK vuelve.
4. **Modo solo texto**. Aceptado cuando las fotos quedan bloqueadas con un aviso
   claro en vez de colgarse enviando durante siete minutos.

## 10. Referencias

- API de cliente de Meshtastic (serial, TCP y BLE):
  <https://meshtastic.org/docs/development/device/client-api/>
- Protocolo y límites del SDK (233 B, MTU, un protobuf por operación GATT):
  <https://github.com/meshtastic/meshtastic-sdk/blob/main/docs/protocol.md>
- Algoritmo de malla, saltos, ACK implícito y reintentos:
  <https://meshtastic.org/docs/overview/mesh-algo/>
- Notas del transporte Android (UUIDs, escrituras cuando faltan buffers):
  <https://github.com/meshtastic/meshtastic-sdk/blob/main/docs/references/meshtastic-android-protocol-notes.md>
- Ciclo de trabajo y banda de 868 MHz:
  <https://www.thethingsnetwork.org/docs/lorawan/duty-cycle>
- Cómo se comporta una red Meshtastic real (saltos, ausencia de entrega):
  <https://loomwave.org/case-study-meshtastic.pdf>
- Fragmentación en enlaces de MTU chico:
  <https://www.mdpi.com/1424-8220/22/4/1531>
