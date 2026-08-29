import 'package:flutter/material.dart';

import 'theme.dart';
import 'usage.dart';

/// Runs over time: one bar per bucket, split into succeeded and failed.
///
/// The two segments sum to the bar's total, so this stays a single-axis
/// chart. Failure wears the reserved critical status color (never a
/// categorical hue) and is always named in the legend, so the split is
/// never carried by color alone.
class RunsBarChart extends StatefulWidget {
  final List<UsageRow> rows;
  final String Function(String bucketLabel) formatBucket;

  const RunsBarChart({
    super.key,
    required this.rows,
    required this.formatBucket,
  });

  @override
  State<RunsBarChart> createState() => _RunsBarChartState();
}

class _RunsBarChartState extends State<RunsBarChart> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<DashboardColors>() ?? DashboardColors.dark;
    final rows = widget.rows;

    if (rows.isEmpty) {
      return _EmptyPlot(message: 'No runs in this period.');
    }

    final maxRuns =
        rows.map((r) => r.n).fold<int>(0, (a, b) => a > b ? a : b);

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final plotHeight = 190.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Legend(
            entries: [
              ('Succeeded', theme.colorScheme.primary),
              ('Failed', colors.badFg),
            ],
          ),
          const SizedBox(height: 12),
          MouseRegion(
            onExit: (_) => setState(() => _hovered = null),
            onHover: (event) {
              final index = _indexAt(event.localPosition.dx, width, rows.length);
              if (index != _hovered) setState(() => _hovered = index);
            },
            child: SizedBox(
              height: plotHeight,
              width: double.infinity,
              child: Stack(children: [
                CustomPaint(
                  size: Size(width, plotHeight),
                  painter: _RunsPainter(
                    rows: rows,
                    maxRuns: maxRuns,
                    hovered: _hovered,
                    barColor: theme.colorScheme.primary,
                    failColor: colors.badFg,
                    gridColor: theme.colorScheme.outline,
                    labelColor: theme.colorScheme.onSurfaceVariant,
                    surface: theme.colorScheme.surface,
                    formatBucket: widget.formatBucket,
                  ),
                ),
                if (_hovered != null && _hovered! < rows.length)
                  _tooltip(context, rows[_hovered!], width, plotHeight),
              ]),
            ),
          ),
        ],
      );
    });
  }

  int? _indexAt(double dx, double width, int count) {
    if (count == 0) return null;
    final slot = width / count;
    final index = (dx / slot).floor();
    return (index < 0 || index >= count) ? null : index;
  }

  Widget _tooltip(
      BuildContext context, UsageRow row, double width, double height) {
    final theme = Theme.of(context);
    final slot = width / widget.rows.length;
    final centre = (_hovered! + 0.5) * slot;
    const tooltipWidth = 172.0;
    final left = (centre - tooltipWidth / 2).clamp(0.0, width - tooltipWidth);

    return Positioned(
      left: left,
      top: 0,
      child: IgnorePointer(
        child: Container(
          width: tooltipWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.formatBucket(row.bucket),
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              _tooltipLine(context, 'Runs', '${row.n}'),
              _tooltipLine(context, 'Failed', '${row.failed}'),
              _tooltipLine(context, 'Compute',
                  '${(row.duration / 60).toStringAsFixed(1)} min'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tooltipLine(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _RunsPainter extends CustomPainter {
  final List<UsageRow> rows;
  final int maxRuns;
  final int? hovered;
  final Color barColor;
  final Color failColor;
  final Color gridColor;
  final Color labelColor;
  final Color surface;
  final String Function(String) formatBucket;

  _RunsPainter({
    required this.rows,
    required this.maxRuns,
    required this.hovered,
    required this.barColor,
    required this.failColor,
    required this.gridColor,
    required this.labelColor,
    required this.surface,
    required this.formatBucket,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelBand = 20.0;
    final plotHeight = size.height - labelBand;
    final slot = size.width / rows.length;
    // Thin marks: cap the bar so dense periods stay readable.
    final barWidth = (slot * 0.62).clamp(2.0, 26.0);
    final scale = maxRuns == 0 ? 0.0 : plotHeight / maxRuns;

    // Recessive gridlines at 0 / 50 / 100% of the max.
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = plotHeight - plotHeight * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    _text(canvas, '$maxRuns', const Offset(2, 0), labelColor, 10);

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final centre = (i + 0.5) * slot;
      final left = centre - barWidth / 2;
      final isHovered = hovered == i;

      final totalHeight = row.n * scale;
      final failHeight = row.failed * scale;
      final okHeight = (totalHeight - failHeight).clamp(0.0, plotHeight);

      // Succeeded: anchored to the baseline, 4px rounded top when it is the
      // top of the bar.
      if (okHeight > 0) {
        final topRounded = failHeight <= 0;
        _bar(
          canvas,
          Rect.fromLTWH(left, plotHeight - okHeight, barWidth, okHeight),
          barColor.withValues(alpha: isHovered ? 1.0 : 0.85),
          roundTop: topRounded,
        );
      }
      // Failed: stacked above, separated by a 2px surface gap.
      if (failHeight > 0) {
        final top = plotHeight - totalHeight;
        _bar(
          canvas,
          Rect.fromLTWH(left, top, barWidth,
              (failHeight - (okHeight > 0 ? 2 : 0)).clamp(1.0, plotHeight)),
          failColor.withValues(alpha: isHovered ? 1.0 : 0.9),
          roundTop: true,
        );
      }
    }

    // Selective labels: first and last bucket only — never one per bar.
    if (rows.isNotEmpty) {
      _text(canvas, formatBucket(rows.first.bucket),
          Offset(0, plotHeight + 4), labelColor, 10.5);
      if (rows.length > 1) {
        final label = formatBucket(rows.last.bucket);
        _text(canvas, label,
            Offset(size.width - label.length * 5.6, plotHeight + 4),
            labelColor, 10.5);
      }
    }
  }

  void _bar(Canvas canvas, Rect rect, Color color, {required bool roundTop}) {
    final paint = Paint()..color = color;
    final radius = roundTop
        ? const BorderRadius.vertical(top: Radius.circular(4))
        : BorderRadius.zero;
    canvas.drawRRect(radius.toRRect(rect), paint);
  }

  void _text(Canvas canvas, String value, Offset at, Color color, double size) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _RunsPainter old) =>
      old.rows != rows || old.hovered != hovered || old.maxRuns != maxRuns;
}

class _Legend extends StatelessWidget {
  final List<(String, Color)> entries;
  const _Legend({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 16, children: [
      for (final (label, color) in entries)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          // Text keeps ink tokens; the swatch carries identity.
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
    ]);
  }
}

class _EmptyPlot extends StatelessWidget {
  final String message;
  const _EmptyPlot({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
