import 'package:flutter/material.dart';

import '../core/models.dart';

class PeerAvatar extends StatelessWidget {
  const PeerAvatar({
    super.key,
    required this.name,
    this.radius = 24,
    this.online = false,
  });

  final String name;
  final double radius;
  final bool online;

  static const List<Color> _palette = [
    Color(0xFF0E9F6E),
    Color(0xFF2F80B8),
    Color(0xFF9B6BD6),
    Color(0xFFC9782F),
    Color(0xFFB84A6A),
  ];

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.substring(0, 1).toUpperCase())
        .join();
    final color = _palette[name.hashCode.abs() % _palette.length];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: color.withValues(alpha: 0.18),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: radius * 0.7,
            ),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: const Color(0xFF2FD37A),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks({super.key, required this.status, this.color});

  final MessageStatus status;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.onSurfaceVariant;
    final tint = color ?? fallback;
    switch (status) {
      case MessageStatus.queued:
        return Icon(Icons.schedule, size: 14, color: tint);
      case MessageStatus.sent:
        return Icon(Icons.check, size: 15, color: tint);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 15, color: const Color(0xFF46C0FF));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 15, color: Color(0xFFE0645B));
    }
  }
}

class SignalBars extends StatelessWidget {
  const SignalBars({super.key, this.rssi, this.active = true});

  final int? rssi;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final level = rssi == null
        ? (active ? 3 : 0)
        : rssi! > -60
            ? 4
            : rssi! > -72
                ? 3
                : rssi! > -85
                    ? 2
                    : 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final filled = i < level;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(
            width: 3.5,
            height: 5.0 + i * 4,
            decoration: BoxDecoration(
              color: filled
                  ? color
                  : Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

String formatClock(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String formatRelative(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return formatClock(time);
  if (diff == 1) return 'Ayer';
  if (diff < 7) {
    const names = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return names[time.weekday - 1];
  }
  return '${time.day}/${time.month}';
}

String formatLastSeen(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 45) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}
