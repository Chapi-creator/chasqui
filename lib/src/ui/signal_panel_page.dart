import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/rescue_service.dart';
import '../rescue/sighting.dart';

/// Símbolos de suelo a aire que reconoce un rescatista.
enum GroundSignal {
  medical('X', 'Necesito médico'),
  help('V', 'Necesito ayuda'),
  direction('', 'Voy en esta dirección');

  const GroundSignal(this.glyph, this.label);

  final String glyph;
  final String label;
}

/// Pantalla blanca con un símbolo negro gigante, para mostrarle al cielo.
///
/// Blanco sobre negro sería más "bonito"; al sol, un fondo blanco con el signo
/// negro es lo que más contraste da a distancia, y es la convención de las
/// señales de suelo a aire.
class SignalPanelPage extends StatefulWidget {
  const SignalPanelPage({
    super.key,
    required this.signal,
    this.lastSighting,
  });

  final GroundSignal signal;
  final DateTime? lastSighting;

  @override
  State<SignalPanelPage> createState() => _SignalPanelPageState();
}

class _SignalPanelPageState extends State<SignalPanelPage> {
  static const List<String> _directions = [
    'norte',
    'noreste',
    'este',
    'sureste',
    'sur',
    'suroeste',
    'oeste',
    'noroeste',
  ];

  late GroundSignal _signal = widget.signal;

  /// La flecha apunta al norte hasta que se gira: la dirección importa, así
  /// que el símbolo tiene que poder orientarse.
  int _turns = 0;

  @override
  void initState() {
    super.initState();
    // Pantalla despierta y al máximo: de nada sirve el símbolo si el teléfono
    // se apaga a los treinta segundos o se ve gris.
    RescueService.keepAwake(true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    RescueService.keepAwake(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sighting = widget.lastSighting;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: Center(child: _buildGlyph())),
            _buildBottomBar(sighting),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.black),
          ),
          const Spacer(),
          for (final signal in GroundSignal.values)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _SignalChip(
                signal: signal,
                selected: signal == _signal,
                onTap: () => setState(() => _signal = signal),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlyph() {
    final size = MediaQuery.sizeOf(context);
    final side = math.min(size.width, size.height) * 0.82;
    if (_signal == GroundSignal.direction) {
      return Transform.rotate(
        angle: _turns * math.pi / 4,
        child: SizedBox(
          width: side * 0.7,
          height: side,
          child: const CustomPaint(painter: _ArrowPainter()),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: Text(
        _signal.glyph,
        style: TextStyle(
          fontSize: side,
          height: 0.95,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildBottomBar(DateTime? sighting) {
    final age = sighting == null
        ? null
        : formatSightingAge(DateTime.now().difference(sighting));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _signal.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          if (_signal == GroundSignal.direction) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _turns = (_turns + 1) % 8),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black26),
              ),
              icon: const Icon(Icons.rotate_right),
              label: Text('Girar 45° · apunta al ${_directions[_turns]}'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            age == null
                ? 'Sin avistamientos marcados'
                : 'Último avistamiento: $age',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pantalla al máximo y sin apagarse. La radio sigue igual.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Franja de tres botones para cambiar de símbolo sin volver atrás.
class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.signal,
    required this.selected,
    required this.onTap,
  });

  final GroundSignal signal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: signal == GroundSignal.direction
            ? Icon(
                Icons.arrow_upward,
                size: 18,
                color: selected ? Colors.white : Colors.black,
              )
            : Text(
                signal.glyph,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : Colors.black,
                ),
              ),
      ),
    );
  }
}

/// Flecha ancha de señalización: mango grueso y cabeza triangular.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final cx = size.width / 2;
    final shaftHalf = size.width * 0.09;
    final headBottom = size.height * 0.34;

    // Mango.
    canvas.drawRect(
      Rect.fromLTRB(cx - shaftHalf, headBottom, cx + shaftHalf, size.height * 0.94),
      paint,
    );
    // Cabeza.
    final head = Path()
      ..moveTo(cx, 0)
      ..lineTo(size.width * 0.94, headBottom)
      ..lineTo(size.width * 0.06, headBottom)
      ..close();
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) => false;
}
