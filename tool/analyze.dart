// Summarizes the CSVs written by tool/measure.ps1.
//
//   dart run tool/analyze.dart results/*.csv
//
// The `Graphics`/`GL mtrack` values from `dumpsys meminfo` behave like a signed
// 32-bit byte counter: they read 0 (and the GL mtrack line disappears) once the
// real value passes 2 GiB, and come back small after it passes 4 GiB. This
// script reconstructs the cumulative value under that assumption:
//
// * a positive reading r is exact modulo 4 GiB: value = r + k * 4 GiB;
// * k grows by one whenever a positive reading is lower than the previous
//   positive one (the counter only grew in every run so far);
// * a 0 reading means value mod 4 GiB is in [2 GiB, 4 GiB): it is not used
//   for the fit, only counted as "hidden".
//
// It then fits value = a + b * round by least squares over the positive
// readings of rounds >= 1, and does the same for the device's MemAvailable.
//
// Consistency check of the wrap assumption: for every hidden (0) reading, the
// fitted line must predict a value whose remainder modulo 4 GiB is >= 2 GiB.
// The column "hidden explained" counts how many hidden readings pass.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

const wrapKb = 4194304; // 4 GiB in kB.

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/analyze.dart results/*.csv');
    exit(64);
  }
  print(
    '| run | flutter | rounds | graphics growth (MB/round) | R² | '
    'graphics at last round (GB, reconstructed) | hidden readings | '
    'hidden explained | MemAvailable first → last (MB) | MemAvailable trend (MB/round) | '
    'native heap (MB) |',
  );
  print('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final path in args) {
    print(_row(path));
  }
}

String _row(String path) {
  final lines = File(path).readAsLinesSync();
  final flutter = lines
      .firstWhere((l) => l.startsWith('# Flutter'), orElse: () => '# ?')
      .split('•')
      .first
      .substring(2)
      .trim();
  final header = lines.firstWhere((l) => l.startsWith('round,')).split(',');
  final rows = lines
      .where(
        (l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('round,'),
      )
      .map((l) => Map.fromIterables(header, _pad(l.split(','), header.length)))
      .toList();

  var k = 0;
  int? previous;
  final gx = <double>[], gy = <double>[];
  var hidden = 0;
  final hiddenRounds = <int>[];
  double? lastGraphics;
  for (final r in rows) {
    final round = int.parse(r['round']!);
    final kb = int.tryParse(r['graphics_kb'] ?? '') ?? 0;
    if (kb == 0) {
      if (round > 0) {
        hidden++;
        hiddenRounds.add(round);
      }
      lastGraphics = null;
      continue;
    }
    if (previous != null && kb < previous) k++;
    previous = kb;
    final value = (kb + k * wrapKb).toDouble();
    lastGraphics = value;
    if (round >= 1) {
      gx.add(round.toDouble());
      gy.add(value);
    }
  }
  final g = _fit(gx, gy);
  final explained = hiddenRounds
      .where((round) => (g.intercept + g.slope * round) % wrapKb >= wrapKb / 2)
      .length;

  final mem = rows
      .where((r) => (r['device_mem_available_kb'] ?? '').isNotEmpty)
      .toList();
  String memRange = 'not recorded', memTrend = 'not recorded';
  if (mem.isNotEmpty) {
    final mx = mem.map((r) => double.parse(r['round']!)).toList();
    final my = mem
        .map((r) => double.parse(r['device_mem_available_kb']!))
        .toList();
    memRange = '${_mb(my.first)} → ${_mb(my.last)}';
    memTrend = (_fit(mx, my).slope / 1024).toStringAsFixed(1);
  }
  final heap = rows
      .where((r) => int.parse(r['round']!) >= 1)
      .map((r) => double.parse(r['native_heap_kb']!))
      .toList();

  final name = path.split(RegExp(r'[\\/]')).last;
  final last = lastGraphics == null
      ? 'hidden'
      : (lastGraphics / 1024 / 1024).toStringAsFixed(1);
  return '| $name | $flutter | ${rows.length - 1} | '
      '${(g.slope / 1024).toStringAsFixed(0)} | ${g.r2.toStringAsFixed(3)} | '
      '$last | $hidden | $explained/$hidden | $memRange | $memTrend | '
      '${_mb(heap.reduce(min))}–${_mb(heap.reduce(max))} |';
}

List<String> _pad(List<String> v, int n) => [
  ...v,
  for (var i = v.length; i < n; i++) '',
];

String _mb(double kb) => (kb / 1024).toStringAsFixed(0);

({double slope, double intercept, double r2}) _fit(
  List<double> x,
  List<double> y,
) {
  final n = x.length;
  if (n < 2) return (slope: double.nan, intercept: double.nan, r2: double.nan);
  final mx = x.reduce((a, b) => a + b) / n;
  final my = y.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  final slope = sxy / sxx;
  final r2 = syy == 0 ? 1.0 : (sxy * sxy) / (sxx * syy);
  return (slope: slope, intercept: my - slope * mx, r2: r2);
}
