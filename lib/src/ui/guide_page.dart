import 'package:flutter/material.dart';

/// Guía de uso: qué hace cada parte de la app, para qué sirve y cómo se usa.
///
/// Es texto fijo a propósito: la app no tiene red, así que la ayuda tiene que
/// estar dentro del APK, completa, y funcionar sin conexión ni cuentas.
class GuidePage extends StatelessWidget {
  const GuidePage({super.key, this.intro = false});

  /// Cuando se abre desde la bienvenida, muestra un encabezado de primer uso.
  final bool intro;

  static const List<GuideSection> sections = <GuideSection>[
    GuideSection(
      icon: Icons.wifi_tethering,
      title: 'Cómo funciona Chasqui',
      items: <String>[
        'No usa internet ni servidores. Los mensajes viajan de teléfono en '
            'teléfono por Bluetooth de bajo consumo: cada uno puede reenviar lo '
            'de los demás, hasta 5 saltos en un chat y 7 en el canal abierto.',
        'Si no hay nadie cerca, el mensaje queda guardado hasta 24 horas y sale '
            'cuando aparece alguien. Eso es el store-and-forward: un mensajero '
            'que lleva la carta en el bolsillo.',
        'Cada teléfono tiene su par de claves. En un chat privado, quien repite '
            'el mensaje no puede leerlo.',
      ],
    ),
    GuideSection(
      icon: Icons.chat_bubble_outline,
      title: 'Chats de persona a persona',
      items: <String>[
        'Toca "Nuevo chat" y elige un nodo al alcance. Aparecen los que se '
            'están anunciando por la malla en ese momento.',
        'Los estados son como en WhatsApp: reloj = en cola, un tick = salió, '
            'dos ticks = llegó. Si no hay enlaces, el mensaje espera.',
        'El botón de ubicación manda tus coordenadas al instante. El de la '
            'linterna pasa tu texto a morse por la pantalla o la linterna.',
        'Con la otra persona compartiendo ubicación, la brújula del chat '
            'apunta hacia ella y muestra la distancia aproximada.',
      ],
    ),
    GuideSection(
      icon: Icons.photo_camera_outlined,
      title: 'Fotos por la malla',
      items: <String>[
        'En un chat toca el ícono de foto: se elige una imagen del teléfono y '
            'se achica antes de salir (para que quepa en la malla).',
        'Una foto tarda entre 10 y 30 segundos de estar cerca, porque el '
            'Bluetooth es lento. Queda en cola y se reintenta como un mensaje.',
        'Se guarda en el teléfono, no en la nube. Tocar la foto la abre en '
            'pantalla completa.',
        'Consejo: sirve para reconocer a una persona desaparecida, no para '
            'mandar paisajes. Cuanto más simple la imagen, más rápido llega.',
      ],
    ),
    GuideSection(
      icon: Icons.campaign_outlined,
      title: 'Canal "Todos"',
      items: <String>[
        'Es un canal abierto: lo lee cualquiera que esté en la malla, sin '
            'agregarlo como contacto. Está fijo arriba en Chats.',
        'Úsalo para avisos generales: "hay agua en la escuela", "corte en la '
            'calle 5". No es privado: no pongas ahí datos que no quieras '
            'compartir con desconocidos.',
      ],
    ),
    GuideSection(
      icon: Icons.tag,
      title: 'Canales con nombre',
      items: <String>[
        'Sirven para organizarse: "Refugio Norte", "Cuadrilla 3", "Edificio B". '
            'Cualquiera puede crear uno y los demás entran escribiendo el mismo '
            'nombre.',
        'Si le pones una clave al crearlo, solo entra quien la sepa y los '
            'mensajes van cifrados con esa clave. Sin clave, el canal es '
            'abierto pero separado del "Todos".',
        'El nombre no distingue mayúsculas ni espacios de más: "Refugio Norte" '
            'y "refugio  norte" son el mismo canal.',
        'Para salir: menú del canal, "Salir del canal". Los mensajes viejos se '
            'borran de tu teléfono.',
      ],
    ),
    GuideSection(
      icon: Icons.dashboard_outlined,
      title: 'Tablero de emergencia',
      items: <String>[
        'Cuatro listas fijas: Necesito, Ofrezco, Desaparecidos y Peligro.',
        'Cada aviso caduca solo: el peligro en 2 horas, necesito y ofrezco en '
            '12, desaparecidos en 48. Así nadie camina hasta un punto de agua '
            'que ya no está.',
        'Muestra la hora y los saltos de cada aviso: si dice "2 saltos", llegó '
            'por dos teléfonos de distancia.',
      ],
    ),
    GuideSection(
      icon: Icons.sos,
      title: 'Estados rápidos, SOS y panel de rescate',
      items: <String>[
        '"Estoy bien", "Necesito ayuda" y "Estoy atrapado" van en un toque al '
            'canal abierto, con tu batería.',
        'El SOS se manda con pulsación larga, incluye tu posición si la hay y '
            'se repite hasta 24 horas por si alguien llega después.',
        'El panel de rescate (ícono SOS arriba) no usa radio: SOS en morse con '
            'pantalla y linterna, sirena, símbolos X / V / flecha y un contador '
            'desde el último avistamiento.',
      ],
    ),
    GuideSection(
      icon: Icons.battery_saver,
      title: 'Radio y batería',
      items: <String>[
        'Cuatro modos, del más tacaño al más rápido. "Máxima batería" escucha '
            '4 segundos cada 5 minutos y aguanta días; "Rápido" escucha casi '
            'siempre y gasta mucho más.',
        'En los modos de ahorro se sueltan los enlaces que llevan rato callados '
            'y se vuelven a abrir en la siguiente ventana.',
        'Modo repetidor: deja el teléfono enchufado reenviando lo de los demás. '
            'Es lo que convierte un teléfono en una antena fija.',
      ],
    ),
    GuideSection(
      icon: Icons.my_location,
      title: 'Ubicación, cercanía y brújula',
      items: <String>[
        'Compartir ubicación manda tu posición a tus contactos cada minuto, '
            'solo si te moviste más de 15 metros. Pide permiso de ubicación.',
        '"Distancia y dirección" agrega un cálculo local (sin internet) que '
            'explica a cuántos metros está la otra persona y hacia dónde ir.',
        'La brújula usa el magnetómetro del teléfono: alejate de metales y '
            'mueve el teléfono en forma de ocho si la flecha se vuelve loca.',
      ],
    ),
    GuideSection(
      icon: Icons.flashlight_on_outlined,
      title: 'Telegrafía morse',
      items: <String>[
        'Enviar: escribí cualquier frase y el teléfono la transmite en morse '
            'con la pantalla, la linterna y un pitido. No toca la radio.',
        'Recibir: la cámara lee una luz que parpadea y la pasa a texto. Si la '
            'cámara no sirve, se toca la pantalla al ritmo.',
        'Calibrar en un toque: dos segundos con la luz apagada y dos encendida. '
            'Hazlo en el lugar y con la cámara que vas a usar.',
        'El receptor contesta con dos destellos para confirmar que llegó, y '
            'guarda cada mensaje leído en el historial para copiarlo o mandarlo '
            'a la malla.',
        'Prueba de campo: manda ocho palabras de dificultad creciente y mide el '
            'porcentaje real con tu cámara y tu linterna. Aprender morse: '
            'abecedario, escucha y un juego corto.',
      ],
    ),
    GuideSection(
      icon: Icons.share_outlined,
      title: 'Compartir la app y sumar gente',
      items: <String>[
        '"Compartir la app" manda el APK por Quick Share o Bluetooth. Es la '
            'forma de que la malla crezca sin internet.',
        'Cada persona que se suma mejora los saltos: dos teléfonos a 100 metros '
            'con un tercero en el medio ya se hablan.',
      ],
    ),
    GuideSection(
      icon: Icons.lock_outline,
      title: 'Privacidad y límites honestos',
      items: <String>[
        'Sin cuentas, sin nube, sin publicidad, sin telemetría. Todo se queda '
            'en tu teléfono.',
        'No reemplaza una llamada de emergencia ni una alerta oficial: no hay '
            'internet, así que no llegan avisos de sismos, clima ni servicios '
            'públicos.',
        'El alcance real del Bluetooth es de decenas de metros, más con paredes '
            'en el medio. La malla se extiende con personas, no con antenas.',
        'Una foto o un audio no viajan más rápido porque sean urgentes: el '
            'ancho de banda es el que es.',
      ],
    ),
    GuideSection(
      icon: Icons.build_outlined,
      title: 'Si algo no funciona',
      items: <String>[
        'No aparece nadie: revisá que el Bluetooth esté encendido, que la app '
            'tenga los permisos y que el modo de radio no sea "Máxima batería" '
            'con los dos teléfonos dormidos.',
        'El mensaje no llega: mirá los ticks. Si está en cola, no hay nadie al '
            'alcance; acercate y esperá la próxima ventana de escaneo.',
        'La cámara no lee morse: calibrá en el lugar, bajá el ritmo a "Lento" y '
            'evitá el sol directo en el fondo.',
        'La malla está rara: "Reiniciar radio" en el ícono de arriba vuelve a '
            'levantar el Bluetooth sin cerrar la app.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Guía de uso')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (intro) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chasqui funciona sin internet',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Los mensajes saltan de teléfono en teléfono por Bluetooth. '
                    'Esta guía explica todo lo que hay adentro; podés volver a '
                    'ella desde Ajustes cuando quieras.',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final section in sections) _GuideTile(section: section),
          const SizedBox(height: 16),
          Text(
            'Todo lo que hace Chasqui está pensado para funcionar con el '
            'teléfono solo: sin señal, sin datos y sin servidores.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class GuideSection {
  const GuideSection({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<String> items;
}

class _GuideTile extends StatelessWidget {
  const _GuideTile({required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(section.icon, color: scheme.primary),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
