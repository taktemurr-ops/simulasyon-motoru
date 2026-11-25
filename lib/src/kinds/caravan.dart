import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';
import 'idle.dart' show numOf, intOf;
import 'tulip.dart' show TulipRng;

// =================================================================== Kervansaray İşletmesi
//
// İpek Yolu üzerinde bir han. Kervanlar dört ihtiyaçla gelir: dinlenme
// (odalar), yem ve bakım (ahırlar), yemek (mutfak) ve su (kuyu). Her tesis
// kendi ihtiyacını seviyesine göre karşılar; doyan kervan yolun değerine göre
// öder. Sırada en çok 4 kervan bekler, fazlası başka hana gider. Ticaret yolu
// görevleri (6 kervan ağırla) uzak ve kazançlı yolları açar.

const List<double> kCaravanArrive = [1.0, 0.8, 1.0, 1.6];
const List<double> kCaravanPay = [3.0, 4.0, 5.5, 7.0];
const List<double> kCaravanFacCost = [1.0, 1.1, 1.2, 0.9];
const List<String> kCaravanFacKeys = ['kRooms', 'kStables', 'kKitchen', 'kWell'];
const List<IconData> kCaravanFacIcons = [Icons.bed_outlined, Icons.agriculture_outlined, Icons.soup_kitchen_outlined, Icons.water_drop_outlined];
const List<String> kCaravanRouteKeys = ['rBursa', 'rAleppo', 'rTabriz', 'rSamarkand'];
const int kCaravanQueue = 4;

class CaravanPuzzle extends SPuzzle {
  final int d;
  final int season0;
  final double priceMul;
  final int rngSeed;
  final double goal;
  final int par;
  final int limit;
  const CaravanPuzzle(this.d, this.season0, this.priceMul, this.rngSeed, this.goal, this.par, this.limit);

  CaravanPuzzle withGoal(double g, int p) => CaravanPuzzle(d, season0, priceMul, rngSeed, g, p, limit);
}

class Caravan {
  final List<double> need;
  final List<double> full;
  final double pay;
  final int route;
  Caravan(this.full, this.pay, this.route) : need = [...full];

  bool get done => need.every((x) => x <= 0);
  double get left => need.fold(0.0, (a, b) => a + b) / full.fold(0.0, (a, b) => a + b);
}

class CaravanSim {
  final CaravanPuzzle z;
  final TulipRng rng;
  double coins = 20;
  double total = 0;
  List<int> lv = [1, 1, 1, 1];
  int staff = 0;
  int route = 0;
  int served = 0;
  int lost = 0;
  int prestiges = 0;
  double lasting = 0;
  double extra = 1;
  bool calm = false;
  double arr = 4;
  double t = 0;
  double tips = 0;
  List<Caravan> queue = [];

  CaravanSim(this.z) : rng = TulipRng(z.rngSeed);

  int get season => (z.season0 + t ~/ kSeasonLen) % 4;
  int get unlocked => math.min(3, served ~/ 6);

  double facCost(int i) => 20 * math.pow(1.6, lv[i] - 1).toDouble() * kCaravanFacCost[i];
  double get staffCost => 80 * math.pow(1.9, staff).toDouble();
  double get speed => 0.5 * (1 + 0.25 * staff);
  double get interval => 12 * kCaravanArrive[season] * (1 + 0.15 * route) * (1 + 0.02 * z.d);

  /// Yaklaşık kazanç hızı (çevrimdışı gelir için).
  double get rate {
    final perCaravan = (2 + route + z.d / 3) * 4 / 2 * kCaravanPay[route] * z.priceMul * extra * (1 + lasting);
    return perCaravan / interval;
  }

  void _arrive() {
    final hi = 2 + route + z.d ~/ 3;
    final n = [for (var i = 0; i < 4; i++) (1 + rng.next(hi)).toDouble()];
    if (season == 1) n[3] += 2;
    if (season == 3) n[0] += 2;
    final sum = n.fold(0.0, (a, b) => a + b);
    queue = [...queue, Caravan(n, sum * kCaravanPay[route] * z.priceMul * extra * (1 + lasting), route)];
  }

  void step(double dt) {
    arr -= dt;
    if (arr <= 0) {
      arr = interval;
      if (queue.length < kCaravanQueue) {
        _arrive();
      } else if (!calm) {
        lost++;
      }
    }
    if (queue.isNotEmpty) {
      final c = queue.first;
      final sp = dt * speed;
      for (var i = 0; i < 4; i++) {
        c.need[i] = math.max(0.0, c.need[i] - lv[i] * sp);
      }
      if (c.done) {
        queue = queue.sublist(1);
        served++;
        coins += c.pay;
        total += c.pay;
      }
    }
    t += dt;
  }

  bool buyFac(int i) {
    final c = facCost(i);
    if (coins < c) return false;
    coins -= c;
    lv = [...lv]..[i] = lv[i] + 1;
    return true;
  }

  bool buyStaff() {
    final c = staffCost;
    if (coins < c) return false;
    coins -= c;
    staff++;
    return true;
  }

  /// Oyuncunun dokunuşu: sıradaki kervana elden yardım (küçük bahşiş).
  void help() {
    if (queue.isEmpty) return;
    final c = queue.first;
    for (var i = 0; i < 4; i++) {
      c.need[i] = math.max(0.0, c.need[i] - 0.15);
    }
    final g = 0.2 * z.priceMul;
    coins += g;
    total += g;
    tips += g;
  }

  int get prestigeGain => served >= 30 ? served ~/ 15 : 0;

  /// Yeni han: tesisler sıfırlanır, kalıcı çarpan kalır.
  void prestige() {
    final g = prestigeGain;
    if (g <= 0) return;
    lasting += 0.06 * g;
    prestiges++;
    coins = 20;
    lv = [1, 1, 1, 1];
    staff = 0;
    route = 0;
    queue = [];
    served = 0;
  }

  int get bottleneck {
    var k = 0;
    if (queue.isNotEmpty) {
      final n = queue.first.need;
      for (var i = 1; i < 4; i++) {
        if (n[i] / lv[i] > n[k] / lv[k]) k = i;
      }
    } else {
      for (var i = 1; i < 4; i++) {
        if (lv[i] < lv[k]) k = i;
      }
    }
    return k;
  }

  void botSecond() {
    route = unlocked;
    final i = bottleneck;
    if (staffCost < facCost(i)) {
      buyStaff();
    } else {
      buyFac(i);
    }
    step(1);
  }
}

int caravanReach(CaravanPuzzle z, int limit) {
  final s = CaravanSim(z);
  for (var i = 1; i <= limit; i++) {
    s.botSecond();
    if (s.total >= z.goal) return i;
  }
  return -1;
}

class CaravanKind extends SimKind {
  @override
  String get id => 'kervan';
  const CaravanKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final seconds = 150 + 45 * d;
    final base = CaravanPuzzle(d, r.nextInt(4), (1.0 - 0.03 * d) * (0.92 + 0.16 * r.nextDouble()), r.nextInt(1 << 30), 1e18, seconds,
        seconds + seconds ~/ 4);
    final s = CaravanSim(base);
    for (var i = 0; i < seconds; i++) {
      s.botSecond();
    }
    final goal = (s.total * 0.95).floorToDouble();
    if (goal < 60) return null;
    final z = base.withGoal(goal, seconds);
    final reach = caravanReach(z, z.limit);
    if (reach < 0) return null;
    return z.withGoal(goal, reach);
  }

  @override
  bool check(SPuzzle p) => p is CaravanPuzzle && p.goal >= 60 && caravanReach(p, p.limit) == p.par;

  @override
  Widget build(SimPlay play) => _CaravanView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('caravans', 'Ağırlanan kervan', 'Caravans hosted', scale: 20),
        const GameStat('prestige', 'Yeni han', 'New inns', scale: 2),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('caravans', 'caravans', [10, 50, 200]),
      ];
}

class _CaravanView extends StatefulWidget {
  final SimPlay play;
  const _CaravanView({required this.play});

  @override
  State<_CaravanView> createState() => _CaravanViewState();
}

class _CaravanViewState extends State<_CaravanView> with SimClock<_CaravanView> {
  late final CaravanPuzzle z = widget.play.puzzle as CaravanPuzzle;
  late final CaravanSim c = CaravanSim(z);
  bool calm = false;
  double saveIn = 5;
  String note = '';
  double noteUntil = -1;
  double armUntil = -1;
  int hosted = 0;

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
      c.coins = numOf(r['co'], 20);
      c.total = numOf(r['to'], 0);
      final l = r['lv'];
      if (l is List && l.length == 4) c.lv = [for (final x in l) math.max(1, intOf(x, 1))];
      c.staff = intOf(r['sf'], 0);
      c.route = clampI(intOf(r['ro'], 0), 0, 3);
      c.served = intOf(r['se'], 0);
      c.lost = intOf(r['lo'], 0);
      c.prestiges = intOf(r['pr'], 0);
      c.lasting = numOf(r['la'], 0);
      c.t = numOf(r['t'], 0);
      c.rng.x = math.max(1, intOf(r['rx'], c.rng.x));
      hosted = intOf(r['ho'], 0);
      seconds = intOf(r['sec'], 0);
      final away = play.awaySeconds(cap: 3600);
      if (away >= 20) {
        final g = math.max(0.0, c.rate) * away * 0.5;
        c.coins += g;
        c.total += g;
        note = st(lang, 'offline').replaceAll('{0}', '🪙 ${fmtNum(g)}');
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
        'co': c.coins,
        'to': c.total,
        'lv': c.lv,
        'sf': c.staff,
        'ro': c.route,
        'se': c.served,
        'lo': c.lost,
        'pr': c.prestiges,
        'la': c.lasting,
        't': c.t,
        'rx': c.rng.x,
        'ho': hosted,
        'sec': seconds,
      });

  void _tick(double dt) {
    if (ended) return;
    final before = c.served;
    c.step(dt);
    if (c.served > before) {
      hosted += c.served - before;
      play.sfx(Sfx.coin);
    }
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
      'caravans': hosted,
      'prestige': c.prestiges,
    });
  }

  void _tap(Offset p, Size s) {
    if (ended) return;
    setState(() {
      c.help();
      play.sfx(Sfx.tap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final season = c.season;
    final gain = c.prestigeGain;
    final head = c.queue.isEmpty ? null : c.queue.first;
    final full = c.queue.length >= kCaravanQueue;
    final banner = noteUntil > c.t && note.isNotEmpty
        ? SNote(note, icon: Icons.nightlight_round)
        : (full && !calm ? SNote(st(lang, 'kFull'), icon: Icons.warning_amber, color: const Color(0xFFFFE2C2)) : null);
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
        c.calm = v;
        SimPrefs.calm = v;
      }),
      banner: banner,
      sceneFlex: 5,
      panelFlex: 4,
      scene: SceneCanvas(paint: (cv, s) => _paintInn(cv, s, c, season), onTap: _tap, semantics: st(lang, 'tapScene')),
      panel: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          SBadge(Icons.groups_outlined, '${st(lang, 'served')} ${c.served}'),
          SBadge(Icons.hourglass_bottom, '${st(lang, 'kQueue')} ${c.queue.length}/$kCaravanQueue'),
          if (c.lost > 0) SBadge(Icons.directions_walk, '${st(lang, 'lost')} ${c.lost}'),
          if (c.lasting > 0) SBadge(Icons.auto_awesome, '×${(1 + c.lasting).toStringAsFixed(2)}'),
        ]),
        if (head != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(children: [
                    Icon(kCaravanFacIcons[i], size: 18),
                    LinearProgressIndicator(value: head.full[i] <= 0 ? 1 : 1 - head.need[i] / head.full[i], minHeight: 6),
                  ]),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < 4; i++)
            SChip(
              onTap: c.coins >= c.facCost(i)
                  ? () => setState(() {
                        if (c.buyFac(i)) play.sfx(Sfx.unlock);
                      })
                  : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(kCaravanFacIcons[i], size: 18),
                const SizedBox(width: 4),
                Text('${st(lang, kCaravanFacKeys[i])} ${c.lv[i]} · ${fmtNum(c.facCost(i))}', style: const TextStyle(fontSize: 13)),
              ]),
            ),
          SChip(
            onTap: c.coins >= c.staffCost
                ? () => setState(() {
                      if (c.buyStaff()) play.sfx(Sfx.unlock);
                    })
                : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.person_add_alt, size: 18),
              const SizedBox(width: 4),
              Text('${st(lang, 'kStaff')} ${c.staff} · ${fmtNum(c.staffCost)}', style: const TextStyle(fontSize: 13)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(st(lang, 'kRoute'), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var r = 0; r < 4; r++)
            SChip(
              selected: c.route == r,
              tooltip: r <= c.unlocked ? '×${kCaravanPay[r].toStringAsFixed(1)}' : st(lang, 'kMission').replaceAll('{0}', '${6 * r}'),
              onTap: r <= c.unlocked
                  ? () => setState(() {
                        c.route = r;
                        play.sfx(Sfx.tap);
                      })
                  : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(r <= c.unlocked ? Icons.route : Icons.lock_outline, size: 16),
                const SizedBox(width: 4),
                Text(st(lang, kCaravanRouteKeys[r]), style: const TextStyle(fontSize: 13)),
              ]),
            ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SChip(
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
            child: Text(gain > 0 ? (armUntil > c.t ? st(lang, 'sure') : '${st(lang, 'kNewInn')} +${(0.06 * gain).toStringAsFixed(2)}') : '${st(lang, 'kNewInn')} 30+',
                style: const TextStyle(fontSize: 13)),
          ),
        ),
      ]),
    );
  }
}

void _paintCamel(Canvas cv, Offset p, double h, Color body) {
  final b = fill(body);
  cv.drawOval(Rect.fromCenter(center: p, width: h * 1.2, height: h * 0.5), b);
  cv.drawCircle(p + Offset(-h * 0.15, -h * 0.28), h * 0.2, b);
  cv.drawLine(p + Offset(h * 0.5, -h * 0.05), p + Offset(h * 0.75, -h * 0.45), stroke(body, h * 0.14));
  cv.drawOval(Rect.fromCenter(center: p + Offset(h * 0.82, -h * 0.5), width: h * 0.3, height: h * 0.16), b);
  final leg = stroke(body, h * 0.1);
  for (final dx in [-0.4, -0.2, 0.2, 0.4]) {
    cv.drawLine(p + Offset(h * dx, h * 0.15), p + Offset(h * dx, h * 0.6), leg);
  }
}

void _paintInn(Canvas cv, Size s, CaravanSim c, int season) {
  paintSky(cv, s, season, groundAt: 0.74);
  final look = kSeasonLooks[season];
  // kervansaray: taş avlu, kemerli kapı, kubbe
  final wall = Rect.fromLTWH(s.width * 0.08, s.height * 0.28, s.width * 0.6, s.height * 0.46);
  cv.drawRect(wall, fill(const Color(0xFFD9B98C)));
  for (var y = wall.top + 10; y < wall.bottom; y += 12) {
    cv.drawLine(Offset(wall.left, y), Offset(wall.right, y), stroke(const Color(0x33704B2A), 1));
  }
  final gate = Rect.fromLTWH(wall.center.dx - wall.width * 0.11, wall.bottom - wall.height * 0.55, wall.width * 0.22, wall.height * 0.55);
  final arch = Path()
    ..moveTo(gate.left, gate.bottom)
    ..lineTo(gate.left, gate.top + gate.width / 2)
    ..arcToPoint(Offset(gate.right, gate.top + gate.width / 2), radius: Radius.circular(gate.width / 2))
    ..lineTo(gate.right, gate.bottom)
    ..close();
  cv.drawPath(arch, fill(const Color(0xFF5B3A22)));
  cv.drawArc(Rect.fromCenter(center: Offset(wall.center.dx, wall.top), width: wall.width * 0.3, height: wall.width * 0.26), math.pi, math.pi, true,
      fill(const Color(0xFF3E7C8C)));
  // tesis pencereleri: seviye kadar ışık
  for (var i = 0; i < 4; i++) {
    final x = wall.left + wall.width * (i < 2 ? 0.1 + i * 0.13 : 0.64 + (i - 2) * 0.13);
    final lit = math.min(c.lv[i], 6);
    for (var k = 0; k < 2; k++) {
      final r = Rect.fromLTWH(x, wall.top + wall.height * (0.2 + k * 0.32), wall.width * 0.08, wall.height * 0.2);
      cv.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), fill(k * 3 < lit ? const Color(0xFFFFD27A) : const Color(0xFF6B4A2E)));
    }
  }
  // kuyu
  final well = Offset(s.width * 0.8, s.height * 0.68);
  cv.drawRect(Rect.fromCenter(center: well, width: 30, height: 18), fill(const Color(0xFF8C7A66)));
  cv.drawLine(well + const Offset(-14, -9), well + const Offset(-14, -30), stroke(const Color(0xFF5B3A22), 3));
  cv.drawLine(well + const Offset(14, -9), well + const Offset(14, -30), stroke(const Color(0xFF5B3A22), 3));
  cv.drawLine(well + const Offset(-16, -30), well + const Offset(16, -30), stroke(const Color(0xFF5B3A22), 3));
  // yol ve bekleyen kervanlar
  final road = s.height * 0.86;
  cv.drawLine(Offset(0, road), Offset(s.width, road), stroke(look.accent.withValues(alpha: 0.5), 6));
  for (var i = 0; i < c.queue.length; i++) {
    final x = wall.center.dx + 40 + i * s.width * 0.11;
    final bob = math.sin(c.t * 3 + i) * 1.5;
    _paintCamel(cv, Offset(x, road - 14 + bob), 22, i == 0 ? const Color(0xFFB07D48) : const Color(0xFFC79A64));
    if (i == 0) {
      final left = c.queue.first.left;
      cv.drawRect(Rect.fromLTWH(x - 18, road - 46, 36, 5), fill(const Color(0x55000000)));
      cv.drawRect(Rect.fromLTWH(x - 18, road - 46, 36 * (1 - left), 5), fill(const Color(0xFF4CAF50)));
    }
  }
  paintSeasonParticles(cv, s, season, c.t, count: 8);
}
