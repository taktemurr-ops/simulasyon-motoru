import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';
import 'idle.dart' show numOf, intOf, intsOf;

// =================================================================== Kasaba Kur (basit şehir kurma)

/// Yapılar: 0 ev, 1 dükkân, 2 park, 3 atölye, 4 çeşme. -1 boş, -2 dere.
const List<double> kTownBase = [15, 40, 30, 80, 150];
const List<String> kTownKeys = ['house', 'shop', 'park', 'workshop', 'fountain'];
const List<IconData> kTownIcons = [Icons.house_rounded, Icons.storefront_rounded, Icons.park_rounded, Icons.handyman_rounded, Icons.water_drop_rounded];
const List<Color> kTownColors = [Color(0xFFE07A5F), Color(0xFF3E6FB0), Color(0xFF4F9A6E), Color(0xFF8D6E63), Color(0xFF3A8D8C)];
const List<double> kTownSeason = [1.0, 1.05, 1.0, 0.85];

class TownPuzzle extends SPuzzle {
  final int n;
  final Set<int> water;
  final int season0;
  final double costMul;
  final int goalPop;
  final int par;
  final int limit;
  const TownPuzzle(this.n, this.water, this.season0, this.costMul, this.goalPop, this.par, this.limit);

  TownPuzzle withGoal(int g, int p) => TownPuzzle(n, water, season0, costMul, g, p, limit);
}

class TownSim {
  final TownPuzzle z;
  late List<int> g;
  final List<int> built = List<int>.filled(5, 0);
  double coins = 40;
  double t = 0;
  int peak = 0;
  int points = 0;
  int prestiges = 0;
  int placed = 0;
  double extra = 1;
  late List<List<int>> _n8;
  late List<List<int>> _r2;

  TownSim(this.z) {
    g = [for (var i = 0; i < z.n * z.n; i++) z.water.contains(i) ? -2 : -1];
    final n = z.n;
    _n8 = [
      for (var i = 0; i < n * n; i++)
        [
          for (var dy = -1; dy <= 1; dy++)
            for (var dx = -1; dx <= 1; dx++)
              if ((dx != 0 || dy != 0) && i % n + dx >= 0 && i % n + dx < n && i ~/ n + dy >= 0 && i ~/ n + dy < n) i + dy * n + dx,
        ],
    ];
    _r2 = [
      for (var i = 0; i < n * n; i++)
        [
          for (var dy = -2; dy <= 2; dy++)
            for (var dx = -2; dx <= 2; dx++)
              if ((dx != 0 || dy != 0) && i % n + dx >= 0 && i % n + dx < n && i ~/ n + dy >= 0 && i ~/ n + dy < n) i + dy * n + dx,
        ],
    ];
  }

  int get season => (z.season0 + t ~/ kSeasonLen) % 4;

  double cost(int type) => kTownBase[type] * z.costMul * math.pow(1.22, built[type]).toDouble();

  double happy(int i) {
    var parks = 0, works = 0;
    for (final j in _n8[i]) {
      if (g[j] == 2) parks++;
      if (g[j] == 3) works++;
    }
    var f = 0;
    for (final j in _r2[i]) {
      if (g[j] == 4) f++;
    }
    final parkBonus = season == 1 ? 0.24 : 0.2;
    return clampD(1 + parkBonus * parks + 0.15 * f - 0.25 * works, 0.3, 2.0);
  }

  double get pop {
    var p = 0.0;
    for (var i = 0; i < g.length; i++) {
      if (g[i] == 0) p += 4 * happy(i);
    }
    return p;
  }

  double get avgHappy {
    var s = 0.0, k = 0;
    for (var i = 0; i < g.length; i++) {
      if (g[i] == 0) {
        s += happy(i);
        k++;
      }
    }
    return k == 0 ? 1 : s / k;
  }

  double get income {
    var v = 0.08 * pop;
    for (var i = 0; i < g.length; i++) {
      if (g[i] == 1) {
        var houses = 0, f = 0;
        for (final j in _n8[i]) {
          if (g[j] == 0) houses++;
        }
        for (final j in _r2[i]) {
          if (g[j] == 4) f++;
        }
        v += 0.6 * houses * (1 + 0.1 * f);
      } else if (g[i] == 3) {
        v += 2.5;
      }
    }
    return v * kTownSeason[season] * (1 + 0.4 * points) * extra;
  }

  bool place(int i, int type) {
    if (g[i] != -1 || cost(type) > coins) return false;
    coins -= cost(type);
    g[i] = type;
    built[type]++;
    placed++;
    final p = pop.floor();
    if (p > peak) peak = p;
    return true;
  }

  double _value() => income + 0.15 * pop;

  /// Botun sıradaki yapı türü: 4 ev, 1 dükkân, 1 park; arada atölye ve çeşme.
  int nextType() {
    final h = built[0], s = built[1], p = built[2], w = built[3], f = built[4];
    if (h < 2) return 0;
    if (s * 4 < h) return 1;
    if (p * 5 < h) return 2;
    if (w * 8 < h) return 3;
    if (f * 12 < h && h >= 8) return 4;
    return 0;
  }

  int bestCell(int type) {
    var best = -1;
    var bv = -1e18;
    final base = _value();
    for (var i = 0; i < g.length; i++) {
      if (g[i] != -1) continue;
      g[i] = type;
      final v = _value() - base;
      g[i] = -1;
      if (v > bv) {
        bv = v;
        best = i;
      }
    }
    return best;
  }

  int get emptyCells => g.where((x) => x == -1).length;

  void botSecond() {
    coins += 2 * (1 + 0.05 * income);
    for (var k = 0; k < 3; k++) {
      if (emptyCells == 0) break;
      final type = nextType();
      if (cost(type) > coins) break;
      final cell = bestCell(type);
      if (cell < 0 || !place(cell, type)) break;
    }
    coins += income;
    t += 1;
  }

  void step(double dt) {
    coins += income * dt;
    t += dt;
    final p = pop.floor();
    if (p > peak) peak = p;
  }

  int get prestigeGain => pop >= 120 ? pop ~/ 60 : 0;

  void prestige() {
    final gn = prestigeGain;
    if (gn <= 0) return;
    points += gn;
    prestiges++;
    g = [for (var i = 0; i < z.n * z.n; i++) z.water.contains(i) ? -2 : -1];
    for (var k = 0; k < 5; k++) {
      built[k] = 0;
    }
    coins = 40;
  }
}

int townReach(TownPuzzle z, int limit) {
  final s = TownSim(z);
  for (var i = 1; i <= limit; i++) {
    s.botSecond();
    if (s.peak >= z.goalPop) return i;
  }
  return -1;
}

class TownKind extends SimKind {
  @override
  String get id => 'kasaba';
  const TownKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final n = 6 + d ~/ 4;
    final water = <int>{};
    if (d >= 3) {
      var x = r.nextInt(n);
      for (var y = 0; y < n; y++) {
        water.add(y * n + x);
        if (r.chance(0.35)) x = clampI(x + (r.chance(0.5) ? 1 : -1), 0, n - 1);
      }
    }
    final seconds = 120 + 40 * d;
    final base = TownPuzzle(n, water, r.nextInt(4), (1 + 0.08 * d) * (0.9 + 0.2 * r.nextDouble()), 99999, seconds, seconds + seconds ~/ 4);
    final s = TownSim(base);
    for (var i = 0; i < seconds; i++) {
      s.botSecond();
    }
    final goal = s.peak;
    if (goal < 16) return null;
    final z = base.withGoal(goal, seconds);
    final reach = townReach(z, z.limit);
    if (reach < 0) return null;
    return z.withGoal(goal, reach);
  }

  @override
  bool check(SPuzzle p) => p is TownPuzzle && p.goalPop >= 16 && p.n >= 6 && townReach(p, p.limit) == p.par;

  @override
  Widget build(SimPlay play) => _TownView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('buildings', 'Kurulan yapı', 'Buildings placed', scale: 20),
        const GameStat('prestige', 'Yeni kasaba', 'New towns', scale: 2),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('build', 'buildings', [10, 40, 120]),
      ];
}

class _TownView extends StatefulWidget {
  final SimPlay play;
  const _TownView({required this.play});

  @override
  State<_TownView> createState() => _TownViewState();
}

class _TownViewState extends State<_TownView> with SimClock<_TownView> {
  late final TownPuzzle z = widget.play.puzzle as TownPuzzle;
  late final TownSim m = TownSim(z);
  bool calm = false;
  int pick = 0;
  double saveIn = 5;
  String note = '';
  double noteUntil = -1;
  double armUntil = -1;
  int flash = -1;

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    m.extra = SimPrefs.renownMul(play.gameId);
    final r = play.restored;
    if (r.isNotEmpty) {
      final gg = intsOf(r['g'], z.n * z.n);
      for (var i = 0; i < gg.length; i++) {
        m.g[i] = z.water.contains(i) ? -2 : (gg[i] >= 0 && gg[i] <= 4 ? gg[i] : -1);
      }
      final b = intsOf(r['bt'], 5);
      for (var k = 0; k < 5; k++) {
        m.built[k] = b[k];
      }
      m.coins = numOf(r['coins'], 40);
      m.t = numOf(r['t'], 0);
      m.peak = intOf(r['pk'], 0);
      m.points = intOf(r['pts'], 0);
      m.prestiges = intOf(r['pre'], 0);
      m.placed = intOf(r['pl'], 0);
      seconds = intOf(r['sec'], 0);
      final away = play.awaySeconds();
      if (away >= 20) {
        final gain = m.income * away * 0.5;
        m.coins += gain;
        note = st(lang, 'offline').replaceAll('{0}', fmtNum(gain));
        noteUntil = m.t + 8;
      }
    }
    SimPrefs.init().then((_) {
      if (!mounted) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        m.extra = SimPrefs.renownMul(play.gameId);
      });
    });
    startLoop(250, _tick);
  }

  void _save() => play.save({
        'g': m.g,
        'bt': m.built,
        'coins': m.coins,
        't': m.t,
        'pk': m.peak,
        'pts': m.points,
        'pre': m.prestiges,
        'pl': m.placed,
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
    if (m.peak >= z.goalPop) _win();
  }

  void _win() {
    if (ended) return;
    ended = true;
    stopLoop();
    _save();
    play.sfx(Sfx.win);
    play.win(stars: starsByTime(seconds, z.par), calm: calm, score: m.peak * 10, seconds: seconds, stats: {
      'buildings': m.placed,
      'prestige': m.prestiges,
    });
  }

  void _tapCell(int i) {
    if (ended) return;
    setState(() {
      if (m.g[i] != -1) {
        flash = i;
        play.sfx(Sfx.tap);
        return;
      }
      if (m.place(i, pick)) {
        flash = i;
        play.sfx(Sfx.place);
        if (m.peak >= z.goalPop) _win();
      } else {
        play.sfx(Sfx.error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final season = m.season;
    final gain = m.prestigeGain;
    final board = LayoutBuilder(builder: (context, box) {
      final cs = math.min(box.maxWidth, box.maxHeight) / z.n;
      return Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (e) {
            final x = (e.localPosition.dx / cs).floor(), y = (e.localPosition.dy / cs).floor();
            if (x >= 0 && x < z.n && y >= 0 && y < z.n) _tapCell(y * z.n + x);
          },
          child: CustomPaint(size: Size(cs * z.n, cs * z.n), painter: _TownPainter(m, cs, season, flash)),
        ),
      );
    });
    return SimFrame(
      play: play,
      moneyIcon: Icons.monetization_on,
      money: fmtNum(m.coins),
      sub: '+${fmtNum(m.income)}${st(lang, 'perSec')}',
      goalText: st(lang, 'goalPop').replaceAll('{0}', '${m.pop.floor()}/${z.goalPop}'),
      progress: m.peak / z.goalPop,
      season: season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      banner: noteUntil > m.t && note.isNotEmpty ? SNote(note, icon: Icons.nightlight_round) : null,
      sceneFlex: 6,
      panelFlex: 3,
      scene: Container(
        decoration: BoxDecoration(color: kSeasonLooks[season].ground.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.all(6),
        child: board,
      ),
      panel: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          SBadge(Icons.groups, '${st(lang, 'population')} ${m.pop.floor()}'),
          SBadge(Icons.sentiment_satisfied_alt, '${st(lang, 'happiness')} ${(m.avgHappy * 100).round()}%'),
          if (m.points > 0) SBadge(Icons.auto_awesome, '×${(1 + 0.4 * m.points).toStringAsFixed(1)}'),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var k = 0; k < 5; k++)
            SChip(
              selected: pick == k,
              onTap: () => setState(() => pick = k),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(kTownIcons[k], size: 18, color: kTownColors[k]),
                const SizedBox(width: 4),
                Text('${st(lang, kTownKeys[k])} ${fmtNum(m.cost(k))}',
                    style: TextStyle(fontSize: 13, color: m.cost(k) <= m.coins ? null : Colors.black38)),
              ]),
            ),
        ]),
        const SizedBox(height: 6),
        Text(st(lang, 'townHelp${pick + 1}'), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SChip(
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
                      play.sfx(Sfx.unlock);
                    })
                : null,
            child: Text(gain > 0 ? (armUntil > m.t ? st(lang, 'sure') : '${st(lang, 'newTown')} +$gain') : '${st(lang, 'newTown')} 120+',
                style: const TextStyle(fontSize: 13)),
          ),
        ),
      ]),
    );
  }
}

class _TownPainter extends CustomPainter {
  final TownSim m;
  final double cs;
  final int season;
  final int flash;
  _TownPainter(this.m, this.cs, this.season, this.flash);

  @override
  void paint(Canvas c, Size size) {
    final n = m.z.n;
    final look = kSeasonLooks[season];
    for (var i = 0; i < n * n; i++) {
      final r = Rect.fromLTWH((i % n) * cs, (i ~/ n) * cs, cs, cs);
      final v = m.g[i];
      if (v == -2) {
        c.drawRect(r, fill(season == 3 ? const Color(0xFFCFE3F0) : const Color(0xFF6FB3D9)));
        c.drawLine(r.centerLeft + Offset(4, -3), r.centerRight + Offset(-4, -3), stroke(Colors.white.withValues(alpha: 0.6), 1.5));
        continue;
      }
      c.drawRect(r.deflate(1), fill(Color.lerp(look.ground, Colors.white, season == 3 ? 0.5 : 0.15)!));
      if (v < 0) continue;
      final inner = r.deflate(cs * 0.12);
      switch (v) {
        case 0:
          final h = m.happy(i);
          c.drawRect(Rect.fromLTWH(inner.left, inner.top + inner.height * 0.35, inner.width, inner.height * 0.65), fill(kTownColors[0]));
          c.drawPath(
              Path()
                ..moveTo(inner.left - 2, inner.top + inner.height * 0.38)
                ..lineTo(inner.center.dx, inner.top)
                ..lineTo(inner.right + 2, inner.top + inner.height * 0.38)
                ..close(),
              fill(season == 3 ? Colors.white : const Color(0xFF7A2E24)));
          c.drawRect(Rect.fromCenter(center: Offset(inner.center.dx, inner.bottom - inner.height * 0.15), width: inner.width * 0.22, height: inner.height * 0.3),
              fill(const Color(0xFF5B3A22)));
          c.drawCircle(Offset(inner.right - 4, inner.top + 4), 3, fill(h >= 1.2 ? const Color(0xFF4F9A6E) : (h < 0.9 ? const Color(0xFFC8553D) : const Color(0xFFD9A441))));
        case 1:
          c.drawRect(inner, fill(kTownColors[1]));
          for (var k = 0; k < 4; k++) {
            c.drawRect(Rect.fromLTWH(inner.left + k * inner.width / 4, inner.top, inner.width / 8, inner.height * 0.28), fill(Colors.white));
          }
          c.drawRect(Rect.fromLTWH(inner.left + inner.width * 0.2, inner.top + inner.height * 0.5, inner.width * 0.6, inner.height * 0.3),
              fill(const Color(0xFFBFE3F2)));
        case 2:
          final leaf = season == 2 ? const Color(0xFFD9772F) : (season == 3 ? Colors.white : kTownColors[2]);
          c.drawCircle(inner.center + Offset(-inner.width * 0.2, 0), inner.width * 0.25, fill(leaf));
          c.drawCircle(inner.center + Offset(inner.width * 0.2, -inner.width * 0.1), inner.width * 0.22, fill(leaf));
          c.drawRect(Rect.fromCenter(center: inner.center + Offset(0, inner.height * 0.3), width: inner.width * 0.5, height: 3), fill(const Color(0xFF7A4E2D)));
        case 3:
          c.drawRect(inner, fill(kTownColors[3]));
          c.drawRect(Rect.fromLTWH(inner.right - inner.width * 0.25, inner.top - 4, inner.width * 0.15, inner.height * 0.4), fill(const Color(0xFF5B4636)));
          final smoke = (DateTime.now().millisecondsSinceEpoch % 2000) / 2000;
          c.drawCircle(Offset(inner.right - inner.width * 0.18, inner.top - 6 - smoke * 8), 3 + smoke * 2, fill(Colors.grey.withValues(alpha: 0.5)));
        default:
          c.drawCircle(inner.center, inner.width * 0.4, fill(const Color(0xFFB0B0A8)));
          c.drawCircle(inner.center, inner.width * 0.3, fill(kTownColors[4]));
          c.drawCircle(inner.center, inner.width * 0.08, fill(Colors.white));
      }
      if (i == flash) c.drawRect(r.deflate(1), stroke(const Color(0xFFFFD166), 2.5));
    }
  }

  @override
  bool shouldRepaint(covariant _TownPainter old) => true;
}
