import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';
import 'idle.dart' show numOf, intOf;

// =================================================================== Karınca Kolonisi

class ColonyPuzzle extends SPuzzle {
  final int d;
  final int season0;
  final double foodMul;
  final double eggCost;
  final int goalPop;
  final int par;
  final int limit;
  const ColonyPuzzle(this.d, this.season0, this.foodMul, this.eggCost, this.goalPop, this.par, this.limit);

  ColonyPuzzle withGoal(int g, int p) => ColonyPuzzle(d, season0, foodMul, eggCost, g, p, limit);
}

/// İş bölümü önayarları: (toplayıcı, kazıcı, bakıcı).
const List<(double, double, double)> kColonyPlans = [
  (0.55, 0.2, 0.25),
  (0.75, 0.1, 0.15),
  (0.5, 0.35, 0.15),
  (0.4, 0.15, 0.45),
];
const List<String> kColonyPlanKeys = ['balanced', 'forage', 'dig', 'nurse'];
const List<IconData> kColonyPlanIcons = [Icons.tune, Icons.eco, Icons.construction, Icons.favorite_border];
const List<double> kColonyFood = [1.0, 1.3, 1.1, 0.35];

class ColonySim {
  final ColonyPuzzle z;
  double food = 25;
  int ants = 6;
  List<double> larvae = [];
  int cap = 20;
  double dig = 0;
  double layT = 0;
  double t = 0;
  int fungus = 0;
  double starve = 0;
  int peak = 6;
  int royal = 0;
  int flights = 0;
  int plan = 0;
  bool calm = false;
  double extra = 1;
  int hatched = 0;

  ColonySim(this.z);

  int get season => (z.season0 + t ~/ kSeasonLen) % 4;
  int get chambers => cap ~/ 4;
  double get fungusCost => 30 * math.pow(1.6, fungus).toDouble();

  (double, double, double) get split => kColonyPlans[plan];

  double get foodRate {
    final s = split;
    return ((ants * s.$1 * 0.22 * kColonyFood[season] + fungus * 0.6) * z.foodMul * (1 + 0.3 * royal) * extra) - ants * 0.03;
  }

  bool buyFungus() {
    if (food < fungusCost) return false;
    food -= fungusCost;
    fungus++;
    return true;
  }

  void step(double dt) {
    final s = split;
    final nu = ants * s.$3;
    food += ((ants * s.$1 * 0.22 * kColonyFood[season] + fungus * 0.6) * z.foodMul * (1 + 0.3 * royal) * extra) * dt;
    food -= ants * 0.03 * dt;
    dig += ants * s.$2 * 0.02 * dt;
    while (dig >= 1) {
      dig -= 1;
      cap += 4;
    }
    layT += dt * (1 + nu * 0.06) * (1 + 0.3 * royal);
    while (layT >= 5) {
      layT -= 5;
      if (ants + larvae.length < cap && food >= z.eggCost) {
        food -= z.eggCost;
        larvae.add(0);
      }
    }
    final next = <double>[];
    for (final p in larvae) {
      final q = p + dt * (1 + nu * 0.05) / 22;
      if (q >= 1) {
        ants++;
        hatched++;
      } else {
        next.add(q);
      }
    }
    larvae = next;
    if (food < 0) {
      food = 0;
      if (!calm) {
        starve += dt;
        if (starve >= 4 && ants > 3) {
          ants--;
          starve = 0;
        }
      }
    }
    if (ants > peak) peak = ants;
    t += dt;
  }

  int get flightGain => ants >= 40 ? ants ~/ 20 : 0;

  void flight() {
    final g = flightGain;
    if (g <= 0) return;
    royal += g;
    flights++;
    food = 25;
    ants = 6;
    larvae = [];
    cap = 20;
    dig = 0;
    fungus = 0;
  }

  void botSecond() {
    final free = cap - ants - larvae.length;
    if (free <= 3) {
      plan = 2;
    } else if (food < 12 || season == 2) {
      plan = 1;
    } else {
      plan = 0;
    }
    if (food > fungusCost * 1.5) buyFungus();
    step(1);
  }
}

int colonyReach(ColonyPuzzle z, int limit) {
  final s = ColonySim(z);
  for (var i = 1; i <= limit; i++) {
    s.botSecond();
    if (s.peak >= z.goalPop) return i;
  }
  return -1;
}

class ColonyKind extends SimKind {
  @override
  String get id => 'karinca';
  const ColonyKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final seconds = 150 + 45 * d;
    final base = ColonyPuzzle(d, r.nextInt(4), (1.0 - 0.03 * d) * (0.92 + 0.16 * r.nextDouble()), 2.0 + 0.15 * d, 9999, seconds,
        seconds + seconds ~/ 4);
    final s = ColonySim(base);
    for (var i = 0; i < seconds; i++) {
      s.botSecond();
    }
    final goal = s.peak;
    if (goal < 12) return null;
    final z = base.withGoal(goal, seconds);
    final reach = colonyReach(z, z.limit);
    if (reach < 0) return null;
    return z.withGoal(goal, reach);
  }

  @override
  bool check(SPuzzle p) => p is ColonyPuzzle && p.goalPop >= 12 && colonyReach(p, p.limit) == p.par;

  @override
  Widget build(SimPlay play) => _ColonyView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('hatched', 'Yumurtadan çıkan karınca', 'Ants hatched', scale: 50),
        const GameStat('prestige', 'Gelin uçuşu', 'Nuptial flights', scale: 2),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('hatched', 'hatched', [30, 150, 500]),
      ];
}

class _ColonyView extends StatefulWidget {
  final SimPlay play;
  const _ColonyView({required this.play});

  @override
  State<_ColonyView> createState() => _ColonyViewState();
}

class _ColonyViewState extends State<_ColonyView> with SimClock<_ColonyView> {
  late final ColonyPuzzle z = widget.play.puzzle as ColonyPuzzle;
  late final ColonySim c = ColonySim(z);
  bool calm = false;
  double saveIn = 5;
  String note = '';
  double noteUntil = -1;
  double armUntil = -1;
  final List<Offset> crumbs = [];
  double nextCrumb = 6;
  final math.Random _rnd = math.Random();

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    c.calm = calm;
    c.extra = SimPrefs.renownMul(play.gameId);
    final r = play.restored;
    if (r.isNotEmpty) {
      c.food = numOf(r['food'], 25);
      c.ants = intOf(r['ants'], 6);
      c.larvae = [for (final x in (r['lv'] is List ? r['lv'] as List : const [])) numOf(x, 0)];
      c.cap = intOf(r['cap'], 20);
      c.dig = numOf(r['dig'], 0);
      c.t = numOf(r['t'], 0);
      c.fungus = intOf(r['fu'], 0);
      c.peak = intOf(r['pk'], 6);
      c.royal = intOf(r['ro'], 0);
      c.flights = intOf(r['fl'], 0);
      c.plan = clampI(intOf(r['pl'], 0), 0, 3);
      c.hatched = intOf(r['ha'], 0);
      seconds = intOf(r['sec'], 0);
      final away = play.awaySeconds(cap: 3600);
      if (away >= 20) {
        final g = math.max(0.0, c.foodRate) * away * 0.5;
        c.food += g;
        note = st(lang, 'offline').replaceAll('{0}', '🍃 ${fmtNum(g)}');
        noteUntil = c.t + 8;
      }
    }
    SimPrefs.init().then((_) {
      if (!mounted) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        c.calm = calm;
        c.extra = SimPrefs.renownMul(play.gameId);
      });
    });
    startLoop(250, _tick);
  }

  void _save() => play.save({
        'food': c.food,
        'ants': c.ants,
        'lv': c.larvae,
        'cap': c.cap,
        'dig': c.dig,
        't': c.t,
        'fu': c.fungus,
        'pk': c.peak,
        'ro': c.royal,
        'fl': c.flights,
        'pl': c.plan,
        'ha': c.hatched,
        'sec': seconds,
      });

  void _tick(double dt) {
    if (ended) return;
    c.step(dt);
    if (c.t >= nextCrumb) {
      nextCrumb = c.t + 7;
      if (crumbs.length < 3) crumbs.add(Offset(0.1 + _rnd.nextDouble() * 0.8, 0.04 + _rnd.nextDouble() * 0.1));
    }
    saveIn -= dt;
    if (saveIn <= 0) {
      saveIn = 5;
      _save();
    }
    if (c.peak >= z.goalPop) _win();
  }

  void _win() {
    if (ended) return;
    ended = true;
    stopLoop();
    _save();
    play.sfx(Sfx.win);
    play.win(stars: starsByTime(seconds, z.par), calm: calm, score: c.peak * 10, seconds: seconds, stats: {
      'hatched': c.hatched,
      'prestige': c.flights,
    });
  }

  void _tap(Offset p, Size s) {
    if (ended) return;
    setState(() {
      for (var i = 0; i < crumbs.length; i++) {
        final q = Offset(crumbs[i].dx * s.width, crumbs[i].dy * s.height);
        if ((q - p).distance < 34) {
          crumbs.removeAt(i);
          final g = 6.0 + c.ants * 0.4;
          c.food += g;
          play.sfx(Sfx.coin);
          return;
        }
      }
      c.food += 0.5;
      play.sfx(Sfx.tap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final season = c.season;
    final gain = c.flightGain;
    final banner = noteUntil > c.t && note.isNotEmpty
        ? SNote(note, icon: Icons.nightlight_round)
        : (c.food <= 0 && !calm ? SNote(st(lang, 'hungry'), icon: Icons.warning_amber, color: const Color(0xFFFFD6CC)) : null);
    return SimFrame(
      play: play,
      moneyIcon: Icons.eco,
      money: fmtNum(c.food),
      sub: '${c.foodRate >= 0 ? '+' : ''}${fmtNum(c.foodRate)}${st(lang, 'perSec')}',
      goalText: st(lang, 'goalPop').replaceAll('{0}', '${c.peak}/${z.goalPop}'),
      progress: c.peak / z.goalPop,
      season: season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        c.calm = v;
        SimPrefs.calm = v;
      }),
      banner: banner,
      sceneFlex: 6,
      panelFlex: 3,
      scene: SceneCanvas(paint: (cv, s) => _paintColony(cv, s, c, season, crumbs), onTap: _tap, semantics: st(lang, 'tapScene')),
      panel: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          SBadge(Icons.bug_report, '${st(lang, 'ants')} ${c.ants}'),
          SBadge(Icons.bubble_chart, '${st(lang, 'larvae')} ${c.larvae.length}'),
          SBadge(Icons.home_work, '${st(lang, 'chambers')} ${c.chambers} · ${c.ants + c.larvae.length}/${c.cap}'),
          if (c.royal > 0) SBadge(Icons.auto_awesome, '×${(1 + 0.3 * c.royal).toStringAsFixed(1)}'),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < kColonyPlans.length; i++)
            SChip(
              selected: c.plan == i,
              onTap: () => setState(() {
                c.plan = i;
                play.sfx(Sfx.tap);
              }),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(kColonyPlanIcons[i], size: 18),
                const SizedBox(width: 4),
                Text(st(lang, kColonyPlanKeys[i]), style: const TextStyle(fontSize: 13)),
              ]),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: c.food >= c.fungusCost
                  ? () => setState(() {
                        if (c.buyFungus()) play.sfx(Sfx.unlock);
                      })
                  : null,
              icon: const Icon(Icons.grass),
              label: FittedBox(child: Text('${st(lang, 'fungus')} ${c.fungus + 1} · 🍃 ${fmtNum(c.fungusCost)}')),
            ),
          ),
          const SizedBox(width: 6),
          SChip(
            selected: armUntil > c.t,
            tooltip: st(lang, 'prestigeInfo'),
            onTap: gain > 0
                ? () => setState(() {
                      if (armUntil < c.t) {
                        armUntil = c.t + 3;
                        return;
                      }
                      armUntil = -1;
                      c.flight();
                      play.sfx(Sfx.unlock);
                    })
                : null,
            child: Text(gain > 0 ? (armUntil > c.t ? st(lang, 'sure') : '${st(lang, 'flight')} +$gain') : '${st(lang, 'flight')} 40+',
                style: const TextStyle(fontSize: 13)),
          ),
        ]),
      ]),
    );
  }
}

void _paintColony(Canvas cv, Size s, ColonySim c, int season, List<Offset> crumbs) {
  paintSky(cv, s, season, groundAt: 0.16);
  final top = s.height * 0.16;
  final soil = Rect.fromLTWH(0, top, s.width, s.height - top);
  cv.drawRect(
      soil,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA47148), Color(0xFF6F4A2F), Color(0xFF4B3221)],
        ).createShader(soil));
  // yüzey: çimen ya da kar
  final look = kSeasonLooks[season];
  for (var x = 0.0; x < s.width; x += 7) {
    cv.drawLine(Offset(x, top), Offset(x + 2, top - 6 - (x * 7) % 5), stroke(season == 3 ? Colors.white : look.ground, 2));
  }
  for (final q in crumbs) {
    final p = Offset(q.dx * s.width, q.dy * s.height);
    cv.drawCircle(p, 12, fill(const Color(0x33FFFFFF)));
    drawLabel(cv, '🍃', p, 18, Colors.black);
  }
  // odalar
  final n = math.max(1, c.chambers);
  final cols = 3;
  final rows = (n + cols - 1) ~/ cols;
  final cw = s.width / cols;
  final rh = (s.height - top - 14) / math.max(rows, 3);
  final centers = <Offset>[];
  for (var i = 0; i < math.min(n, 18); i++) {
    final x = cw * (i % cols) + cw / 2 + ((i * 37) % 21 - 10);
    final y = top + 24 + rh * (i ~/ cols) + ((i * 53) % 13);
    centers.add(Offset(x, y));
  }
  final tunnel = stroke(const Color(0xFF3A2618), 7);
  cv.drawLine(Offset(s.width / 2, top), centers.first, tunnel);
  for (var i = 1; i < centers.length; i++) {
    cv.drawLine(centers[i - 1], centers[i], tunnel);
  }
  for (var i = 0; i < centers.length; i++) {
    final r = Rect.fromCenter(center: centers[i], width: math.min(cw * 0.7, 70.0), height: math.min(rh * 0.6, 34.0));
    cv.drawOval(r, fill(const Color(0xFF3A2618)));
    if (i == 0) {
      // yiyecek ambarı
      final pile = math.min(1.0, c.food / 200);
      cv.drawOval(Rect.fromCenter(center: r.center + const Offset(0, 6), width: r.width * 0.7 * pile + 6, height: r.height * 0.5 * pile + 3),
          fill(const Color(0xFF7FB069)));
    } else if (i == 1) {
      for (var k = 0; k < math.min(c.larvae.length, 8); k++) {
        cv.drawOval(Rect.fromCenter(center: r.center + Offset(-r.width * 0.3 + k * r.width * 0.08, 4), width: 7, height: 10),
            fill(const Color(0xFFF7F1E3)));
      }
    } else if (i - 2 < c.fungus) {
      for (var k = 0; k < 4; k++) {
        final p = r.center + Offset(-12 + k * 8.0, 4);
        cv.drawCircle(p, 4, fill(const Color(0xFFE9E3D5)));
      }
    }
  }
  // karıncalar tüneller boyunca
  final shown = math.min(c.ants, 60);
  final path = [Offset(s.width / 2, top), ...centers];
  for (var a = 0; a < shown; a++) {
    final speed = 0.05 + (a % 7) * 0.01;
    final u = ((c.t * speed + a * 0.137) % 1.0) * (path.length - 1);
    final seg = u.floor().clamp(0, path.length - 2).toInt();
    final f = u - seg;
    final p = Offset.lerp(path[seg], path[seg + 1], f)!;
    final jitter = Offset(math.sin(a * 3.1) * 3, math.cos(a * 2.3) * 3);
    cv.drawCircle(p + jitter, 2.4, fill(const Color(0xFF1B0F08)));
    cv.drawCircle(p + jitter + const Offset(2.5, 0), 1.6, fill(const Color(0xFF1B0F08)));
  }
  // dışarıdaki toplayıcılar
  for (var a = 0; a < math.min(c.ants ~/ 3, 12); a++) {
    final x = (c.t * (14 + a) + a * 47) % s.width;
    cv.drawCircle(Offset(x, top - 3), 2.2, fill(const Color(0xFF1B0F08)));
  }
}
