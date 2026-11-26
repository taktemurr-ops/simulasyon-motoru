import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

// =================================================================== Parlat! (ASMR yıkama ve temizlik)
//
// Eşyanın üstü ızgaraya bölünür; her hücrede üst üste en çok iki kir
// katmanı vardır. Üstteki katman yalnızca kendi aletiyle kalkar:
// 1 toz -> bez, 2 çamur -> su, 3 yağ -> köpük, 4 pas -> fırça.
// Bütün hücreler temizlenince eşya parlatılır.

const List<String> kShineToolKeys = ['sCloth', 'sSpray', 'sFoam', 'sBrush'];
const List<IconData> kShineToolIcons = [Icons.dry_cleaning, Icons.water_drop, Icons.bubble_chart, Icons.brush];
const List<Color> kDirtColors = [Color(0x00000000), Color(0xAAB9A88E), Color(0xCC7A5A3A), Color(0xAA4A4030), Color(0xCCB0562E)];

/// Eşyalar: araba, bisiklet, kanepe, pencere, ayakkabı, tencere, bahçe cücesi, sandal.
const List<String> kShineObjKeys = ['sCar', 'sBike', 'sSofa', 'sWindow', 'sShoe', 'sPot', 'sGnome', 'sBoat'];
const List<Color> kShineObjColors = [
  Color(0xFFE4572E), Color(0xFF2F8F6B), Color(0xFF6C5CE7), Color(0xFF8CC0DE),
  Color(0xFFF2A516), Color(0xFF9AA3AE), Color(0xFFD94F70), Color(0xFF3F6FD8),
];

/// Eşya biçimleri: normalleştirilmiş dikdörtgen (r) ve elips (e) parçaları.
const List<List<(bool, double, double, double, double)>> kShineShapes = [
  [(false, 0.05, 0.45, 0.9, 0.3), (false, 0.25, 0.25, 0.5, 0.25), (true, 0.12, 0.65, 0.22, 0.25), (true, 0.66, 0.65, 0.22, 0.25)],
  [(true, 0.02, 0.5, 0.36, 0.4), (true, 0.62, 0.5, 0.36, 0.4), (false, 0.2, 0.4, 0.6, 0.12), (false, 0.45, 0.2, 0.1, 0.3)],
  [(false, 0.05, 0.3, 0.9, 0.25), (false, 0.0, 0.5, 1.0, 0.3), (false, 0.05, 0.8, 0.1, 0.15), (false, 0.85, 0.8, 0.1, 0.15)],
  [(false, 0.1, 0.05, 0.8, 0.9)],
  [(false, 0.1, 0.45, 0.8, 0.3), (true, 0.05, 0.25, 0.5, 0.45), (false, 0.05, 0.72, 0.9, 0.12)],
  [(true, 0.1, 0.3, 0.8, 0.6), (false, 0.0, 0.35, 0.15, 0.08), (false, 0.85, 0.35, 0.15, 0.08)],
  [(true, 0.25, 0.4, 0.5, 0.55), (false, 0.3, 0.05, 0.4, 0.4), (true, 0.3, 0.3, 0.4, 0.25)],
  [(true, 0.0, 0.45, 1.0, 0.35), (false, 0.45, 0.05, 0.06, 0.45), (false, 0.2, 0.1, 0.25, 0.3)],
];

bool shineInside(int obj, double x, double y) {
  for (final (ell, l, t, w, h) in kShineShapes[obj]) {
    if (ell) {
      final cx = l + w / 2, cy = t + h / 2;
      final dx = (x - cx) / (w / 2), dy = (y - cy) / (h / 2);
      if (dx * dx + dy * dy <= 1) return true;
    } else if (x >= l && x <= l + w && y >= t && y <= t + h) {
      return true;
    }
  }
  return false;
}

/// Kir katmanının temizleyen aleti.
int toolFor(int dirt) => dirt - 1;

class ShinePuzzle extends SPuzzle {
  final int obj;
  final int cols;
  final int rows;

  /// Her hücre: alt katman * 8 + üst katman (0 = yok). -1 eşyanın dışı.
  final List<int> cells;
  final int par;
  const ShinePuzzle(this.obj, this.cols, this.rows, this.cells, this.par);
}

class ShineSim {
  final ShinePuzzle z;
  late final List<int> c = List<int>.of(z.cells);
  int scrubs = 0;
  ShineSim(this.z);

  static int top(int v) => v <= 0 ? 0 : (v % 8 != 0 ? v % 8 : v ~/ 8);

  static int peel(int v) => v % 8 != 0 ? (v ~/ 8) * 8 : 0;

  int get dirty => c.where((v) => v > 0).length;

  /// [tool] ile (x,y) çevresini (3x3) temizler; temizlenen katman sayısı.
  int dab(int tool, int x, int y) {
    var n = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= z.cols || yy >= z.rows) continue;
        final i = yy * z.cols + xx;
        final v = c[i];
        if (v > 0 && toolFor(top(v)) == tool) {
          c[i] = peel(v);
          n++;
        }
      }
    }
    if (n > 0) scrubs++;
    return n;
  }
}

/// Bot: her adımda en çok katman kaldıran alet ve noktayı seçer.
int shineBot(ShinePuzzle z) {
  final s = ShineSim(z);
  for (var guard = 0; guard < 2000 && s.dirty > 0; guard++) {
    var best = 0, bt = 0, bx = 0, by = 0;
    for (var t = 0; t < 4; t++) {
      for (var y = 0; y < z.rows; y++) {
        for (var x = 0; x < z.cols; x++) {
          var n = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final xx = x + dx, yy = y + dy;
              if (xx < 0 || yy < 0 || xx >= z.cols || yy >= z.rows) continue;
              final v = s.c[yy * z.cols + xx];
              if (v > 0 && toolFor(ShineSim.top(v)) == t) n++;
            }
          }
          if (n > best) {
            best = n;
            bt = t;
            bx = x;
            by = y;
          }
        }
      }
    }
    if (best == 0) return -1;
    s.dab(bt, bx, by);
  }
  return s.dirty == 0 ? s.scrubs : -1;
}

class ShineKind extends SimKind {
  @override
  String get id => 'parlat';
  const ShineKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final obj = r.nextInt(kShineShapes.length);
    final cols = 8 + d ~/ 3, rows = 7 + d ~/ 3;
    final kinds = 1 + math.min(3, d ~/ 2);
    final pool = [1, 2, 3, 4];
    r.shuffle(pool);
    final use = pool.take(kinds).toList();
    // Kir lekeleri: rastgele merkezli damlalar.
    final cells = List<int>.filled(cols * rows, -1);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (shineInside(obj, (x + 0.5) / cols, (y + 0.5) / rows)) cells[y * cols + x] = 0;
      }
    }
    final inside = [for (var i = 0; i < cells.length; i++) if (cells[i] == 0) i];
    if (inside.length < 12) return null;
    final blobs = 2 + d;
    for (var b = 0; b < blobs; b++) {
      final cIdx = r.pick(inside);
      final cx = cIdx % cols, cy = cIdx ~/ cols;
      final rad = 1 + r.nextInt(2 + d ~/ 4);
      final dirt = r.pick(use);
      for (final i in inside) {
        final x = i % cols, y = i ~/ cols;
        if ((x - cx).abs() + (y - cy).abs() > rad) continue;
        final v = cells[i];
        if (v == 0) {
          cells[i] = dirt;
        } else if (v < 8 && v != dirt && d >= 3) {
          cells[i] = v * 8 + dirt; // eski kir alta iner
        }
      }
    }
    if (cells.where((v) => v > 0).length < 6) return null;
    final probe = ShinePuzzle(obj, cols, rows, cells, 0);
    final par = shineBot(probe);
    if (par <= 0) return null;
    return ShinePuzzle(obj, cols, rows, cells, par);
  }

  @override
  bool check(SPuzzle p) =>
      p is ShinePuzzle &&
      p.cells.length == p.cols * p.rows &&
      p.cells.any((v) => v > 0) &&
      p.cells.every((v) => v < 0 || (v % 8 <= 4 && v ~/ 8 <= 4)) &&
      shineBot(p) == p.par;

  @override
  Widget build(SimPlay play) => _ShineView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('scrubs', 'Temizleme hareketi', 'Scrubs', scale: 100),
        const GameStat('shined', 'Parlatılan eşya', 'Items shined', scale: 10),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('shined', 'shined', [3, 15, 50]),
      ];
}

class _ShineView extends StatefulWidget {
  final SimPlay play;
  const _ShineView({required this.play});

  @override
  State<_ShineView> createState() => _ShineViewState();
}

class _ShineViewState extends State<_ShineView> {
  late final ShinePuzzle z = widget.play.puzzle as ShinePuzzle;
  late final ShineSim s = ShineSim(z);
  late final int total = z.cells.fold<int>(0, (a, v) => a + (v <= 0 ? 0 : (v ~/ 8 > 0 ? 2 : 1)));
  int tool = 0;
  int strokes = 0;
  bool inStroke = false;
  bool ended = false;
  bool calm = false;
  final Stopwatch watch = Stopwatch()..start();
  int sparkle = 0;

  SimPlay get play => widget.play;
  String get lang => play.lang;

  int get left => s.c.fold<int>(0, (a, v) => a + (v <= 0 ? 0 : (v ~/ 8 > 0 && v % 8 != 0 ? 2 : 1)));

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    SimPrefs.init().then((_) {
      if (mounted) setState(() => calm = play.zenMode || SimPrefs.calm);
    });
  }

  void _scrub(Offset p, Size size) {
    if (ended) return;
    final x = (p.dx / size.width * z.cols).floor(), y = (p.dy / size.height * z.rows).floor();
    if (x < 0 || y < 0 || x >= z.cols || y >= z.rows) return;
    if (!inStroke) {
      inStroke = true;
      strokes++;
    }
    final n = s.dab(tool, x, y);
    if (n > 0) {
      setState(() => sparkle++);
      if (sparkle % 4 == 0) play.sfx(Sfx.tap);
      if (s.dirty == 0) _finish();
    }
  }

  void _finish() {
    if (ended) return;
    ended = true;
    play.sfx(Sfx.win);
    // Rahatlatıcı tür: yıldız yalnız fırça darbesi sayısına bakar, kayıp yok.
    final stars = calm || strokes <= z.par ? 3 : (strokes <= z.par * 2 ? 2 : 1);
    play.win(stars: stars, calm: calm, score: 1000 + 50 * math.max(0, 3 * z.par - strokes), seconds: watch.elapsed.inSeconds,
        stats: {'scrubs': s.scrubs, 'shined': 1});
  }

  @override
  Widget build(BuildContext context) {
    final scene = SceneCanvas(
      semantics: st(lang, kShineObjKeys[z.obj]),
      paint: _paint,
      onPan: _scrub,
      onTap: (p, size) {
        _scrub(p, size);
        inStroke = false;
      },
      onPanEnd: () => inStroke = false,
    );
    return SimFrame(
      play: play,
      moneyIcon: Icons.auto_awesome,
      money: '${(100 * (1 - left / math.max(1, total))).round()}%',
      sub: '${st(lang, kShineObjKeys[z.obj])} · ${st(lang, 'sStrokes')} $strokes / ${z.par}',
      goalText: st(lang, 'sGoal'),
      progress: 1 - left / math.max(1, total),
      season: 1,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      sceneFlex: 7,
      panelFlex: 2,
      scene: scene,
      panel: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          for (var t = 0; t < 4; t++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: SChip(
                  selected: tool == t,
                  onTap: () => setState(() => tool = t),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(kShineToolIcons[t], size: 20),
                    Text(st(lang, kShineToolKeys[t]), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  void _paint(Canvas c, Size size) {
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)), fill(const Color(0xFFDDEFF6)));
    // fayans
    for (var y = 0.0; y < size.height; y += 24) {
      c.drawLine(Offset(0, y), Offset(size.width, y), stroke(const Color(0x22000000), 1));
    }
    final cw = size.width / z.cols, ch = size.height / z.rows;
    final base = kShineObjColors[z.obj];
    for (var y = 0; y < z.rows; y++) {
      for (var x = 0; x < z.cols; x++) {
        final v = s.c[y * z.cols + x];
        if (v < 0) continue;
        final r = Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5);
        c.drawRect(r, fill(base));
        if (v > 0) {
          final under = v ~/ 8, topD = ShineSim.top(v);
          if (under > 0 && v % 8 != 0) c.drawRect(r, fill(kDirtColors[under]));
          c.drawRect(r.deflate(1), fill(kDirtColors[topD]));
        } else {
          c.drawCircle(r.center + Offset(-cw * 0.2, -ch * 0.2), math.min(cw, ch) * 0.12, fill(const Color(0x88FFFFFF)));
        }
      }
    }
    if (ended || s.dirty == 0) {
      for (var i = 0; i < 12; i++) {
        final a = i * 0.52 + sparkle * 0.01;
        drawLabel(c, '✨', Offset(size.width / 2 + math.cos(a) * size.width * 0.35, size.height / 2 + math.sin(a) * size.height * 0.35), 16,
            Colors.black);
      }
    }
  }
}
