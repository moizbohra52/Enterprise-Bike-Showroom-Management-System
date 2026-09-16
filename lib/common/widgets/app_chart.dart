import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A labeled data point for [AppLineChart] / [AppBarChart].
class ChartSeries {
  const ChartSeries({
    required this.name,
    required this.points,
    this.color = const Color(0xFF14532D),
  });

  final String name;
  final List<FlSpot> points;
  final Color color;
}

/// A pie/donut segment.
class ChartSlice {
  const ChartSlice({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;
}

const List<Color> _defaultColors = <Color>[
  Color(0xFF14532D),
  Color(0xFFF59E0B),
  Color(0xFF2563EB),
  Color(0xFFDC2626),
  Color(0xFF0EA5E9),
  Color(0xFF9333EA),
  Color(0xFF64748B),
  Color(0xFF16A34A),
];

/// Line/area trend chart.
class AppLineChart extends StatelessWidget {
  const AppLineChart({
    super.key,
    required this.series,
    this.xLabels = const <String>[],
    this.height = 240,
    this.showArea = true,
    this.yTitle,
  });

  final List<ChartSeries> series;
  final List<String> xLabels;
  final double height;
  final bool showArea;
  final String? yTitle;

  @override
  Widget build(BuildContext context) {
    double maxY = 1;
    double maxX = 1;
    for (final ChartSeries s in series) {
      for (final FlSpot p in s.points) {
        if (p.y > maxY) maxY = p.y;
        if (p.x > maxX) maxX = p.x;
      }
    }
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: xLabels.isNotEmpty,
                reservedSize: 22,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= xLabels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(xLabels[index],
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: (maxY / 4).ceilToDouble(),
                getTitlesWidget: (double value, TitleMeta meta) {
                  return Text(
                    _compact(value),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: maxX,
          minY: 0,
          maxY: maxY * 1.15,
          lineTouchData: const LineTouchData(enabled: true),
          lineBarsData: <LineChartBarData>[
            for (final ChartSeries s in series)
              LineChartBarData(
                spots: s.points,
                isCurved: true,
                barWidth: 3,
                color: s.color,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: showArea,
                  color: s.color.withAlpha(25),
                ),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _compact(double value) {
    if (value >= 10000000) return '${(value / 10000000).toStringAsFixed(1)}Cr';
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

/// Vertical bar chart.
class AppBarChart extends StatelessWidget {
  const AppBarChart({
    super.key,
    required this.series,
    this.xLabels = const <String>[],
    this.height = 240,
  });

  final List<ChartSeries> series;
  final List<String> xLabels;
  final double height;

  @override
  Widget build(BuildContext context) {
    double maxY = 1;
    for (final ChartSeries s in series) {
      for (final FlSpot p in s.points) {
        if (p.y > maxY) maxY = p.y;
      }
    }
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: xLabels.isNotEmpty,
                reservedSize: 22,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= xLabels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(xLabels[index],
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: (maxY / 4).ceilToDouble(),
                getTitlesWidget: (double value, TitleMeta meta) {
                  return Text(
                    _compact(value),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          maxY: maxY * 1.15,
          barTouchData: BarTouchData(enabled: true),
          barGroups: <BarChartGroupData>[
            for (int i = 0; i < _maxPoints(); i++)
              BarChartGroupData(x: i, barRods: <BarChartRodData>[
                for (final ChartSeries s in series)
                  if (i < s.points.length)
                    BarChartRodData(
                      toY: s.points[i].y,
                      width: 14,
                      borderRadius: BorderRadius.circular(4),
                      color: s.color,
                    ),
              ]),
          ],
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  int _maxPoints() {
    int max = 0;
    for (final ChartSeries s in series) {
      if (s.points.length > max) max = s.points.length;
    }
    return max;
  }

  String _compact(double value) {
    if (value >= 10000000) return '${(value / 10000000).toStringAsFixed(1)}Cr';
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

/// Donut chart with a legend.
class AppPieChart extends StatelessWidget {
  const AppPieChart({
    super.key,
    required this.slices,
    this.height = 240,
  });

  final List<ChartSlice> slices;
  final double height;

  @override
  Widget build(BuildContext context) {
    double total = 0;
    for (final ChartSlice s in slices) {
      total += s.value;
    }
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double available = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : height;
                final double side = available < height ? available : height;
                final double radius = side / 2;
                // 55% of the radius is left empty => donut look.
                final double holeRadius = radius * 0.55;
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: side,
                      height: side,
                      child: PieChart(
                        PieChartData(
                          startDegreeOffset: -90,
                          sectionsSpace: 2,
                          centerSpaceRadius: holeRadius,
                          sections: <PieChartSectionData>[
                            for (int i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                value: slices[i].value,
                                color: slices[i].color ??
                                    _defaultColors[i % _defaultColors.length],
                                radius: radius - holeRadius,
                                title: '',
                                showTitle: false,
                              ),
                          ],
                        ),
                        duration: const Duration(milliseconds: 300),
                      ),
                    ),
                    Center(
                      child: Text(
                        _compact(total),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: ListView(
              children: <Widget>[
                for (int i = 0; i < slices.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: slices[i].color ??
                                _defaultColors[i % _defaultColors.length],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(slices[i].label,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(
                          total == 0
                              ? '0%'
                              : '${(slices[i].value / total * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _compact(double value) {
    if (value >= 10000000) return '${(value / 10000000).toStringAsFixed(1)}Cr';
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}
