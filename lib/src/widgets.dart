import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sci_http_client/error.dart';

import 'admin_api.dart';
import 'platform/platform_stub.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart' as platform;
import 'theme.dart';

/// Severity buckets, resolved against the active theme so chips read
/// correctly on both the black and the white ground.
enum Severity { ok, warn, bad, info, neutral }

/// Colored chip for a task/worker state.
class StateChip extends StatelessWidget {
  final String state;
  const StateChip(this.state, {super.key});

  static const _severities = <String, Severity>{
    'RunningState': Severity.info,
    'RunningDependentState': Severity.info,
    'PendingState': Severity.warn,
    'InitState': Severity.warn,
    'DoneState': Severity.ok,
    'FailedState': Severity.bad,
    'CanceledState': Severity.neutral,
    // Worker statuses share the widget.
    'Available': Severity.ok,
    'Idle': Severity.info,
    'Unavailable': Severity.bad,
    'Terminating': Severity.warn,
    'Terminated': Severity.neutral,
  };

  static (Color, Color) colorsFor(BuildContext context, Severity severity) {
    final c = Theme.of(context).extension<DashboardColors>() ??
        DashboardColors.dark;
    return switch (severity) {
      Severity.ok => (c.okBg, c.okFg),
      Severity.warn => (c.warnBg, c.warnFg),
      Severity.bad => (c.badBg, c.badFg),
      Severity.info => (c.infoBg, c.infoFg),
      Severity.neutral => (c.neutralBg, c.neutralFg),
    };
  }

  @override
  Widget build(BuildContext context) {
    final label = state.endsWith('State')
        ? state.substring(0, state.length - 5)
        : state;
    final (bg, fg) =
        colorsFor(context, _severities[state] ?? Severity.neutral);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// KPI tile for the overview grid.
class KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color? valueColor;

  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(letterSpacing: 0.8)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600, color: valueColor)),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(detail!,
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard panel body: title row with refresh control, then content that
/// reloads on demand and on a fixed interval while the panel is visible.
class RefreshingPanel<T> extends StatefulWidget {
  final String title;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback refresh)
      builder;
  final Duration interval;
  final List<Widget> actions;

  const RefreshingPanel({
    super.key,
    required this.title,
    required this.load,
    required this.builder,
    this.interval = const Duration(seconds: 15),
    this.actions = const [],
  });

  @override
  State<RefreshingPanel<T>> createState() => _RefreshingPanelState<T>();
}

class _RefreshingPanelState<T> extends State<RefreshingPanel<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.interval, (_) => _refresh(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Mobile-friendly: on narrow screens the actions (filters, pickers)
    // wrap onto their own line under the title instead of overflowing.
    final isNarrow = isNarrowLayout(context);
    final titleRow = Row(children: [
      // On narrow screens the app bar already names the panel.
      if (!isNarrow) ...[
        Text(widget.title, style: theme.textTheme.headlineSmall),
        const SizedBox(width: 12),
      ],
      if (_loading)
        const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
      const Spacer(),
      if (!isNarrow) ...widget.actions,
      IconButton(
        tooltip: 'Refresh',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh),
      ),
    ]);

    return Padding(
      padding: EdgeInsets.all(isNarrow ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow,
          if (isNarrow && widget.actions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: widget.actions),
          ],
          const SizedBox(height: 12),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final error = _error;
    final data = _data;
    if (error != null && data == null) {
      return ErrorBox(error: error, onRetry: _refresh);
    }
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return widget.builder(context, data, _refresh);
  }
}

class ErrorBox extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorBox({super.key, required this.error, this.onRetry});

  /// A 404 here means the server has no such route, not that something
  /// broke: this panel needs a Tercen build carrying AdminService /
  /// UsageService. Say that plainly instead of showing a raw error.
  bool get _serverTooOld {
    final e = error;
    return e is ServiceError &&
        (e.statusCode == 404 || e.error == AdminApi.unavailableCode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_serverTooOld) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off_outlined,
                    color: theme.colorScheme.onSurfaceVariant, size: 30),
                const SizedBox(height: 12),
                Text('Not available on this server',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'This panel needs the dashboard API (AdminService / '
                  'UsageService), which this Tercen build does not have. '
                  'Tasks and Workers keep working; the rest arrives when the '
                  'server is upgraded.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    color: theme.colorScheme.error, size: 32),
                const SizedBox(height: 10),
                SelectableText('$error', textAlign: TextAlign.center),
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                      onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Monospace value with one-tap copy, for ids and hashes.
class CopyableId extends StatelessWidget {
  final String value;
  const CopyableId(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const Text('—');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 14,
        tooltip: 'Copy',
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied'), width: 160));
          }
        },
        icon: const Icon(Icons.copy_outlined),
      ),
    ]);
  }
}

/// Phone-shaped viewport. Width < 720 is the design breakpoint; the touch
/// tiebreaker catches Chrome's "Desktop site" mode, which lays a phone out
/// at ~980px (viewport meta ignored, desktop UA) but can't hide the
/// touchscreen.
bool isNarrowLayout(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width < 720 || (platform.isTouchDevice() && width < 1024);
}

/// Tercen's App icon (tercen-style icons/App.svg): a 4x4 grid of coloured
/// squares, drawn natively so the app needs no SVG package. It keeps its
/// own colours in both themes — no IconTheme, no tint.
class TercenAppIcon extends StatelessWidget {
  final double size;
  const TercenAppIcon({super.key, this.size = 24});

  /// The SVG's fills, row by row, left to right.
  static const colors = <Color>[
    Color(0xFFFF0000), Color(0xFFFF8200), Color(0xFF99FF00), Color(0xFFFFBF00),
    Color(0xFF9333EA), Color(0xFF0099FF), Color(0xFF6D0000), Color(0xFF66FF7F),
    Color(0xFFE040FB), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFF0D9488),
    Color(0xFFFF4F00), Color(0xFFEC4899), Color(0xFFFFF8DC), Color(0xFFFFDD00),
  ];

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size), painter: const _AppIconPainter());
}

class _AppIconPainter extends CustomPainter {
  const _AppIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // crispEdges: no anti-aliasing, and each cell edge is the next cell's
    // edge, so no seam shows between squares.
    final paint = Paint()..isAntiAlias = false;
    double edge(double extent, int i) => (extent * i / 4).roundToDouble();
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        paint.color = TercenAppIcon.colors[row * 4 + col];
        canvas.drawRect(
            Rect.fromLTRB(edge(size.width, col), edge(size.height, row),
                edge(size.width, col + 1), edge(size.height, row + 1)),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AppIconPainter oldDelegate) => false;
}
