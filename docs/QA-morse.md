# QA del receptor de morse

Qué se midió, qué falló, qué se arregló y qué queda fuera. Todo lo de acá es
simulación reproducible (`test/morse_qa_test.dart`): no hay teléfono en la
cadena, así que sirve para saber qué garantiza el código, no cómo se porta una
cámara concreta.

## 1. Qué se prueba

La cadena completa, con el muestreador y el decodificador reales:

    mensaje → emisor exacto → cámara simulada → LightSampler → MorseDecoder → texto

La cámara simulada tiene fotogramas irregulares (temblor), fotogramas que no
llegan, exposición automática que tarda en seguir al apagado, y ruido de imagen.

| Parámetro | Valores |
| --- | --- |
| Mensajes | 8: `SOS`, `HOLA`, `AGUA`, `CASA`, `AYUDA`, `SOS SOS`, `NO HAY AGUA`, `NECESITO MEDICO EN EL REFUGIO` |
| Ritmo (ms por punto) | 300 (lento), 200 (normal), 120 (rápido) |
| Cadencia de cámara | 30, 24, 20, 15, 12, 10 imágenes por segundo |
| Temblor entre fotogramas | ±20 %, ±35 % |
| Fotogramas perdidos | 3 %, 8 % |
| Exposición (constante de tiempo) | 0 ms (ideal), 30 ms, 60 ms |
| Ruido de brillo | ±1 %, ±5 % |

Total: 3 × 6 × 2 × 2 × 3 × 2 × 8 = **3.456 lecturas** por corrida. Una lectura
cuenta como acierto solo si el mensaje entero sale igual; una letra cambiada es
un fallo.

## 2. Criterio de aprobado

| Banda | Se exige | Medido |
| --- | --- | --- |
| 300 ms, cualquier cámara (30 a 10 por segundo) | 100 % | 100 % |
| 200 ms, desde 20 por segundo | 100 % | 100 % |
| 200 ms, 15 por segundo | ≥ 95 % | 98,4 % |
| 200 ms, 12 y 10 por segundo | ≥ 85 % | 87,0 % / 89,6 % |
| 120 ms, 30 por segundo | ≥ 85 % | 91,1 % |
| 120 ms, 24 por segundo | ≥ 70 % | 78,6 % |
| 120 ms, 20 por segundo | ≥ 55 % | 64,1 % |
| 120 ms, 12 por segundo | ≥ 25 % | 34,9 % |

El piso de cada banda está un poco por debajo de lo medido a propósito: si
alguien toca el muestreador o el decodificador y algo empeora, la prueba falla
antes de publicar.

## 3. Antes y después del arreglo de la 1.1.2

Porcentaje de mensajes completos leídos bien (192 combinaciones por celda):

| Ritmo | 30 fps | 24 fps | 20 fps | 15 fps | 12 fps | 10 fps |
| --- | --- | --- | --- | --- | --- | --- |
| 300 ms antes | 83,3 | 83,3 | 83,3 | 83,3 | 93,8 | 87,5 |
| 300 ms después | **100** | **100** | **100** | **100** | **100** | **100** |
| 200 ms antes | 83,3 | 93,8 | 93,8 | 92,2 | 81,3 | 78,1 |
| 200 ms después | **100** | **100** | **100** | **98,4** | **87,0** | **89,6** |
| 120 ms antes | 84,9 | 72,4 | 58,3 | 53,1 | 32,8 | 3,1 |
| 120 ms después | **91,1** | **78,6** | **64,1** | **56,8** | **34,9** | 3,1 |

Global: **74,5 % → 83,5 %** de 3.456 lecturas.

## 4. El fallo que encontró el QA

No estaba en el decodificador sino en el muestreador de luz.

Con la linterna encendida y quieta, dentro de la ventana de 6 s no hay más que
ruido de la cámara: unos 0,05 de rango. El muestreador recalculaba los umbrales
adaptativos con ese ruido, así que quedaban a 0,024 de distancia entre sí
(60 % y 40 % de 0,05). El temblor de un fotograma cruzaba los dos y el receptor
veía una pausa falsa dentro de la primera marca:

```
esperado   +300 -300 +300 -300 +300 ...   (SOS a 300 ms)
recibido   +55 -72 +173 -303 +304 ...     → H O S
```

Eso no dependía del ritmo ni de la cadencia: pasaba a 300 ms y a 30 imágenes por
segundo, y explica mensajes leídos mal "sin motivo". Con la primera letra
arruinada, el resto del mensaje quedaba inútil.

**Arreglo** (`LightSampler`, 1.1.2):

- Los umbrales automáticos solo se recalculan si el rango medido es claramente
  mayor que el ruido (2,5 × `minRange`). Si no, valen los últimos buenos.
- La zona muerta entre los dos umbrales nunca baja de 0,06 de brillo, así un
  solo fotograma de temblor no puede cruzar los dos.

Prueba de regresión: `test/morse_receiver_test.dart`, "con la luz quieta y ruido
de cámara no inventa marcas".

## 5. Casos borde cubiertos

| Caso | Resultado |
| --- | --- |
| Cámara sin luz (solo pausas) | no hay lectura, no inventa unidades |
| Chispazos de 12 ms (ruido de sensor) | se descartan |
| Mensaje vacío | texto vacío |
| Números (`SOS 911`) | se leen enteros |
| Mensaje de 30 caracteres | se lee entero |
| Borrar y empezar otro mensaje | el mensaje nuevo se lee limpio, el ritmo se reestima |
| Última letra sin pausa final | queda como símbolos en curso y `closeLetter` la cierra |
| 5.000 tramos seguidos | no se cuelga; el ritmo sigue en 200 ms |
| Temblor aislado antes del mensaje | no arruina el mensaje |
| Ritmo estimado | dentro del 15 % del real en 120, 200 y 300 ms |

## 6. Límite físico, no del código

Con 30 imágenes por segundo una cámara puede seguir como mucho unos 15
símbolos por segundo (dos fotogramas por símbolo). El ritmo rápido de la app son
8,3 símbolos por segundo, así que necesita 20 imágenes por segundo como mínimo y
va cómodo a 30. Medido: a 20 fps acierta el 64 %, a 12 fps el 35 %, a 10 fps el
3 %. No es un problema de traducción: con 120 ms por punto y una cámara de 12
fotogramas, un punto dura 1,4 fotogramas y dos puntos con su pausa se funden en
una raya.

De ahí los avisos de la app: el transmisor avisa al elegir Rápido y el receptor,
cuando estima 140 ms o menos, sugiere pedir 200 ms.

## 7. Qué dice la literatura y qué se aplicó

La búsqueda se hizo para no reinventar el decodificador a ciegas.

- **Estado del arte práctico**: los decodificadores serios (fldigi, ggmorse)
  usan umbral adaptativo con histéresis, duraciones de tramo, estimación de
  velocidad por agrupamiento y decisión al final. Chasqui ya está en esa clase:
  umbral adaptativo con zona muerta, candidatos de ritmo puntuados y
  recentrado por mediana.
  ([skipzone.co.uk](https://skipzone.co.uk/blog/building-a-browser-cw-decoder))
- **Siguiente escalón**: decisiones suaves con HMM/Viterbi sobre las duraciones,
  en vez de umbrales duros. La literatura reporta 3–6 dB de mejora en señales
  con ruido. **No se aplicó**: nuestra falla no es ruido de señal sino
  fotogramas que no existen; con la información que llega, un Viterbi no puede
  recuperar un punto que la cámara nunca vio.
  ([roadmap CW](https://patrick.lidstone.net/wiki/cw-decoder-roadmap),
  [decodificador bayesiano AG1LE](http://ag1le.blogspot.com/2013/01/towards-bayesian-morse-decoder.html))
- **Cámara**: los trabajos de comunicación por cámara coinciden en que la
  cadencia limita el ritmo (~30 fps → menos de 15 símbolos por segundo) y en que
  la **exposición automática desestabiliza** la decodificación; con exposición
  fija el brillo sigue al emisor de forma lineal.
  ([Royal Society 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7061997),
  [MDPI Sensors 2019](https://www.mdpi.com/2079-9292/8/8/913),
  [Sensors 2026](https://pmc.ncbi.nlm.nih.gov/articles/PMC13517238))
- **Lo que no se toca**: las propuestas de exposición fija piden fijar ISO y
  tiempo de obturación. La app no lo hace porque en la oscuridad la cámara
  quedaría negra y el receptor no vería nada; preferimos cámara automática con
  umbrales propios y un aviso claro de velocidad.

## 8. Lo que este QA no cubre

- **Teléfono real**: no hay ningún dispositivo conectado por `adb`. Nada de esto
  se validó con cámara física.
- **Exposición automática real**: se modela como un filtro de primer orden; una
  cámara real además tiene ganancia, reducción de ruido temporal y, en algunos
  modelos, obturador de laminillas o lectura por filas (rolling shutter).
- **Destellos con sol de frente, reflejos o luz infrarroja del mando**: fuera del
  modelo.
- **Calibración en el lugar**: se prueba con umbrales medidos a mano, no con el
  procedimiento de calibración completo en exteriores.
- **Modo por toques**: tiene sus propias pruebas (`test/morse_receiver_test.dart`)
  y no pasa por la cámara.
