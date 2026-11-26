import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';
import 'idle.dart' show numOf, intOf, intsOf;

// =================================================================== Çömlek Atölyesi (birleştir-geliştir)

class MergePuzzle extends SPuzzle {
  final int cols;
  final int rows;
  final double c0;
  final double growth;
  final double spawnSec;
  final int season0;
  final int goalTier;
  final int par;
  final int limit;
  const MergePuzzle(this.cols, this.rows, this.c0, this.growth, this.spawnSec, this.season0, this.goalTier, this.par, this.limit);

  int get cells => cols * rows;

  MergePuzzle withGoal(int tier, int par) => MergePuzzle(cols, rows, c0, growth, spawnSec, season0, tier, par, limit);
}

const List<double> kMergeSeason = [1.0, 1.1, 1.0, 0.9];

class MergeSim {
  final MergePuzzle z;
  late List<int> grid;
  double coins = 10;
  int bought = 0;
  double spawnT = 0;
  double t = 0;
  int maxTier = 1;
  int levelMax = 1;
  int glaze = 0;
  int merges = 0;
  int prestiges = 0;
  double extra = 1;

  MergeSim(this.z) {
    grid = List<int>.filled(z.cells, 0);
  }

  int get season => (z.season0 + t ~/ kSeasonLen) % 4;

  static double rateOf(int tier) => 0.4 * math.pow(3, tier - 1).toDouble();

  double get income {
    var v = 0.0;
    for (final x in grid) {
      if (x > 0) v += rateOf(x);
    }
    return v * (1 + 0.5 * glaze) * kMergeSeason[season] * extra;
  }

  double get cost => z.c0 * math.pow(z.growth, bought).toDouble();

  double get spawnEvery => z.spawnSec * (season == 3 ? 0.8 : 1.0);

  int freeCell() => grid.indexOf(0);

  bool buy() {
    final i = freeCell();
    if (i < 0 || cost > coins) return false;
    coins -= cost;
    bought++;
    grid[i] = 1;
    return true;
  }

  bool merge(int a, int b) {
    if (a == b || grid[a] == 0 || grid[a] != grid[b]) return false;
    final t2 = grid[a] + 1;
    grid[b] = t2;
    grid[a] = 0;
    merges++;
    if (t2 > maxTier) maxTier = t2;
    if (t2 > levelMax) levelMax = t2;
    return true;
  }

  bool move(int a, int b) {
    if (grid[a] == 0 || grid[b] != 0) return false;
    grid[b] = grid[a];
    grid[a] = 0;
    return true;
  }

  /// En küçük kademeden bir çift birleştirir (bot ve otomatik yardımcı).
  bool mergeOne() {
    final seen = <int, int>{};
    var bestA = -1, bestB = -1, bestT = 1 << 20;
    for (var i = 0; i < grid.length; i++) {
      final x = grid[i];
      if (x == 0) continue;
      final j = seen[x];
      if (j != null && x < bestT) {
        bestA = j;
        bestB = i;
        bestT = x;
      } else {
        seen[x] = i;
      }
    }
    return bestA >= 0 && merge(bestA, bestB);
  }

  void step(double dt) {
    final v = income * dt;
    coins += v;
    spawnT += dt;
    if (spawnT >= spawnEvery) {
      spawnT = 0;
      final i = freeCell();
      if (i >= 0) grid[i] = 1;
    }
    t += dt;
  }

  int get glazeGain => maxTier >= 6 ? maxTier - 5 : 0;

  void prestige() {
    final g = glazeGain;
    if (g <= 0) return;
    glaze += g;
    prestiges++;
    grid = List<int>.filled(z.cells, 0);
    coins = 10;
    bought = 0;
    maxTier = 1;
  }

  void botSecond() {
    coins += 2 * (1 + 0.05 * income);
    if (t.round() % 2 == 0) mergeOne();
    for (var g = 0; g < 50 && buy(); g++) {}
    step(1);
  }
}

int mergeReach(MergePuzzle z, int limit) {
  final s = MergeSim(z);
  for (var i = 1; i <= limit; i++) {
    s.botSecond();
    if (s.levelMax >= z.goalTier) return i;
  }
  return -1;
}

/// Liman Pazarı modu: sipariş panosundaki malların teslim ödülü.
int limanReward(int tier) => (6 * math.pow(2.6, tier - 1)).round();

/// Liman Pazarı modu: botun siparişleri sırayla teslim ederek bitirdiği saniye (-1: yetişmedi).
int limanReach(MergePuzzle z, List<int> orders) {
  final s = MergeSim(z);
  var k = 0;
  for (var i = 1; i <= z.limit; i++) {
    s.botSecond();
    while (k < orders.length) {
      final j = s.grid.indexOf(orders[k]);
      if (j < 0) break;
      s.grid[j] = 0;
      s.coins += limanReward(orders[k]);
      k++;
    }
    if (k >= orders.length) return i;
  }
  return -1;
}

/// Liman Pazarı siparişleri: bölümden belirlenimci üretilir, botun
/// yetişemediği son siparişler atılır (en az bir sipariş kalır).
List<int> limanOrders(MergePuzzle z) {
  final r = SeededRandom(mixSeed([z.cols, z.rows, z.goalTier, z.par, (z.c0 * 1000).round(), z.season0, 7717]));
  final n = 3 + z.goalTier ~/ 2;
  var orders = [for (var i = 0; i < n; i++) 2 + r.nextInt(math.max(1, z.goalTier - 2))];
  while (orders.length > 1 && limanReach(z, orders) < 0) {
    orders = orders.sublist(0, orders.length - 1);
  }
  return orders;
}

const int kLimanChapters = 6;

class MergeKind extends SimKind {
  @override
  String get id => 'birlestir';
  const MergeKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final seconds = 150 + 45 * d;
    final base = MergePuzzle(5, 4 + d ~/ 4, 3 * (0.9 + 0.2 * r.nextDouble()), 1.035 + 0.002 * d, 7.0 - 0.2 * d, r.nextInt(4), 99,
        seconds, seconds + seconds ~/ 4);
    final s = MergeSim(base);
    for (var i = 0; i < seconds; i++) {
      s.botSecond();
    }
    final goal = s.levelMax;
    if (goal < 4) return null;
    final z = base.withGoal(goal, seconds);
    final reach = mergeReach(z, z.limit);
    if (reach < 0) return null;
    return z.withGoal(goal, reach);
  }

  @override
  bool check(SPuzzle p) => p is MergePuzzle && p.goalTier >= 4 && p.cells >= 20 && mergeReach(p, p.limit) == p.par;

  @override
  Widget build(SimPlay play) => _MergeView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('merges', 'Birleştirme', 'Merges', scale: 50),
        const GameStat('prestige', 'Sırlama', 'Glazings', scale: 2),
        const GameStat('orders', 'Liman siparişi', 'Harbor orders', scale: 20),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('merges', 'merges', [30, 120, 400]),
      ];
}

Color potColor(int tier) => HSVColor.fromAHSV(1, (18 + tier * 37) % 360.0, 0.45 + 0.03 * (tier % 5), 0.78 + 0.02 * (tier % 6)).toColor();

/// Kademeye göre biçimi değişen çömlek.
void paintPot(Canvas c, Rect r, int tier, {bool selected = false, double t = 0}) {
  if (tier <= 0) return;
  final col = potColor(tier);
  final cx = r.center.dx;
  final w = r.width * (0.42 + 0.03 * (tier % 4));
  final h = r.height * (0.5 + 0.03 * math.min(8, tier));
  final bottom = r.bottom - r.height * 0.14;
  final neck = 0.25 + 0.12 * (tier % 3);
  final belly = 0.5 + 0.1 * ((tier + 1) % 3);
  final p = Path()
    ..moveTo(cx - w * neck, bottom - h)
    ..cubicTo(cx - w * 0.2, bottom - h * 0.75, cx - w, bottom - h * belly, cx - w * 0.55, bottom)
    ..lineTo(cx + w * 0.55, bottom)
    ..cubicTo(cx + w, bottom - h * belly, cx + w * 0.2, bottom - h * 0.75, cx + w * neck, bottom - h)
    ..close();
  if (selected) c.drawCircle(r.center, r.width * 0.48, fill(const Color(0x55FFD166)));
  c.drawPath(p, fill(col));
  c.drawPath(p, stroke(Color.lerp(col, Colors.black, 0.4)!, 1.5));
  // süsleme bantları
  for (var i = 0; i < math.min(4, (tier + 1) ~/ 2); i++) {
    final y = bottom - h * (0.3 + 0.15 * i);
    c.drawLine(Offset(cx - w * 0.55, y), Offset(cx + w * 0.55, y), stroke(Color.lerp(col, Colors.white, 0.55)!, 2));
  }
  if (tier >= 5) {
    for (var i = 0; i < 3; i++) {
      c.drawCircle(Offset(cx - w * 0.3 + i * w * 0.3, bottom - h * 0.55), 2.5, fill(const Color(0xFF2E5E8C)));
    }
  }
  if (tier >= 8) c.drawCircle(Offset(cx + w * 0.3, bottom - h * 0.85), 2 + math.sin(t * 4).abs() * 2, fill(Colors.white));
  drawLabel(c, '$tier', Offset(cx, bottom - h * 0.42), r.width * 0.2, Colors.white);
}

class _MergeView extends StatefulWidget {
  final SimPlay play;
  const _MergeView({required this.play});

  @override
  State<_MergeView> createState() => _MergeViewState();
}

class _MergeViewState extends State<_MergeView> with SimClock<_MergeView> {
  late final MergePuzzle z = widget.play.puzzle as MergePuzzle;
  late final MergeSim m = MergeSim(z);
  bool calm = false;
  int sel = -1;
  double saveIn = 5;
  String note = '';
  double noteUntil = -1;
  double armUntil = -1;

  /// Liman Pazarı modu (merge-2 + sipariş panosu + hikâye).
  bool harbor = false;
  late final List<int> orders = limanOrders(z);
  late final int harborPar = math.max(1, limanReach(z, orders));
  int delivered = 0;

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    m.extra = SimPrefs.renownMul(play.gameId);
    final r = play.restored;
    if (r.isNotEmpty) {
      m.grid = intsOf(r['g'], z.cells);
      m.coins = numOf(r['coins'], 10);
      m.bought = intOf(r['b'], 0);
      m.t = numOf(r['t'], 0);
      m.maxTier = intOf(r['mx'], 1);
      m.levelMax = intOf(r['lm'], 1);
      m.glaze = intOf(r['gl'], 0);
      m.merges = intOf(r['mg'], 0);
      m.prestiges = intOf(r['pr'], 0);
      delivered = intOf(r['lo'], 0);
      seconds = intOf(r['sec'], 0);
      final away = play.awaySeconds();
      if (away >= 20) {
        final g = m.income * away * 0.5;
        m.coins += g;
        note = st(lang, 'offline').replaceAll('{0}', fmtNum(g));
        noteUntil = m.t + 8;
      }
    }
    SimPrefs.init().then((_) {
      if (!mounted) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        harbor = SimPrefs.getBool('merge_harbor');
        m.extra = SimPrefs.renownMul(play.gameId);
      });
    });
    startLoop(250, _tick);
  }

  void _save() => play.save({
        'g': m.grid,
        'coins': m.coins,
        'b': m.bought,
        't': m.t,
        'mx': m.maxTier,
        'lm': m.levelMax,
        'gl': m.glaze,
        'mg': m.merges,
        'pr': m.prestiges,
        'lo': delivered,
        'sec': seconds,
      });

  void _tick(double dt) {
    if (ended) return;
    m.step(dt);
    saveIn -= dt;
    if (saveIn <= 0) {
      saveIn = 5;
      _save();
    }
    if (!harbor && m.levelMax >= z.goalTier) _win();
  }

  void _deliver() {
    if (ended || delivered >= orders.length) return;
    final j = m.grid.indexOf(orders[delivered]);
    setState(() {
      if (j < 0) {
        play.sfx(Sfx.error);
        return;
      }
      m.grid[j] = 0;
      if (sel == j) sel = -1;
      m.coins += limanReward(orders[delivered]);
      delivered++;
      play.sfx(Sfx.coin);
    });
    if (delivered >= orders.length) _win();
  }

  void _win() {
    if (ended) return;
    ended = true;
    stopLoop();
    _save();
    play.sfx(Sfx.win);
    play.win(
        stars: starsByTime(seconds, harbor ? harborPar : z.par),
        calm: calm,
        score: m.levelMax * 1000 + m.merges + delivered * 500,
        seconds: seconds,
        stats: {
          'merges': m.merges,
          'prestige': m.prestiges,
          if (harbor) 'orders': delivered,
        });
  }

  void _tapCell(int i) {
    if (ended) return;
    setState(() {
      if (sel < 0) {
        if (m.grid[i] > 0) {
          sel = i;
          play.sfx(Sfx.tap);
        }
        return;
      }
      if (sel == i) {
        sel = -1;
        return;
      }
      if (m.merge(sel, i)) {
        play.sfx(m.grid[i] >= 6 ? Sfx.combo : Sfx.clear);
        sel = -1;
        if (!harbor && m.levelMax >= z.goalTier) _win();
      } else if (m.move(sel, i)) {
        play.sfx(Sfx.place);
        sel = -1;
      } else {
        sel = m.grid[i] > 0 ? i : -1;
        play.sfx(Sfx.tap);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final season = m.season;
    final look = kSeasonLooks[season];
    final board = LayoutBuilder(builder: (context, box) {
      final cw = box.maxWidth / z.cols;
      final ch = box.maxHeight / z.rows;
      final cs = math.min(cw, ch);
      return Center(
        child: SizedBox(
          width: cs * z.cols,
          height: cs * z.rows,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) {
              final x = (e.localPosition.dx / cs).floor(), y = (e.localPosition.dy / cs).floor();
              if (x >= 0 && x < z.cols && y >= 0 && y < z.rows) _tapCell(y * z.cols + x);
            },
            child: CustomPaint(
              size: Size(cs * z.cols, cs * z.rows),
              painter: _MergePainter(m, sel, cs, look),
            ),
          ),
        ),
      );
    });
    final gain = m.glazeGain;
    final banner = harbor
        ? _harborBoard()
        : (noteUntil > m.t && note.isNotEmpty ? SNote(note, icon: Icons.nightlight_round) : null);
    return SimFrame(
      play: play,
      moneyIcon: Icons.savings,
      money: fmtNum(m.coins),
      sub: '+${fmtNum(m.income)}${st(lang, 'perSec')}',
      goalText: harbor
          ? '${st(lang, 'lOrders')} $delivered/${orders.length}'
          : st(lang, 'goalTier').replaceAll('{0}', '${z.goalTier}'),
      progress: harbor ? delivered / orders.length : m.levelMax / z.goalTier,
      season: season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      banner: banner,
      sceneFlex: 6,
      panelFlex: 2,
      scene: Container(
        decoration: BoxDecoration(color: const Color(0xFFF1E4D0), borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.all(6),
        child: board,
      ),
      panel: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Expanded(
              child: StudioButton(
                onPressed: m.freeCell() >= 0 && m.cost <= m.coins
                    ? () => setState(() {
                          if (m.buy()) play.sfx(Sfx.place);
                        })
                    : null,
                icon: Icons.add_circle_outline,
                fontSize: 15,
                label: '${st(lang, 'newPot')}  ${fmtNum(m.cost)}',
              ),
            ),
            const SizedBox(width: 8),
            SChip(
              onTap: () => setState(() {
                if (m.mergeOne()) {
                  play.sfx(Sfx.clear);
                  if (!harbor && m.levelMax >= z.goalTier) _win();
                }
              }),
              tooltip: st(lang, 'merge'),
              child: const Icon(Icons.merge_type),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            SChip(
              selected: harbor,
              tooltip: st(lang, 'lHarbor'),
              onTap: () => setState(() {
                harbor = !harbor;
                SimPrefs.setBool('merge_harbor', harbor);
                play.sfx(Sfx.tap);
              }),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.anchor, size: 16),
                const SizedBox(width: 4),
                Text(st(lang, 'lHarbor'), style: const TextStyle(fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 6),
            SBadge(Icons.local_fire_department, '${st(lang, 'kiln')} ${m.spawnEvery.toStringAsFixed(1)}s'),
            const SizedBox(width: 6),
            if (m.glaze > 0) SBadge(Icons.auto_awesome, '×${(1 + 0.5 * m.glaze).toStringAsFixed(1)}'),
            const Spacer(),
            SChip(
              selected: armUntil > m.t,
              tooltip: st(lang, 'prestigeInfo'),
              onTap: gain > 0
                  ? () => setState(() {
                        if (armUntil < m.t) {
                          armUntil = m.t + 3;
                          return;
                        }
                        armUntil = -1;
                        m.prestige();
                        sel = -1;
                        play.sfx(Sfx.unlock);
                      })
                  : null,
              child: Text(
                  gain > 0 ? (armUntil > m.t ? st(lang, 'sure') : '${st(lang, 'glaze')} +$gain') : '${st(lang, 'glaze')} 6+',
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
        ]),
      ),
    );
  }
}

extension on _MergeViewState {
  Widget _harborBoard() {
    if (delivered >= orders.length) return SNote(st(lang, 'lStory${kLimanChapters - 1}'), icon: Icons.celebration);
    final tier = orders[delivered];
    final have = m.grid.contains(tier);
    final chapter = (delivered * kLimanChapters) ~/ orders.length;
    return SNote(
      '${st(lang, 'lStory$chapter')} · ${st(lang, 'lWant').replaceAll('{0}', '$tier')} (+${fmtNum(limanReward(tier))})',
      icon: have ? Icons.sailing : Icons.anchor,
      onTap: _deliver,
    );
  }
}

class _MergePainter extends CustomPainter {
  final MergeSim m;
  final int sel;
  final double cs;
  final SeasonLook look;
  _MergePainter(this.m, this.sel, this.cs, this.look);

  @override
  void paint(Canvas c, Size size) {
    final z = m.z;
    for (var i = 0; i < z.cells; i++) {
      final x = i % z.cols, y = i ~/ z.cols;
      final r = Rect.fromLTWH(x * cs, y * cs, cs, cs).deflate(3);
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cs * 0.18)), fill(Color.lerp(const Color(0xFFE2CFB2), look.accent, 0.12)!));
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cs * 0.18)), stroke(const Color(0x33000000), 1));
      paintPot(c, r, m.grid[i], selected: i == sel, t: m.t);
    }
  }

  @override
  bool shouldRepaint(covariant _MergePainter old) => true;
}
