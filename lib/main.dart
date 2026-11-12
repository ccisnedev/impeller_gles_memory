import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Minimal reproduction: graphics memory that keeps growing with Impeller on
/// OpenGL ES on PowerVR GPUs, e.g. the GE8320 in a Samsung Galaxy A04.
///
/// The app runs "rounds" by itself: it pushes screens with image lists,
/// scrolls them and pops. Between rounds, `tool/measure.ps1` samples
/// `dumpsys meminfo`.
///
/// Scenarios (`--dart-define=SCENARIO=...`):
///   images     push + image list + scroll + pop (default)
///   stack      same, but never pops: screens pile up
///   no_images  push + list of flat colors + scroll + pop
///   fresh      like images, but every round decodes different images
///
/// Other options:
///   ROUNDS    how many rounds (0 = endless). Default 30.
///   PAUSE_MS  pause between rounds, for sampling. Default 4000.
const scenario = String.fromEnvironment('SCENARIO', defaultValue: 'images');
const rounds = int.fromEnvironment('ROUNDS', defaultValue: 30);
const pauseMs = int.fromEnvironment('PAUSE_MS', defaultValue: 4000);
const imagesPerScreen = 24;
const screensPerRound = 3;

void main() => runApp(const App());

final navigatorKey = GlobalKey<NavigatorState>();

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Impeller GLES memory',
    navigatorKey: navigatorKey,
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _round = 0;
  String _status = 'waiting';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    // Baseline sample before the first round.
    debugPrint('IMPELLER_REPRO round=0 scenario=$scenario');
    await Future<void>.delayed(const Duration(milliseconds: pauseMs));
    while (mounted && (rounds == 0 || _round < rounds)) {
      final n = _round + 1;
      setState(() => _status = 'round $n running');
      await _oneRound(n);
      setState(() {
        _round = n;
        _status = 'round $n done';
      });
      // Marker read from logcat by tool/measure.ps1.
      debugPrint('IMPELLER_REPRO round=$n scenario=$scenario');
      await Future<void>.delayed(const Duration(milliseconds: pauseMs));
    }
    debugPrint('IMPELLER_REPRO end');
  }

  Future<void> _oneRound(int n) async {
    final nav = navigatorKey.currentState!;
    for (var s = 0; s < screensPerRound; s++) {
      final seed = scenario == 'fresh' ? n * 100 + s : s;
      final shown = Completer<void>();
      final controller = ScrollController();
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => ListScreen(
              seed: seed,
              withImages: scenario != 'no_images',
              controller: controller,
              onShown: shown,
            ),
          ),
        ),
      );
      await shown.future;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _scroll(controller);
      if (scenario != 'stack') {
        nav.pop();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        controller.dispose();
      }
    }
  }

  Future<void> _scroll(ScrollController c) async {
    if (!c.hasClients) return;
    for (var i = 0; i < 2; i++) {
      await c.animateTo(
        c.position.maxScrollExtent,
        duration: const Duration(seconds: 2),
        curve: Curves.linear,
      );
      await c.animateTo(
        0,
        duration: const Duration(seconds: 2),
        curve: Curves.linear,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Impeller GLES memory')),
    body: Center(
      child: Text(
        'scenario: $scenario\n$_status',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18),
      ),
    ),
  );
}

class ListScreen extends StatefulWidget {
  const ListScreen({
    super.key,
    required this.seed,
    required this.withImages,
    required this.controller,
    required this.onShown,
  });

  final int seed;
  final bool withImages;
  final ScrollController controller;
  final Completer<void> onShown;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  List<Uint8List>? _images;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final images = widget.withImages
        ? await Future.wait([
            for (var i = 0; i < imagesPerScreen; i++)
              generatePng(widget.seed * 1000 + i),
          ])
        : <Uint8List>[];
    if (!mounted) return;
    setState(() => _images = images);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.onShown.isCompleted) widget.onShown.complete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    return Scaffold(
      appBar: AppBar(title: Text('Screen ${widget.seed}')),
      body: images == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              controller: widget.controller,
              itemCount: imagesPerScreen,
              itemBuilder: (_, i) => ItemCard(
                index: i,
                image: widget.withImages ? images[i] : null,
              ),
            ),
    );
  }
}

/// A card like the ones in a real app: rounded corners, shadow, clipping and a
/// decoded image.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.index, this.image});

  final int index;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))],
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        SizedBox(
          width: 140,
          height: 100,
          child: image == null
              ? ColoredBox(color: Colors.primaries[index % 18])
              : Image.memory(image!, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('Item $index')),
      ],
    ),
  );
}

/// An 800×600 PNG generated on the device: no network or assets involved, and
/// each seed yields a different image, so the image cache cannot share them.
Future<Uint8List> generatePng(int seed) async {
  const width = 800.0, height = 600.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final color = Colors.primaries[seed % Colors.primaries.length];
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(width, height), [
        color,
        Colors.black,
      ]),
  );
  for (var i = 0; i < 12; i++) {
    canvas.drawCircle(
      Offset((seed * 37 + i * 61) % width, (seed * 53 + i * 47) % height),
      30.0 + (i * 7) % 50,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
  }
  final image = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
