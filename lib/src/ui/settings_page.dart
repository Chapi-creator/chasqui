import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_version.dart';
import '../mesh/mesh_node.dart';
import '../platform/app_share.dart';
import '../platform/location_service.dart';
import '../platform/power_service.dart';
import '../power/power_policy.dart';
import 'widgets.dart';

/// Texto que explica cuánta radio se está gastando ahora mismo.
///
/// En una emergencia la batería es el recurso que no se repone: el usuario
/// tiene que poder ver el porcentaje, no solo elegir un nombre de modo.
String _radioSummary(MeshNode node) {
  final plan = node.scanPlan;
  final duty = (plan.dutyCycle * 100).toStringAsFixed(1).replaceAll('.', ',');
  if (node.relayMode) {
    return 'Modo repetidor: escucha ${plan.window.inSeconds}s de cada '
        '${plan.interval.inSeconds}s. Es el que más gasta, para un teléfono '
        'enchufado.';
  }
  return 'Ahora mismo: ${plan.window.inSeconds}s de radio cada '
      '${plan.interval.inSeconds}s (≈$duty % del tiempo). Las ventanas caen en '
      'el mismo instante en todos los teléfonos, así que se puede dormir más '
      'sin perder encuentros. En Máxima batería y Ahorro se sueltan además los '
      'enlaces que llevan rato sin tráfico; los mensajes pueden tardar unos '
      'minutos en salir.';
}

TextStyle? _radioSummaryStyle(ColorScheme scheme) =>
    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.45);

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        InfoCard(
          child: Row(
            children: [
              PeerAvatar(name: node.displayName, radius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: node.identity.id),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Identidad copiada')),
                          );
                        }
                      },
                      child: Text(
                        'ID ${node.nodeShortId} · identidad X25519',
                        style: TextStyle(fontSize: 12, color: scheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cambiar nombre',
                onPressed: () => _editName(context, node),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Radio y batería'),
        const SizedBox(height: 8),
        InfoCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: RadioGroup<RadioMode>(
            groupValue: node.radioMode,
            onChanged: (value) {
              if (value != null) node.setRadioMode(value);
            },
            child: Column(
              children: [
                for (final mode in RadioMode.values)
                  RadioListTile<RadioMode>(
                    value: mode,
                    title: Text(mode.label),
                    subtitle: Text(
                      mode.description,
                      style: const TextStyle(fontSize: 12),
                    ),
                    dense: true,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(_radioSummary(node), style: _radioSummaryStyle(scheme)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: PowerService.openBatterySettings,
          icon: const Icon(Icons.battery_saver_outlined, size: 18),
          label: const Text('Permitir en segundo plano'),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Radio'),
        const SizedBox(height: 8),
        InfoCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              SwitchListTile(
                value: node.usingDemo,
                onChanged: (value) async {
                  final transport = value
                      ? node.createDemoTransport()
                      : node.createBleTransport();
                  await node.switchTransport(transport, demo: value);
                  if (!context.mounted) return;
                  if (!value && node.error != null) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(node.error!)));
                  }
                },
                title: const Text('Modo demo'),
                subtitle: const Text(
                  'Nodos simulados para probar sin otros teléfonos. '
                  'Hablan el protocolo real: cifran, confirman y responden.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reiniciar radio'),
                subtitle: Text(node.transportLabel),
                onTap: () async {
                  // Por si el usuario concedió los permisos después.
                  await PowerService.requestPermissions();
                  await node.restartRadio();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Ubicación y cercanía'),
        const SizedBox(height: 8),
        InfoCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              SwitchListTile(
                value: node.shareLocation,
                onChanged: (value) => _toggleLocation(context, node, value),
                title: const Text('Compartir mi ubicación'),
                subtitle: const Text(
                  'Envía tus coordenadas, cifradas, solo a tus contactos. '
                  'Sirve para que vean a qué distancia estás y en qué '
                  'dirección. Sin internet y sin servidores.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: node.showProximity,
                onChanged: node.setShowProximity,
                title: const Text('Distancia y dirección'),
                subtitle: const Text(
                  'Muestra «≈30 m al NE» de quien comparte su ubicación. '
                  'Sin coordenadas del otro teléfono solo se puede estimar '
                  '«cerca o lejos» por la señal: una antena no da dirección.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (node.shareLocation)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              node.myLocation == null
                  ? 'Esperando la primera posición del GPS…'
                  : 'Última posición: ${node.myLocation}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        TextButton.icon(
          onPressed: LocationService.openSettings,
          icon: const Icon(Icons.location_on_outlined, size: 18),
          label: const Text('Permiso de ubicación del sistema'),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Apagón y emergencia'),
        const SizedBox(height: 8),
        InfoCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              SwitchListTile(
                value: node.relayMode,
                onChanged: (value) => node.setRelayMode(value),
                title: const Text('Modo repetidor'),
                subtitle: const Text(
                  'Escucha casi todo el tiempo para reenviar los mensajes de '
                  'otros. Deja el teléfono enchufado: gasta bastante más '
                  'batería que el modo normal.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(
                  node.charging
                      ? Icons.battery_charging_full
                      : Icons.battery_std,
                ),
                title: Text(
                  'Batería ${node.batteryPercent}%'
                  '${node.charging ? ' · cargando' : ''}',
                ),
                subtitle: Text(
                  node.relayMode
                      ? 'Repetidor activo · ${node.relayedCount} tramas '
                            'reenviadas desde que abrió la app'
                      : 'Con este modo la radio descansa entre ventanas.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Compartir la app'),
                subtitle: const Text(
                  'Manda el APK por Quick Share o Bluetooth. Funciona sin '
                  'internet ni Play Store.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final sent = await AppShare.shareApk();
                  if (!sent) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No se pudo abrir el selector para compartir el APK.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'El canal Todos, en Chats, manda avisos a cualquiera que esté en la '
          'malla. El SOS se envía manteniendo pulsado el botón rojo del canal: '
          'incluye tu posición si la tienes y se reintenta solo.',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Cómo viaja un mensaje'),
        const SizedBox(height: 8),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Bullet(
                icon: Icons.lock_outline,
                text:
                    'Se cifra con la clave pública del destinatario '
                    '(X25519 + AES-256-GCM). Quien repite no puede leerlo.',
              ),
              SizedBox(height: 10),
              _Bullet(
                icon: Icons.alt_route,
                text:
                    'Salta de teléfono en teléfono con TTL 3 y '
                    'deduplicación para no inundar la banda.',
              ),
              SizedBox(height: 10),
              _Bullet(
                icon: Icons.outbox_outlined,
                text:
                    'Si el destinatario no está cerca, el mensaje queda en '
                    'cola hasta 24 h y se reintenta en cada enlace nuevo.',
              ),
              SizedBox(height: 10),
              _Bullet(
                icon: Icons.battery_charging_full,
                text:
                    'La radio solo escucha en ventanas cortas. '
                    'El advertising se mantiene porque gasta mucho menos.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Límites honestos'),
        const SizedBox(height: 8),
        InfoCard(
          child: Text(
            '• El alcance por salto es Bluetooth (10–100 m). Para kilómetros '
            'hacen falta teléfonos intermedios o radios LoRa.\n'
            '• El cifrado es estático: no hay forward secrecy todavía.\n'
            '• Android puede matar el proceso si no se permite el segundo '
            'plano; por eso existe el servicio en primer plano.\n'
            '• El canal Todos es abierto: el nombre y la batería que muestra '
            'los declara quien escribe, no hay firma detrás.\n'
            '• Es un prototipo: no uses esto para nada crítico ni ilegal.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Image.asset(
            'assets/brand/sinred_logo.png',
            width: 76,
            height: 76,
            // El logo es decorativo: sin la imagen la app sigue siendo usable.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'SinRed $appVersion · malla BLE sin internet',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  /// Enciende el GPS solo si el usuario concede el permiso; si no, el
  /// interruptor vuelve a apagado en vez de quedarse mintiendo.
  Future<void> _toggleLocation(
    BuildContext context,
    MeshNode node,
    bool value,
  ) async {
    if (!value) {
      await node.setShareLocation(false);
      await LocationService.stop();
      return;
    }
    final granted = await LocationService.requestPermission();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin permiso de ubicación no se pueden compartir coordenadas.',
          ),
        ),
      );
      return;
    }
    final started = await LocationService.start();
    if (!context.mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enciende la ubicación del teléfono (GPS) para compartirla.',
          ),
        ),
      );
      return;
    }
    // Si ya hay una última posición conocida se usa de inmediato; si no, se
    // espera al primer aviso del GPS, que llega al flujo de la app.
    final point = await LocationService.current();
    if (point != null) node.updateMyLocation(point);
    await node.setShareLocation(true);
  }

  Future<void> _editName(BuildContext context, MeshNode node) async {
    final controller = TextEditingController(text: node.displayName);
    final String? value;
    try {
      value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tu nombre en la malla'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(
              hintText: 'Cómo te verán los demás',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
    } finally {
      // El controlador se crea para el diálogo y se libera con él: dejarlo vivo
      // era una fuga por cada cambio de nombre.
      controller.dispose();
    }
    if (value != null && value.isNotEmpty) {
      node.setDisplayName(value);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
