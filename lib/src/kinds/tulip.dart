import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';
import 'idle.dart' show numOf, intOf;

// =================================================================== Lale Serası
//
// Lale Devri'nde bir sera. Tarhlar kendiliğinden lale yetiştirir; çiçekler
// çarşı tezgâhında satılır. İki çeşidi melezleyerek yeni renk ve desenler
// keşfedilir: renk iki alelle (kırmızı, sarı, beyaz, mor), alev deseni
// baskın bir genle (F) belirlenir. 10 renk × 2 desen = 20 çeşitlik defter.

/// Park–Miller üreteci: her platformda (web dahil) aynı sonucu verir.
class TulipRng {
  int x;
  TulipRng(int seed) : x = (seed % 2147483646) + 1;
  int next(int n) {
    x = (x * 48271) % 2147483647;
    return x % n;
  }
}

/// Genotip: iki renk aleli (0 kırmızı, 1 sarı, 2 beyaz, 3 mor) ve alev aleli sayısı (0..2).
class TulipGene {
  final int a;
  final int b;
  final int f;
  const TulipGene(this.a, this.b, this.f);

  int get lo => math.min(a, b);
  int get hi => math.max(a, b);
  bool get flamed => f > 0;

  /// Görünüş anahtarı (defterdeki çeşit).
  int get pheno => lo * 4 + hi + (flamed ? 16 : 0);
  int get code => a * 12 + b * 3 + f;

  double get value {
    final v = (kTulipColorValue[a] + kTulipColorValue[b]) / 2 * (a == b ? 1.0 : 1.35);
    return v * (flamed ? 1.8 : 1.0);
  }

  @override
  bool operator ==(Object o) => o is TulipGene && o.a == a && o.b == b && o.f == f;

  @override
  int get hashCode => code;
}

const List<double> kTulipColorValue = [2.0, 2.4, 3.0, 4.0];
const List<Color> kTulipColors = [Color(0xFFD7263D), Color(0xFFF4C430), Color(0xFFF7F4EA), Color(0xFF7B4FB8)];
const List<String> kTulipColorKeys = ['tRed', 'tYellow', 'tWhite', 'tPurple'];
const List<double> kTulipGrow = [1.5, 1.0, 0.7, 0.3];

/// Defterde olabilecek bütün çeşitler.
const int kTulipVarieties = 20;

class TulipPuzzle extends SPuzzle {
  final int d;
  final int season0;
  final double priceMul;
  final int rngSeed;
  final double goal;
  final int par;
  final int limit;
  const TulipPuzzle(this.d, this.season0, this.priceMul, this.rngSeed, this.goal, this.par, this.limit);

  TulipPuzzle withGoal(double g, int p) => TulipPuzzle(d, season0, priceMul, rngSeed, g, p, limit);
}

class TulipSim {
  final TulipPuzzle z;
  final TulipRng rng;
  double coins = 10;
  double total = 0;
  int beds = 2;
  int glass = 0;
  int gardener = 0;
  int stall = 0;
  int crosses = 0;
  int harvested = 0;
  int prestiges = 0;
  double lasting = 0;
  double extra = 1;
  double t = 0;
  List<double> prog = [0, 0];
  List<TulipGene> genes = const [TulipGene(0, 0, 0), TulipGene(1, 1, 1), TulipGene(2, 3, 0)].toList();
  Set<int> book = {};

  TulipSim(this.z) : rng = TulipRng(z.rngSeed) {
    book = {for (final g in genes) g.pheno};
  }

  int get season => (z.season0 + t ~/ kSeasonLen) % 4;

  TulipGene get best => genes.reduce((x, y) => y.value > x.value ? y : x);

  double get price => best.value * (1 + 0.3 * stall) * z.priceMul * extra * (1 + lasting);

  double get bedCost => 15 * math.pow(1.55, beds - 2).toDouble();
  double get glassCost => 40 * math.pow(1.7, glass).toDouble();
  double get gardenerCost => 120 * math.pow(2.0, gardener).toDouble();
  double get stallCost => 60 * math.pow(1.65, stall).toDouble();
  double get crossCost => 20 * math.pow(1.3, crosses).toDouble();

  /// Saniyede yaklaşık kazanç (çevrimdışı ve gösterge için).
  double get rate => beds * 3 * price / 20 * (1 + 0.25 * glass) * kTulipGrow[season];

  int get ready => prog.where((p) => p >= 1).length;

  int harvest() {
    var n = 0;
    for (var i = 0; i < prog.length; i++) {
      if (prog[i] >= 1) {
        prog[i] = 0;
        n++;
      }
    }
    if (n > 0) {
      final g = n * 3 * price;
      coins += g;
      total += g;
      harvested += n * 3;
    }
    return n;
  }

  void step(double dt) {
    final r = dt / 20 * (1 + 0.25 * glass) * kTulipGrow[season];
    for (var i = 0; i < prog.length; i++) {
      prog[i] = math.min(1.0, prog[i] + r);
    }
    if (gardener > 0) harvest();
    t += dt;
  }

  bool buy(int k) {
    final c = [bedCost, glassCost, stallCost, gardenerCost][k];
    if (coins < c) return false;
    coins -= c;
    switch (k) {
      case 0:
        beds++;
        prog = [...prog, 0];
      case 1:
        glass++;
      case 2:
        stall++;
      default:
        gardener++;
    }
    return true;
  }

  /// İki genotipi melezler; yeni bir çeşitse çeşidi, değilse null döner.
  /// Para yetmezse hiçbir şey olmaz (`crossed` false).
  ({bool crossed, TulipGene? found}) cross(TulipGene x, TulipGene y) {
    final c = crossCost;
    if (coins < c) return (crossed: false, found: null);
    coins -= c;
    crosses++;
    final a = rng.next(2) == 0 ? x.a : x.b;
    final b = rng.next(2) == 0 ? y.a : y.b;
    final fa = x.f == 2 ? 1 : (x.f == 1 ? rng.next(2) : 0);
    final fb = y.f == 2 ? 1 : (y.f == 1 ? rng.next(2) : 0);
    final g = TulipGene(a, b, fa + fb);
    if (!genes.contains(g)) genes = [...genes, g];
    if (book.contains(g.pheno)) return (crossed: true, found: null);
    book = {...book, g.pheno};
    final bonus = 10 * g.value * z.priceMul;
    coins += bonus;
    total += bonus;
    return (crossed: true, found: g);
  }

  /// Yeni sera: her şey sıfırlanır, defter ve kalıcı çarpan kalır.
  int get prestigeGain => book.length >= 6 ? book.length : 0;

  void prestige() {
    final g = prestigeGain;
    if (g <= 0) return;
    lasting += 0.05 * g;
    prestiges++;
    coins = 10;
    beds = 2;
    glass = 0;
    gardener = 0;
    stall = 0;
    prog = [0, 0];
  }

  List<TulipGene> get byValue => [...genes]..sort((x, y) => y.value.compareTo(x.value));

  void botSecond() {
    harvest();
    if (book.length < kTulipVarieties && coins >= crossCost && crosses < 4 + 3 * book.length) {
      final gs = byValue;
      cross(gs[crosses % gs.length], gs[(crosses * 3 + 1) % gs.length]);
    } else {
      final costs = [bedCost, glassCost, stallCost, gardenerCost];
      var k = 0;
      for (var i = 1; i < 4; i++) {
        if (costs[i] < costs[k]) k = i;
      }
      buy(k);
    }
    step(1);
  }
}

int tulipReach(TulipPuzzle z, int limit) {
  final s = TulipSim(z);
  for (var i = 1; i <= limit; i++) {
    s.botSecond();
    if (s.total >= z.goal) return i;
  }
  return -1;
}

class TulipKind extends SimKind {
  @override
  String get id => 'lale';
  const TulipKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final seconds = 150 + 45 * d;
    final base = TulipPuzzle(d, r.nextInt(4), (1.0 - 0.03 * d) * (0.92 + 0.16 * r.nextDouble()), r.nextInt(1 << 30), 1e18, seconds,
        seconds + seconds ~/ 4);
    final s = TulipSim(base);
    for (var i = 0; i < seconds; i++) {
      s.botSecond();
    }
    final goal = (s.total * 0.95).floorToDouble();
    if (goal < 100) return null;
    final z = base.withGoal(goal, seconds);
    final reach = tulipReach(z, z.limit);
    if (reach < 0) return null;
    return z.withGoal(goal, reach);
  }

  @override
  bool check(SPuzzle p) => p is TulipPuzzle && p.goal >= 100 && tulipReach(p, p.limit) == p.par;

  @override
  Widget build(SimPlay play) => _TulipView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('varieties', 'Keşfedilen lale çeşidi', 'Tulip varieties found', scale: 5),
        const GameStat('flowers', 'Satılan lale', 'Tulips sold', scale: 100),
        const GameStat('prestige', 'Yeni sera', 'New greenhouses', scale: 2),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('varieties', 'varieties', [3, 10, 30]),
        const MissionTemplate('flowers', 'flowers', [100, 500, 2000]),
      ];
}

String tulipName(String lang, TulipGene g) {
  final c = g.lo == g.hi ? st(lang, kTulipColorKeys[g.lo]) : '${st(lang, kTulipColorKeys[g.lo])}–${st(lang, kTulipColorKeys[g.hi])}';
  return g.flamed ? '$c · ${st(lang, 'tFlamed')}' : c;
}

class _TulipView extends StatefulWidget {
  final SimPlay play;
  const _TulipView({required this.play});

  @override
  State<_TulipView> createState() => _TulipViewState();
}

class _TulipViewState extends State<_TulipView> with SimClock<_TulipView> {
  late final TulipPuzzle z = widget.play.puzzle as TulipPuzzle;
  late final TulipSim c = TulipSim(z);
  bool calm = false;
  double saveIn = 5;
  String note = '';
  double noteUntil = -1;
  double armUntil = -1;
  final List<int> picked = [];
  int found = 0;
  bool showBook = false;

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    c.extra = SimPrefs.renownMul(play.gameId);
    final r = play.restored;
    if (r.isNotEmpty) {
      c.coins = numOf(r['co'], 10);
      c.total = numOf(r['to'], 0);
      c.beds = math.max(2, intOf(r['be'], 2));
      c.glass = intOf(r['gl'], 0);
      c.gardener = intOf(r['ga'], 0);
      c.stall = intOf(r['sa'], 0);
      c.crosses = intOf(r['cr'], 0);
      c.harvested = intOf(r['hv'], 0);
      c.prestiges = intOf(r['pr'], 0);
      c.lasting = numOf(r['la'], 0);
      c.t = numOf(r['t'], 0);
      c.rng.x = math.max(1, intOf(r['rx'], c.rng.x));
      c.prog = List<double>.filled(c.beds, 0);
      final gl = r['ge'];
      if (gl is List) {
        final gs = <TulipGene>[];
        for (final v in gl) {
          if (v is num) {
            final k = v.toInt();
            gs.add(TulipGene(clampI(k ~/ 12, 0, 3), clampI(k % 12 ~/ 3, 0, 3), clampI(k % 3, 0, 2)));
          }
        }
        if (gs.isNotEmpty) {
          c.genes = gs;
          c.book = {for (final g in gs) g.pheno};
        }
      }
      found = intOf(r['fo'], 0);
      seconds = intOf(r['sec'], 0);
      final away = play.awaySeconds(cap: 3600);
      if (away >= 20) {
        final g = math.max(0.0, c.rate) * away * 0.5;
        c.coins += g;
        c.total += g;
        note = st(lang, 'offline').replaceAll('{0}', '🌷 ${fmtNum(g)}');
        noteUntil = c.t + 8;
      }
    }
    SimPrefs.init().then((_) {
      if (!mounted) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        c.extra = SimPrefs.renownMul(play.gameId);
      });
    });
    startLoop(250, _tick);
  }

  void _save() => play.save({
        'co': c.coins,
        'to': c.total,
        'be': c.beds,
        'gl': c.glass,
        'ga': c.gardener,
        'sa': c.stall,
        'cr': c.crosses,
        'hv': c.harvested,
        'pr': c.prestiges,
        'la': c.lasting,
        't': c.t,
        'rx': c.rng.x,
        'ge': [for (final g in c.genes) g.code],
        'fo': found,
        'sec': seconds,
      });

  void _tick(double dt) {
    if (ended) return;
    c.step(dt);
    saveIn -= dt;
    if (saveIn <= 0) {
      saveIn = 5;
      _save();
    }
    if (c.total >= z.goal) _win();
  }

  void _win() {
    if (ended) return;
    ended = true;
    stopLoop();
    _save();
    play.sfx(Sfx.win);
    play.win(stars: starsByTime(seconds, z.par), calm: calm, score: c.total.round(), seconds: seconds, stats: {
      'varieties': found,
      'flowers': c.harvested,
      'prestige': c.prestiges,
    });
  }

  void _harvest() {
    if (c.harvest() > 0) {
      play.sfx(Sfx.coin);
    } else {
      play.sfx(Sfx.tap);
    }
  }

  void _tap(Offset p, Size s) {
    if (ended) return;
    setState(_harvest);
  }

  void _cross() {
    final gs = c.byValue;
    final x = picked.isNotEmpty ? c.genes[picked[0]] : gs[0];
    final y = picked.length > 1 ? c.genes[picked[1]] : (gs.length > 1 ? gs[1] : gs[0]);
    final r = c.cross(x, y);
    if (!r.crossed) return;
    final g = r.found;
    if (g != null) {
      found++;
      note = st(lang, 'tNew').replaceAll('{0}', tulipName(lang, g));
      noteUntil = c.t + 6;
      play.sfx(Sfx.unlock);
    } else {
      note = st(lang, 'tSame');
      noteUntil = c.t + 3;
      play.sfx(Sfx.place);
    }
    picked.clear();
  }

  @override
  Widget build(BuildContext context) {
    final season = c.season;
    final gain = c.prestigeGain;
    final banner = noteUntil > c.t && note.isNotEmpty
        ? SNote(note, icon: Icons.local_florist)
        : (season == 3 ? SNote(st(lang, 'tWinter'), icon: Icons.ac_unit) : null);
    final costs = [c.bedCost, c.glassCost, c.stallCost, c.gardenerCost];
    const icons = [Icons.grid_view, Icons.wb_sunny_outlined, Icons.storefront, Icons.person_outline];
    const keys = ['tBed', 'tGlass', 'tStall', 'tGardener'];
    final levels = [c.beds, c.glass, c.stall, c.gardener];
    return SimFrame(
      play: play,
      moneyIcon: Icons.monetization_on_outlined,
      money: fmtNum(c.coins),
      sub: '~${fmtNum(c.rate)}${st(lang, 'perSec')}',
      goalText: st(lang, 'goalEarn').replaceAll('{0}', '${fmtNum(c.total)}/${fmtNum(z.goal)}'),
      progress: c.total / z.goal,
      season: season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      banner: banner,
      sceneFlex: 5,
      panelFlex: 4,
      scene: SceneCanvas(paint: (cv, s) => _paintGreenhouse(cv, s, c, season), onTap: _tap, semantics: st(lang, 'tapScene')),
      panel: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          SBadge(Icons.local_florist, '${st(lang, 'tBook')} ${c.book.length}/$kTulipVarieties'),
          SBadge(Icons.spa, '${st(lang, 'tReady')} ${c.ready}/${c.beds}'),
          if (c.lasting > 0) SBadge(Icons.auto_awesome, '×${(1 + c.lasting).toStringAsFixed(2)}'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: c.ready > 0 ? () => setState(_harvest) : null,
              icon: const Icon(Icons.shopping_basket_outlined),
              label: FittedBox(child: Text(st(lang, 'harvest'))),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: c.coins >= c.crossCost ? () => setState(_cross) : null,
              icon: const Icon(Icons.call_merge),
              label: FittedBox(child: Text('${st(lang, 'tCross')} · ${fmtNum(c.crossCost)}')),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(st(lang, 'tPick'), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < c.genes.length && i < 24; i++)
            SChip(
              selected: picked.contains(i),
              tooltip: '${tulipName(lang, c.genes[i])} · ${c.genes[i].value.toStringAsFixed(1)}',
              onTap: () => setState(() {
                if (picked.contains(i)) {
                  picked.remove(i);
                } else {
                  if (picked.length >= 2) picked.removeAt(0);
                  picked.add(i);
                }
                play.sfx(Sfx.tap);
              }),
              child: SizedBox(width: 26, height: 26, child: CustomPaint(painter: _TulipIcon(c.genes[i]))),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var k = 0; k < 4; k++)
            SChip(
              onTap: c.coins >= costs[k]
                  ? () => setState(() {
                        if (c.buy(k)) play.sfx(Sfx.unlock);
                      })
                  : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icons[k], size: 18),
                const SizedBox(width: 4),
                Text('${st(lang, keys[k])} ${levels[k]} · ${fmtNum(costs[k])}', style: const TextStyle(fontSize: 13)),
              ]),
            ),
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
                      c.prestige();
                      note = st(lang, 'prestigeDone').replaceAll('{0}', '×${(1 + c.lasting).toStringAsFixed(2)}');
                      noteUntil = c.t + 5;
                      play.sfx(Sfx.unlock);
                    })
                : null,
            child: Text(gain > 0 ? (armUntil > c.t ? st(lang, 'sure') : '${st(lang, 'tNewHouse')} +${(0.05 * gain).toStringAsFixed(2)}') : '${st(lang, 'tNewHouse')} 6+',
                style: const TextStyle(fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => showBook = !showBook),
          icon: Icon(showBook ? Icons.expand_less : Icons.menu_book_outlined),
          label: Text(st(lang, 'tBook')),
        ),
        if (showBook)
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var lo = 0; lo < 4; lo++)
              for (var hi = lo; hi < 4; hi++)
                for (var fl = 0; fl < 2; fl++)
                  Opacity(
                    opacity: c.book.contains(lo * 4 + hi + fl * 16) ? 1 : 0.18,
                    child: SizedBox(width: 30, height: 30, child: CustomPaint(painter: _TulipIcon(TulipGene(lo, hi, fl)))),
                  ),
          ]),
      ]),
    );
  }
}

/// Tek bir lalenin küçük çizimi (alevli desen dahil).
void paintTulip(Canvas cv, Offset base, double h, TulipGene g, {double open = 1}) {
  final stem = stroke(const Color(0xFF3E8E41), math.max(1.5, h * 0.06));
  final top = base - Offset(0, h);
  cv.drawLine(base, top + Offset(0, h * 0.28), stem);
  cv.drawOval(Rect.fromCenter(center: base - Offset(h * 0.12, h * 0.3), width: h * 0.16, height: h * 0.42), fill(const Color(0xFF4F9A4A)));
  if (open <= 0) return;
  final w = h * 0.42 * open;
  final cup = Path()
    ..moveTo(top.dx - w / 2, top.dy + h * 0.05)
    ..quadraticBezierTo(top.dx - w / 2, top.dy + h * 0.36, top.dx, top.dy + h * 0.36)
    ..quadraticBezierTo(top.dx + w / 2, top.dy + h * 0.36, top.dx + w / 2, top.dy + h * 0.05)
    ..lineTo(top.dx + w / 4, top.dy + h * 0.16)
    ..lineTo(top.dx, top.dy - h * 0.02)
    ..lineTo(top.dx - w / 4, top.dy + h * 0.16)
    ..close();
  cv.drawPath(cup, fill(kTulipColors[g.a]));
  if (g.a != g.b) {
    final inner = Path()
      ..moveTo(top.dx - w / 4, top.dy + h * 0.16)
      ..quadraticBezierTo(top.dx, top.dy + h * 0.34, top.dx + w / 4, top.dy + h * 0.16)
      ..lineTo(top.dx, top.dy - h * 0.02)
      ..close();
    cv.drawPath(inner, fill(kTulipColors[g.b]));
  }
  if (g.flamed) {
    final flame = stroke(g.hi == 3 ? const Color(0xFFF4C430) : const Color(0xFF7B1E2B), math.max(1.0, h * 0.035));
    for (final dx in [-0.12, 0.0, 0.12]) {
      cv.drawLine(Offset(top.dx + w * dx, top.dy + h * 0.3), Offset(top.dx + w * dx * 1.4, top.dy + h * 0.08), flame);
    }
  }
  cv.drawPath(cup, stroke(const Color(0x55000000), 0.8));
}

class _TulipIcon extends CustomPainter {
  final TulipGene g;
  _TulipIcon(this.g);

  @override
  void paint(Canvas canvas, Size size) => paintTulip(canvas, Offset(size.width / 2, size.height * 0.98), size.height * 0.95, g);

  @override
  bool shouldRepaint(covariant _TulipIcon old) => old.g != g;
}

void _paintGreenhouse(Canvas cv, Size s, TulipSim c, int season) {
  paintSky(cv, s, season, groundAt: 0.78);
  // sera iskeleti
  final house = Rect.fromLTWH(s.width * 0.04, s.height * 0.12, s.width * 0.92, s.height * 0.7);
  final roof = Path()
    ..moveTo(house.left, house.top + house.height * 0.22)
    ..lineTo(house.center.dx, house.top)
    ..lineTo(house.right, house.top + house.height * 0.22)
    ..lineTo(house.right, house.bottom)
    ..lineTo(house.left, house.bottom)
    ..close();
  final glassAlpha = 0.18 + 0.05 * math.min(c.glass, 6);
  cv.drawPath(roof, fill(Color.fromRGBO(225, 244, 240, glassAlpha)));
  final frame = stroke(const Color(0xFF6B4F3A), 2.2);
  cv.drawPath(roof, frame);
  for (var i = 1; i < 6; i++) {
    final x = house.left + house.width * i / 6;
    final ty = house.top + house.height * 0.22 * (1 - (x - house.center.dx).abs() / (house.width / 2));
    cv.drawLine(Offset(x, house.bottom), Offset(x, ty), stroke(const Color(0x886B4F3A), 1.2));
  }
  // tarhlar
  final shown = math.min(c.beds, 16);
  final cols = math.min(shown, 4);
  final rows = (shown + cols - 1) ~/ cols;
  final cw = house.width / cols;
  final rh = (house.height * 0.72) / math.max(rows, 2);
  final best = c.best;
  for (var i = 0; i < shown; i++) {
    final cx = house.left + cw * (i % cols) + cw / 2;
    final by = house.top + house.height * 0.3 + rh * (i ~/ cols + 1);
    cv.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, by), width: cw * 0.82, height: 10), const Radius.circular(4)),
        fill(const Color(0xFF6F4A2F)));
    final p = i < c.prog.length ? c.prog[i] : 0.0;
    for (var k = 0; k < 3; k++) {
      final x = cx + (k - 1) * cw * 0.22;
      paintTulip(cv, Offset(x, by - 3), rh * 0.75 * (0.35 + 0.65 * p), best, open: p >= 1 ? 1 : (p > 0.6 ? (p - 0.6) * 2 : 0));
    }
    if (p >= 1) drawLabel(cv, '✿', Offset(cx + cw * 0.36, by - rh * 0.7), 12, const Color(0xFFB8336A));
  }
  paintSeasonParticles(cv, s, season, c.t, count: 10);
}
