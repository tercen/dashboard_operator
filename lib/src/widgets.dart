import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(widget.title, style: theme.textTheme.headlineSmall),
            const SizedBox(width: 12),
            if (_loading)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            const Spacer(),
            ...widget.actions,
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ]),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
