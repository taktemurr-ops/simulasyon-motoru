import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

// =================================================================== Ev Yenileme (dekor + yerleştirme bulmacası)
//
// Odanın boş zemini, verilen mobilyalarla tam olarak doldurulur (kapı önü ve
// sütunlar boş kalır). Mobilyalar döndürülebilir. Her çözülen oda yıldız
// kazandırır; yıldızlarla duvar rengi ve zemin deseni açılır (kalıcı dekor).

/// Mobilya türleri: (genişlik, yükseklik, emoji, anahtar).
const List<(int, int, String, String)> kFurniture = [
  (1, 1, '🪴', 'rPlant'),
  (1, 2, '🚪', 'rWardrobe'),
  (1, 3, '📚', 'rShelf'),
  (2, 2, '🪑', 'rTable'),
  (2, 3, '🛏️', 'rBed'),
  (1, 2, '🖥️', 'rDesk'),
  (2, 1, '🛋️', 'rSofa'),
  (3, 1, '🛋️', 'rCouch'),
];

const List<Color> kWallColors = [
  Color(0xFFF3E6D0), Color(0xFFDCEBDD), Color(0xFFDDE6F3), Color(0xFFF3DCDC), Color(0xFFEDE3F5), Color(0xFFF7EFC4),
];
const List<Color> kFloorColors = [
  Color(0xFFC9A27A), Color(0xFFB8B8B8), Color(0xFF9C7A5B), Color(0xFFD8C3A5), Color(0xFF7F9C8C), Color(0xFFB48E7A),
];

class RenoPiece {
  final int type;
  final int w;
  final int h;
  const RenoPiece(this.type, this.w, this.h);
}

class RenoPuzzle extends SPuzzle {
  final int cols;
  final int rows;

  /// Kapalı hücreler (kapı önü, sütun).
  final List<bool> blocked;
  final List<RenoPiece> pieces;

  /// Üreticinin çözümü: her parça için (x, y, döndürülmüş mü).
  final List<(int, int, bool)> solution;
  const RenoPuzzle(this.cols, this.rows, this.blocked, this.pieces, this.solution);
}

/// Parçayı yerleştirir; sığmazsa false.
bool renoFits(int cols, int rows, List<int> grid, RenoPiece p, int x, int y, bool rot) {
  final w = rot ? p.h : p.w, h = rot ? p.w : p.h;
  if (x < 0 || y < 0 || x + w > cols || y + h > rows) return false;
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      if (grid[(y + j) * cols + x + i] != -1) return false;
    }
  }
  return true;
}

void renoPut(int cols, List<int> grid, RenoPiece p, int x, int y, bool rot, int id) {
  final w = rot ? p.h : p.w, h = rot ? p.w : p.h;
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      grid[(y + j) * cols + x + i] = id;
    }
  }
}

/// Çözüm geçerli mi: her parça sığar ve bütün boş hücreler dolar.
bool renoSolved(RenoPuzzle z, List<(int, int, bool)?> place) {
  final grid = [for (final b in z.blocked) b ? -2 : -1];
  for (var k = 0; k < z.pieces.length; k++) {
    final pl = place[k];
    if (pl == null) return false;
    if (!renoFits(z.cols, z.rows, grid, z.pieces[k], pl.$1, pl.$2, pl.$3)) return false;
    renoPut(z.cols, grid, z.pieces[k], pl.$1, pl.$2, pl.$3, k);
  }
  return !grid.contains(-1);
}

class RenovateKind extends SimKind {
  @override
  String get id => 'yenile';
  const RenovateKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final cols = 4 + math.min<int>(3, (d + 1) ~/ 3), rows = 4 + math.min<int>(3, d ~/ 3);
    final blocked = List<bool>.filled(cols * rows, false);
    // kapı önü (alt kenarda) ve 0-2 sütun
    final door = r.nextInt(cols);
    blocked[(rows - 1) * cols + door] = true;
    for (var k = 0; k < (d >= 4 ? 1 + r.nextInt(2) : 0); k++) {
      blocked[r.nextInt(rows - 1) * cols + r.nextInt(cols)] = true;
    }
    final grid = [for (final b in blocked) b ? -2 : -1];
    final pieces = <RenoPiece>[];
    final sol = <(int, int, bool)>[];
    final big = [for (var t = 1; t < kFurniture.length; t++) t];
    for (var i = 0; i < grid.length; i++) {
      if (grid[i] != -1) continue;
      final x = i % cols, y = i ~/ cols;
      r.shuffle(big);
      var placed = false;
      for (final t in big) {
        final p = RenoPiece(t, kFurniture[t].$1, kFurniture[t].$2);
        final rot = r.chance(0.5);
        for (final rr in [rot, !rot]) {
          if (renoFits(cols, rows, grid, p, x, y, rr)) {
            renoPut(cols, grid, p, x, y, rr, pieces.length);
            pieces.add(p);
            sol.add((x, y, rr));
            placed = true;
            break;
          }
        }
        if (placed) break;
      }
      if (!placed) {
        const p = RenoPiece(0, 1, 1);
        renoPut(cols, grid, p, x, y, false, pieces.length);
        pieces.add(p);
        sol.add((x, y, false));
      }
    }
    final singles = pieces.where((p) => p.type == 0).length;
    if (pieces.length < 3 || singles * 3 > pieces.length) return null;
    // Tepside sıra karışık; çözüm aynı sırayla tutulur.
    final order = [for (var k = 0; k < pieces.length; k++) k];
    r.shuffle(order);
    final z = RenoPuzzle(cols, rows, blocked, [for (final k in order) pieces[k]], [for (final k in order) sol[k]]);
    return renoSolved(z, z.solution) ? z : null;
  }

  @override
  bool check(SPuzzle p) => p is RenoPuzzle && p.pieces.length == p.solution.length && renoSolved(p, p.solution);

  @override
  Widget build(SimPlay play) => _RenoView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('rooms', 'Yenilenen oda', 'Rooms renovated', scale: 10),
        const GameStat('placed', 'Yerleşen mobilya', 'Furniture placed', scale: 50),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('rooms', 'rooms', [3, 15, 50]),
      ];
}

class _RenoView extends StatefulWidget {
  final SimPlay play;
  const _RenoView({required this.play});

  @override
  State<_RenoView> createState() => _RenoViewState();
}

class _RenoViewState extends State<_RenoView> {
  late final RenoPuzzle z = widget.play.puzzle as RenoPuzzle;
  late final List<(int, int, bool)?> place = List<(int, int, bool)?>.filled(z.pieces.length, null);
  int sel = 0;
  bool rot = false;
  int moves = 0;
  int hints = 0;
  bool ended = false;
  bool calm = false;
  int wall = 0;
  int floor = 0;
  final Stopwatch watch = Stopwatch()..start();

  SimPlay get play => widget.play;
  String get lang => play.lang;

  int get budget => SimPrefs.renown(play.gameId);

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    SimPrefs.init().then((_) {
      if (!mounted) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        wall = SimPrefs.getInt('reno_wall_${play.gameId}');
        floor = SimPrefs.getInt('reno_floor_${play.gameId}');
      });
    });
  }

  List<int> _grid({int skip = -1}) {
    final g = [for (final b in z.blocked) b ? -2 : -1];
    for (var k = 0; k < z.pieces.length; k++) {
      final pl = place[k];
      if (pl == null || k == skip) continue;
      renoPut(z.cols, g, z.pieces[k], pl.$1, pl.$2, pl.$3, k);
    }
    return g;
  }

  void _tapCell(Offset p, Size size) {
    if (ended) return;
    final cw = size.width / z.cols, ch = size.height / z.rows;
    final x = (p.dx / cw).floor(), y = (p.dy / ch).floor();
    if (x < 0 || y < 0 || x >= z.cols || y >= z.rows) return;
    final g = _grid();
    final at = g[y * z.cols + x];
    if (at >= 0) {
      // yerleşmiş mobilyayı tepsiye geri al
      setState(() {
        place[at] = null;
        sel = at;
        play.sfx(Sfx.tap);
      });
      return;
    }
    if (sel < 0 || sel >= z.pieces.length || place[sel] != null) {
      play.sfx(Sfx.error);
      return;
    }
    if (renoFits(z.cols, z.rows, g, z.pieces[sel], x, y, rot)) {
      setState(() {
        place[sel] = (x, y, rot);
        moves++;
        play.sfx(Sfx.place);
        final nx = [for (var k = 0; k < z.pieces.length; k++) if (place[k] == null) k];
        sel = nx.isEmpty ? -1 : nx.first;
      });
      if (renoSolved(z, place)) _finish();
    } else {
      play.sfx(Sfx.error);
    }
  }

  void _hint() {
    if (ended) return;
    // Yanlış yerdeki ilk parçayı kaldırır ve doğru yerine koyar.
    setState(() {
      for (var k = 0; k < z.pieces.length; k++) {
        if (place[k] != z.solution[k]) {
          final s = z.solution[k];
          final w = s.$3 ? z.pieces[k].h : z.pieces[k].w, h = s.$3 ? z.pieces[k].w : z.pieces[k].h;
          for (var o = 0; o < z.pieces.length; o++) {
            final pl = place[o];
            if (pl == null || o == k) continue;
            final ow = pl.$3 ? z.pieces[o].h : z.pieces[o].w, oh = pl.$3 ? z.pieces[o].w : z.pieces[o].h;
            final hit = pl.$1 < s.$1 + w && s.$1 < pl.$1 + ow && pl.$2 < s.$2 + h && s.$2 < pl.$2 + oh;
            if (hit) place[o] = null;
          }
          place[k] = s;
          hints++;
          play.sfx(Sfx.unlock);
          break;
        }
      }
    });
    if (renoSolved(z, place)) _finish();
  }

  void _finish() {
    if (ended) return;
    ended = true;
    play.sfx(Sfx.win);
    final stars = calm ? 3 : (hints == 0 && moves <= z.pieces.length + 2 ? 3 : (hints <= 1 ? 2 : 1));
    play.win(stars: stars, calm: calm, score: 100 * z.pieces.length - 30 * hints, seconds: watch.elapsed.inSeconds,
        stats: {'rooms': 1, 'placed': z.pieces.length});
  }

  void _style(bool isWall) {
    // Her yeni renk 3 ün (yıldız) ister; ün harcanmaz, eşik olarak kullanılır.
    final unlocked = 1 + budget ~/ 3;
    setState(() {
      if (isWall) {
        wall = (wall + 1) % math.min<int>(kWallColors.length, unlocked);
        SimPrefs.setInt('reno_wall_${play.gameId}', wall);
      } else {
        floor = (floor + 1) % math.min<int>(kFloorColors.length, unlocked);
        SimPrefs.setInt('reno_floor_${play.gameId}', floor);
      }
      play.sfx(Sfx.tap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = place.where((p) => p != null).length;
    final scene = Padding(
      padding: const EdgeInsets.all(6),
      child: AspectRatio(
        aspectRatio: z.cols / z.rows,
        child: SceneCanvas(semantics: st(lang, 'rRoom'), paint: _paint, onTap: _tapCell),
      ),
    );
    return SimFrame(
      play: play,
      moneyIcon: Icons.star,
      money: '$budget',
      sub: '${st(lang, 'rRoom')} ${z.cols}×${z.rows} · ${st(lang, 'rMoves')} $moves',
      goalText: '${st(lang, 'rPlace')} $done/${z.pieces.length}',
      progress: done / z.pieces.length,
      season: 0,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      sceneFlex: 6,
      panelFlex: 3,
      scene: Center(child: scene),
      actions: [
        IconButton(tooltip: st(lang, 'rRotate'), onPressed: () => setState(() => rot = !rot), icon: const Icon(Icons.rotate_90_degrees_ccw)),
        IconButton(tooltip: st(lang, 'rHint'), onPressed: _hint, icon: const Icon(Icons.lightbulb_outline)),
      ],
      panel: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(children: [
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var k = 0; k < z.pieces.length; k++)
                if (place[k] == null)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: SChip(
                      selected: sel == k,
                      onTap: () => setState(() => sel = k),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(kFurniture[z.pieces[k].type].$3, style: const TextStyle(fontSize: 22)),
                        Text(
                            '${rot && sel == k ? z.pieces[k].h : z.pieces[k].w}×${rot && sel == k ? z.pieces[k].w : z.pieces[k].h}',
                            style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
            ]),
          ),
          Row(children: [
            Expanded(child: SNote(st(lang, 'rWall'), icon: Icons.format_paint, onTap: () => _style(true))),
            const SizedBox(width: 6),
            Expanded(child: SNote(st(lang, 'rFloor'), icon: Icons.grid_on, onTap: () => _style(false))),
          ]),
        ]),
      ),
    );
  }

  void _paint(Canvas c, Size size) {
    final cw = size.width / z.cols, ch = size.height / z.rows;
    c.drawRect(Offset.zero & size, fill(kFloorColors[floor % kFloorColors.length]));
    for (var y = 0; y < z.rows; y++) {
      for (var x = 0; x < z.cols; x++) {
        final r = Rect.fromLTWH(x * cw, y * ch, cw, ch);
        if ((x + y).isEven) c.drawRect(r, fill(const Color(0x14000000)));
        if (z.blocked[y * z.cols + x]) {
          c.drawRect(r.deflate(3), fill(const Color(0x55FFFFFF)));
          drawLabel(c, y == z.rows - 1 ? '🚪' : '🏛️', r.center, math.min(cw, ch) * 0.5, Colors.black);
        }
      }
    }
    c.drawRect(Offset.zero & size, stroke(kWallColors[wall % kWallColors.length], 8));
    final cols = [const Color(0xFFE9C46A), const Color(0xFF8AB17D), const Color(0xFFE76F51), const Color(0xFF6D9DC5), const Color(0xFFB392AC)];
    for (var k = 0; k < z.pieces.length; k++) {
      final pl = place[k];
      if (pl == null) continue;
      final p = z.pieces[k];
      final w = pl.$3 ? p.h : p.w, h = pl.$3 ? p.w : p.h;
      final r = Rect.fromLTWH(pl.$1 * cw, pl.$2 * ch, w * cw, h * ch).deflate(3);
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), fill(cols[p.type % cols.length]));
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), stroke(const Color(0x66000000), 1.5));
      drawLabel(c, kFurniture[p.type].$3, r.center, math.min(r.width, r.height) * 0.55, Colors.black);
    }
  }
}
