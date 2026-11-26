import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

// =================================================================== Lokanta (restoran işletme, zaman yönetimi)

/// Yemekler: (istasyon, pişme süresi, fiyat). İstasyonlar: 0 ocak, 1 fırın,
/// 2 soğuk tezgâh, 3 içecek.
const List<(int, double, int)> kDishes = [
  (0, 4.0, 12),
  (1, 6.0, 18),
  (0, 5.0, 16),
  (2, 3.0, 9),
  (3, 2.0, 5),
  (2, 3.0, 10),
  (1, 4.0, 6),
  (3, 3.0, 4),
];
const List<String> kDishEmoji = ['🍲', '🥙', '🍢', '🥗', '🥛', '🍮', '🥨', '🍵'];
const List<String> kDishKeys = ['dSoup', 'dPide', 'dKofte', 'dSalad', 'dAyran', 'dPudding', 'dSimit', 'dTea'];
const List<IconData> kStationIcons = [Icons.local_fire_department, Icons.bakery_dining, Icons.kitchen, Icons.local_cafe];
const List<int> kSlots = [2, 1, 1, 1];

/// Mevsime göre sevilen yemekler (yazın ayran ve salata, kışın çorba ve çay).
const List<List<int>> kDishSeason = [
  [3, 2, 3, 4, 2, 3, 3, 2],
  [2, 2, 3, 6, 6, 3, 2, 1],
  [4, 3, 3, 3, 2, 3, 3, 3],
  [6, 3, 4, 2, 1, 3, 4, 6],
];

class DinerPuzzle extends SPuzzle {
  final int d;
  final int season;
  final List<int> menu;
  final double day;
  final List<double> arrive;
  final List<List<int>> orders;
  final double patience;
  final int goal;
  final int botEarn;
  const DinerPuzzle(this.d, this.season, this.menu, this.day, this.arrive, this.orders, this.patience, this.goal, this.botEarn);
}

class Guest {
  final int id;
  final List<int> want;
  final int price;
  double patience;
  final double full;
  Guest(this.id, this.want, this.price, this.patience) : full = patience;
}

class DinerSim {
  final DinerPuzzle z;
  final double patienceMul;
  final List<Guest?> seats = List<Guest?>.filled(4, null);
  final List<Guest> line = [];
  final List<(int, double)> cooking = [];
  final List<int> ready = [];
  double t = 0;
  int next = 0;
  double earned = 0;
  int served = 0;
  int lost = 0;
  int cooked = 0;
  int lastLost = -1;

  DinerSim(this.z, {this.patienceMul = 1});

  bool get over => t > z.day + 60 || (t >= z.day && next >= z.arrive.length && line.isEmpty && seats.every((s) => s == null));

  int busy(int station) => cooking.where((c) => kDishes[c.$1].$1 == station).length;

  bool canCook(int dish) => busy(kDishes[dish].$1) < kSlots[kDishes[dish].$1] && ready.length + cooking.length < 6;

  bool cook(int dish) {
    if (!canCook(dish)) return false;
    cooking.add((dish, kDishes[dish].$2));
    return true;
  }

  /// Masadaki misafire hazır yemeklerinden birini götürür.
  bool deliver(int seat) {
    final g = seats[seat];
    if (g == null) return false;
    for (final d in List<int>.of(g.want)) {
      if (ready.contains(d)) {
        ready.remove(d);
        g.want.remove(d);
        if (g.want.isEmpty) _pay(seat);
        return true;
      }
    }
    return false;
  }

  void _pay(int seat) {
    final g = seats[seat]!;
    served++;
    earned += g.price * (1 + 0.3 * math.max(0.0, g.patience) / g.full);
    seats[seat] = null;
  }

  void step(double dt) {
    while (next < z.arrive.length && z.arrive[next] <= t) {
      final o = List<int>.of(z.orders[next]);
      line.add(Guest(next, o, o.fold<int>(0, (a, b) => a + kDishes[b].$3), z.patience * patienceMul));
      next++;
    }
    while (line.length > 3) {
      line.removeAt(0);
      lost++;
    }
    for (var i = 0; i < 4; i++) {
      if (seats[i] == null && line.isNotEmpty) seats[i] = line.removeAt(0);
    }
    for (final g in line) {
      g.patience -= dt * 0.5;
    }
    final before = line.length;
    line.removeWhere((g) => g.patience <= 0);
    lost += before - line.length;
    for (var i = 0; i < 4; i++) {
      final g = seats[i];
      if (g == null) continue;
      g.patience -= dt;
      if (g.patience <= 0) {
        seats[i] = null;
        lost++;
        lastLost = i;
      }
    }
    final keep = <(int, double)>[];
    for (final c in cooking) {
      final rem = c.$2 - dt;
      if (rem <= 0) {
        ready.add(c.$1);
        cooked++;
      } else {
        keep.add((c.$1, rem));
      }
    }
    cooking
      ..clear()
      ..addAll(keep);
    t += dt;
  }

  /// Bot: önce götür, yoksa en sabırsız misafirin eksik yemeğini pişir.
  bool botAct() {
    final order = [for (var i = 0; i < 4; i++) if (seats[i] != null) i]..sort((a, b) => seats[a]!.patience.compareTo(seats[b]!.patience));
    for (final i in order) {
      if (deliver(i)) return true;
    }
    final need = <int, int>{};
    for (final i in order) {
      for (final d in seats[i]!.want) {
        need[d] = (need[d] ?? 0) + 1;
      }
    }
    for (final d in ready) {
      need[d] = (need[d] ?? 0) - 1;
    }
    for (final c in cooking) {
      need[c.$1] = (need[c.$1] ?? 0) - 1;
    }
    for (final i in order) {
      for (final d in seats[i]!.want) {
        if ((need[d] ?? 0) > 0 && cook(d)) return true;
      }
    }
    return false;
  }
}

/// Botun bir günlük kazancı.
int dinerBot(DinerPuzzle z) {
  final s = DinerSim(z);
  var cd = 0.0;
  while (!s.over) {
    s.step(0.25);
    cd -= 0.25;
    if (cd <= 0 && s.botAct()) cd = 0.75;
  }
  return s.earned.floor();
}

class DinerKind extends SimKind {
  @override
  String get id => 'lokanta';
  const DinerKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final season = r.nextInt(4);
    final all = [0, 1, 2, 3, 4, 5, 6, 7];
    r.shuffle(all);
    final menu = (all.take(3 + d ~/ 3).toList()..sort());
    final day = 90.0 + 10 * d;
    final n = 8 + 2 * d;
    final arrive = [for (var i = 0; i < n; i++) 2 + r.nextDouble() * (day * 0.8 - 2)]..sort();
    final weights = [for (final m in menu) kDishSeason[season][m]];
    final orders = <List<int>>[];
    for (var i = 0; i < n; i++) {
      final k = 1 + (d >= 4 && r.chance(0.6) ? 1 : 0) + (d >= 8 && r.chance(0.4) ? 1 : 0);
      orders.add([for (var j = 0; j < k; j++) menu[r.weighted(weights)]]);
    }
    final patience = math.max(25.0, 45.0 - 2 * d);
    final probe = DinerPuzzle(d, season, menu, day, arrive, orders, patience, 0, 0);
    final bot = dinerBot(probe);
    final goal = (bot * (d <= 3 ? 0.7 : 0.8)).floor();
    if (goal < 20) return null;
    return DinerPuzzle(d, season, menu, day, arrive, orders, patience, goal, bot);
  }

  @override
  bool check(SPuzzle p) =>
      p is DinerPuzzle && p.menu.length >= 3 && p.orders.length == p.arrive.length && p.goal >= 20 && dinerBot(p) == p.botEarn && p.botEarn >= p.goal;

  @override
  Widget build(SimPlay play) => _DinerView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('served', 'Doyurulan misafir', 'Guests served', scale: 50),
        const GameStat('cooked', 'Pişen yemek', 'Dishes cooked', scale: 50),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('served', 'served', [10, 50, 150]),
        const MissionTemplate('cooked', 'cooked', [20, 100, 300]),
      ];
}

class _DinerView extends StatefulWidget {
  final SimPlay play;
  const _DinerView({required this.play});

  @override
  State<_DinerView> createState() => _DinerViewState();
}

class _DinerViewState extends State<_DinerView> with SimClock<_DinerView> {
  late final DinerPuzzle z = widget.play.puzzle as DinerPuzzle;
  late DinerSim s;
  bool calm = false;
  bool started = false;

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    s = DinerSim(z, patienceMul: calm ? 2 : 1);
    SimPrefs.init().then((_) {
      if (!mounted || started) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        s = DinerSim(z, patienceMul: calm ? 2 : 1);
      });
    });
  }

  void _start() {
    if (started) return;
    setState(() => started = true);
    startLoop(250, _tick);
  }

  void _tick(double dt) {
    if (ended) return;
    final lostBefore = s.lost;
    s.step(dt);
    if (s.lost > lostBefore) play.sfx(Sfx.error);
    if (s.over) _end();
  }

  void _end() {
    if (ended) return;
    ended = true;
    stopLoop();
    final e = s.earned.floor();
    final stats = {'served': s.served, 'cooked': s.cooked};
    if (e >= z.goal) {
      play.sfx(Sfx.win);
      final stars = e >= z.botEarn ? 3 : (e >= (z.goal + z.botEarn) ~/ 2 ? 2 : 1);
      play.win(stars: stars, calm: calm, score: e, seconds: seconds, stats: stats);
    } else {
      play.sfx(Sfx.lose);
      play.lose(score: e, seconds: seconds, stats: stats);
    }
  }

  void _cook(int dish) {
    if (ended || !started) return;
    setState(() => play.sfx(s.cook(dish) ? Sfx.place : Sfx.error));
  }

  void _serve(int seat) {
    if (ended || !started) return;
    setState(() {
      if (s.deliver(seat)) {
        play.sfx(s.seats[seat] == null ? Sfx.coin : Sfx.tap);
      } else {
        play.sfx(Sfx.error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scene = LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      return Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _DinerPainter(s, z.season))),
        for (var i = 0; i < 4; i++)
          Positioned(
            left: (i % 2) * w / 2 + 6,
            top: (i ~/ 2) * h * 0.36 + 6,
            width: w / 2 - 12,
            height: h * 0.34,
            child: _seat(i),
          ),
        Positioned(
          left: 6,
          right: 6,
          bottom: 6,
          height: h * 0.22,
          child: _pass(),
        ),
        if (!started)
          Positioned.fill(
            child: Center(
              child: FilledButton.icon(onPressed: _start, icon: const Icon(Icons.storefront), label: Text(st(lang, 'open'))),
            ),
          ),
      ]);
    });
    return SimFrame(
      play: play,
      moneyIcon: Icons.payments,
      money: fmtNum(s.earned),
      sub: '${st(lang, 'served')} ${s.served} · ${st(lang, 'lost')} ${s.lost}',
      goalText: '${st(lang, 'target')} ${z.goal} · ${clock(math.max(0, (z.day - s.t).ceil()))}',
      progress: s.earned / z.goal,
      season: z.season,
      calm: calm,
      onCalm: (v) {
        if (started) return;
        setState(() {
          calm = v;
          SimPrefs.calm = v;
          s = DinerSim(z, patienceMul: v ? 2 : 1);
        });
      },
      sceneFlex: 6,
      panelFlex: 3,
      scene: scene,
      panel: _menuBar(),
    );
  }

  Widget _seat(int i) {
    final g = s.seats[i];
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: g == null ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: g == null ? null : () => _serve(i),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: g == null
              ? const Center(child: Icon(Icons.chair_alt, color: Colors.black26, size: 30))
              : Column(children: [
                  Row(children: [
                    Text(['🙂', '😊', '🧑', '👵', '👴', '🧔', '👩', '👨'][g.id % 8], style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: clampD(g.patience / g.full, 0, 1),
                          minHeight: 7,
                          color: g.patience / g.full < 0.3 ? const Color(0xFFC8553D) : scheme.primary,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Expanded(
                    child: FittedBox(
                      child: Text(g.want.map((d) => kDishEmoji[d]).join(' '), style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }

  Widget _pass() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StudioLook.of(context).accent.withValues(alpha: 0.45), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        const Icon(Icons.room_service, size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: FittedBox(
            alignment: AlignmentDirectional.centerStart,
            fit: BoxFit.scaleDown,
            child: Text(
              [
                ...s.ready.map((d) => kDishEmoji[d]),
                ...s.cooking.map((c) => '⏳${kDishEmoji[c.$1]}${c.$2.ceil()}'),
              ].join('  '),
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _menuBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        // Büyük yazıda kutu yazıyla birlikte uzar (ad ve süre kesilmez).
        childAspectRatio: 2.1 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
        children: [
          for (final d in z.menu)
            SChip(
              onTap: () => _cook(d),
              selected: s.cooking.any((c) => c.$1 == d),
              child: Row(children: [
                Text(kDishEmoji[d], style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(st(lang, kDishKeys[d]), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    Row(children: [
                      Icon(kStationIcons[kDishes[d].$1], size: 12),
                      Flexible(
                        child: Text(' ${kDishes[d].$2.round()}s · ${kDishes[d].$3}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: const TextStyle(fontSize: 11)),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _DinerPainter extends CustomPainter {
  final DinerSim s;
  final int season;
  _DinerPainter(this.s, this.season);

  @override
  void paint(Canvas c, Size size) {
    final look = kSeasonLooks[season];
    final rect = Offset.zero & size;
    c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)), fill(const Color(0xFFEFD9B4)));
    // karo zemin
    for (var y = 0.0; y < size.height; y += 26) {
      for (var x = ((y ~/ 26) % 2) * 26.0; x < size.width; x += 52) {
        c.drawRect(Rect.fromLTWH(x, y, 26, 26), fill(const Color(0x14000000)));
      }
    }
    // pencere: mevsim
    final win = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.36), width: size.width * 0.18, height: size.height * 0.14);
    c.drawRect(win, fill(look.skyTop));
    c.drawRect(Rect.fromLTWH(win.left, win.bottom - 6, win.width, 6), fill(look.ground));
    c.drawRect(win, stroke(const Color(0xFF8A6A4A), 3));
    for (var i = 0; i < 4; i++) {
      c.drawCircle(Offset(win.left + 6 + i * win.width / 4, win.top + 5 + (i % 2) * 6), 2, fill(look.accent));
    }
  }

  @override
  bool shouldRepaint(covariant _DinerPainter old) => true;
}
