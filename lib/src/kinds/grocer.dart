import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

// =================================================================== Mahalle Bakkalı (dükkân işletme)

/// Ürünler: (toptan fiyat, satış fiyatı). Markasız, kodla çizilen ürünler.
const List<(int, int)> kGoods = [
  (2, 4), // ekmek
  (3, 5), // süt
  (4, 7), // yumurta
  (3, 6), // çay
  (2, 4), // elma
  (3, 6), // sabun
  (4, 8), // pirinç
  (1, 3), // şeker
  (5, 9), // peynir
  (1, 2), // su
];
const List<String> kGoodEmoji = ['🍞', '🥛', '🥚', '🍵', '🍎', '🧼', '🍚', '🍬', '🧀', '💧'];
const List<String> kGoodKeys = ['bBread', 'bMilk', 'bEggs', 'bTea', 'bApple', 'bSoap', 'bRice', 'bCandy', 'bCheese', 'bWater'];

/// Mevsime göre talep ağırlıkları (yazın su ve elma, kışın çay ve süt).
const List<List<int>> kGoodSeason = [
  [4, 3, 3, 2, 3, 2, 2, 3, 2, 3],
  [4, 2, 2, 1, 5, 2, 2, 3, 2, 6],
  [4, 3, 3, 3, 4, 2, 3, 3, 3, 2],
  [4, 5, 3, 6, 2, 3, 3, 3, 3, 1],
];

const int kShopSlots = 4;
const double kRestockCd = 1.2;
const double kCheckoutCd = 0.7;

class GrocerPuzzle extends SPuzzle {
  final int d;
  final int season;
  final List<int> goods;
  final int cap;
  final int cash0;
  final double day;
  final List<double> arrive;
  final List<List<int>> lists;
  final double patience;
  final int goal;
  final int botEarn;
  const GrocerPuzzle(this.d, this.season, this.goods, this.cap, this.cash0, this.day, this.arrive, this.lists, this.patience, this.goal,
      this.botEarn);
}

class Shopper {
  final int id;
  final List<int> want;
  final List<int> basket = [];
  double patience;
  final double full;
  double pickT = 0;
  Shopper(this.id, this.want, this.patience) : full = patience;

  bool get done => want.isEmpty;
}

class GrocerSim {
  final GrocerPuzzle z;
  final double patienceMul;
  late final List<int> shelf;
  late int cap;
  double cash;
  final List<Shopper> aisle = [];
  final List<Shopper> queue = [];
  double t = 0;
  int next = 0;
  int served = 0;
  int lost = 0;
  int restocks = 0;
  int upgrades = 0;
  double restockCd = 0;
  double checkoutCd = 0;

  GrocerSim(this.z, {this.patienceMul = 1}) : cash = z.cash0.toDouble() {
    shelf = List<int>.filled(z.goods.length, 2);
    cap = z.cap;
  }

  double get earned => cash - z.cash0;

  bool get over => t > z.day + 60 || (t >= z.day && next >= z.arrive.length && aisle.isEmpty && queue.isEmpty);

  int restockCost(int i) => (cap - shelf[i]) * kGoods[z.goods[i]].$1;

  int get upgradeCost => 30 + 30 * upgrades;

  bool canRestock(int i) => restockCd <= 0 && shelf[i] < cap && cash >= restockCost(i);

  bool restock(int i) {
    if (!canRestock(i)) return false;
    cash -= restockCost(i);
    shelf[i] = cap;
    restocks++;
    restockCd = kRestockCd;
    return true;
  }

  bool upgrade() {
    if (upgrades >= 2 || cash < upgradeCost) return false;
    cash -= upgradeCost;
    upgrades++;
    cap += 3;
    return true;
  }

  bool checkout() {
    if (checkoutCd > 0 || queue.isEmpty) return false;
    final s = queue.removeAt(0);
    var sum = 0.0;
    for (final g in s.basket) {
      sum += kGoods[z.goods[g]].$2;
    }
    cash += sum * (1 + 0.2 * math.max(0.0, s.patience) / s.full);
    served++;
    checkoutCd = kCheckoutCd;
    return true;
  }

  /// Raflardan herkesin istediği eksik ürünlerin sayısı.
  int demand(int i) {
    var n = 0;
    for (final s in aisle) {
      for (final g in s.want) {
        if (g == i) n++;
      }
    }
    return n;
  }

  void step(double dt) {
    while (next < z.arrive.length && z.arrive[next] <= t) {
      aisle.add(Shopper(next, List<int>.of(z.lists[next]), z.patience * patienceMul));
      next++;
    }
    while (aisle.length > kShopSlots) {
      aisle.removeLast();
      lost++;
    }
    final left = <Shopper>[];
    for (final s in aisle) {
      s.pickT -= dt;
      if (s.pickT <= 0 && s.want.isNotEmpty) {
        final g = s.want.first;
        if (shelf[g] > 0) {
          shelf[g]--;
          s.want.removeAt(0);
          s.basket.add(g);
          s.pickT = 0.8;
        } else {
          s.patience -= dt;
        }
      }
      if (s.done) {
        queue.add(s);
        left.add(s);
      } else if (s.patience <= 0) {
        // Ürünleri rafa geri koyup çıkar.
        for (final g in s.basket) {
          shelf[g] = math.min(cap, shelf[g] + 1);
        }
        lost++;
        left.add(s);
      }
    }
    aisle.removeWhere(left.contains);
    for (final s in List<Shopper>.of(queue)) {
      s.patience -= dt * 0.6;
      if (s.patience <= 0) {
        queue.remove(s);
        for (final g in s.basket) {
          shelf[g] = math.min(cap, shelf[g] + 1);
        }
        lost++;
      }
    }
    restockCd -= dt;
    checkoutCd -= dt;
    t += dt;
  }

  /// Bot: önce kasa, yoksa en çok aranan boş rafı doldur.
  void botAct() {
    if (checkout()) return;
    var best = -1, bestNeed = 0;
    for (var i = 0; i < shelf.length; i++) {
      final need = demand(i) - shelf[i];
      if (need > bestNeed && canRestock(i)) {
        best = i;
        bestNeed = need;
      }
    }
    if (best >= 0) {
      restock(best);
      return;
    }
    for (var i = 0; i < shelf.length; i++) {
      if (shelf[i] == 0 && canRestock(i)) {
        restock(i);
        return;
      }
    }
  }
}

int grocerBot(GrocerPuzzle z) {
  final s = GrocerSim(z);
  while (!s.over) {
    s.step(0.25);
    s.botAct();
  }
  return s.earned.floor();
}

class GrocerKind extends SimKind {
  @override
  String get id => 'bakkal';
  const GrocerKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final season = r.nextInt(4);
    final all = [for (var i = 0; i < kGoods.length; i++) i];
    r.shuffle(all);
    final goods = (all.take(4 + d ~/ 2).toList()..sort());
    final day = 80.0 + 10 * d;
    final n = 8 + 2 * d;
    final arrive = [for (var i = 0; i < n; i++) 2 + r.nextDouble() * (day * 0.85 - 2)]..sort();
    final weights = [for (final g in goods) kGoodSeason[season][g]];
    final lists = <List<int>>[];
    for (var i = 0; i < n; i++) {
      final k = 1 + r.nextInt(2) + (d >= 5 && r.chance(0.5) ? 1 : 0) + (d >= 8 && r.chance(0.4) ? 1 : 0);
      lists.add([for (var j = 0; j < k; j++) r.weighted(weights)]);
    }
    final patience = math.max(14.0, 26.0 - d);
    final cap = 4 + (d <= 3 ? 1 : 0);
    final cash0 = 40 + 4 * d;
    final probe = GrocerPuzzle(d, season, goods, cap, cash0, day, arrive, lists, patience, 0, 0);
    final bot = grocerBot(probe);
    final goal = (bot * (d <= 3 ? 0.7 : 0.8)).floor();
    if (goal < 15) return null;
    return GrocerPuzzle(d, season, goods, cap, cash0, day, arrive, lists, patience, goal, bot);
  }

  @override
  bool check(SPuzzle p) =>
      p is GrocerPuzzle &&
      p.goods.length >= 4 &&
      p.lists.length == p.arrive.length &&
      p.lists.every((l) => l.isNotEmpty && l.every((g) => g >= 0 && g < p.goods.length)) &&
      p.goal >= 15 &&
      grocerBot(p) == p.botEarn &&
      p.botEarn >= p.goal;

  @override
  Widget build(SimPlay play) => _GrocerView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('served', 'Ödeme yapan müşteri', 'Customers checked out', scale: 50),
        const GameStat('restocks', 'Doldurulan raf', 'Shelves restocked', scale: 50),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('served', 'served', [10, 50, 150]),
        const MissionTemplate('restocks', 'restocks', [20, 100, 300]),
      ];
}

class _GrocerView extends StatefulWidget {
  final SimPlay play;
  const _GrocerView({required this.play});

  @override
  State<_GrocerView> createState() => _GrocerViewState();
}

class _GrocerViewState extends State<_GrocerView> with SimClock<_GrocerView> {
  late final GrocerPuzzle z = widget.play.puzzle as GrocerPuzzle;
  late GrocerSim s;
  bool calm = false;
  bool started = false;

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    s = GrocerSim(z, patienceMul: calm ? 2 : 1);
    SimPrefs.init().then((_) {
      if (!mounted || started) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        s = GrocerSim(z, patienceMul: calm ? 2 : 1);
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
    final stats = {'served': s.served, 'restocks': s.restocks};
    if (e >= z.goal) {
      play.sfx(Sfx.win);
      final stars = e >= z.botEarn ? 3 : (e >= (z.goal + z.botEarn) ~/ 2 ? 2 : 1);
      play.win(stars: stars, calm: calm, score: e, seconds: seconds, stats: stats);
    } else {
      play.sfx(Sfx.lose);
      play.lose(score: math.max(0, e), seconds: seconds, stats: stats);
    }
  }

  void _restock(int i) {
    if (ended || !started) return;
    setState(() => play.sfx(s.restock(i) ? Sfx.place : Sfx.error));
  }

  void _checkout() {
    if (ended || !started) return;
    setState(() => play.sfx(s.checkout() ? Sfx.coin : Sfx.error));
  }

  void _upgrade() {
    if (ended || !started) return;
    setState(() => play.sfx(s.upgrade() ? Sfx.unlock : Sfx.error));
  }

  @override
  Widget build(BuildContext context) {
    final scene = LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      return Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _GrocerPainter(s, z))),
        for (var i = 0; i < s.aisle.length; i++)
          Positioned(
            left: 6 + i * (w - 12) / kShopSlots,
            top: h * 0.08,
            width: (w - 12) / kShopSlots - 6,
            height: h * 0.40,
            child: _shopper(s.aisle[i]),
          ),
        Positioned(
          left: 6,
          right: 6,
          bottom: 6,
          height: h * 0.34,
          child: _counter(),
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
      money: fmtNum(s.cash),
      sub: '${st(lang, 'bShop')} · ${st(lang, 'served')} ${s.served} · ${st(lang, 'lost')} ${s.lost}',
      goalText: '${st(lang, 'bProfit')} ${fmtNum(math.max(0, s.earned))} / ${z.goal} · ${clock(math.max(0, (z.day - s.t).ceil()))}',
      progress: s.earned / z.goal,
      season: z.season,
      calm: calm,
      onCalm: (v) {
        if (started) return;
        setState(() {
          calm = v;
          SimPrefs.calm = v;
          s = GrocerSim(z, patienceMul: v ? 2 : 1);
        });
      },
      sceneFlex: 5,
      panelFlex: 4,
      scene: scene,
      panel: _shelves(),
    );
  }

  Widget _shopper(Shopper p) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(4),
      child: Column(children: [
        Text(['🙂', '👵', '🧑', '👴', '👩', '🧔', '👧', '👨'][p.id % 8], style: const TextStyle(fontSize: 22)),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: clampD(p.patience / p.full, 0, 1),
            minHeight: 6,
            color: p.patience / p.full < 0.3 ? const Color(0xFFC8553D) : scheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: FittedBox(
            child: Text(p.want.map((g) => kGoodEmoji[z.goods[g]]).join(' '),
                style: const TextStyle(fontSize: 20, color: Color(0xFF22303F))),
          ),
        ),
      ]),
    );
  }

  Widget _counter() {
    final look = StudioLook.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: look.accent.withValues(alpha: 0.45), width: 1.2),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(children: [
        Expanded(
          child: FittedBox(
            alignment: AlignmentDirectional.centerStart,
            fit: BoxFit.scaleDown,
            child: Text(
              s.queue.isEmpty ? '🧺' : s.queue.map((p) => '🧺${p.basket.length}').join('  '),
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: s.queue.isEmpty ? null : _checkout,
          icon: const Icon(Icons.point_of_sale),
          label: Text('${st(lang, 'bCheckout')} (${s.queue.length})'),
        ),
      ]),
    );
  }

  Widget _shelves() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(children: [
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            // Büyük yazıda kutu yazıyla birlikte uzar (ad ve stok kesilmez).
            childAspectRatio: 2.1 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
            children: [
              for (var i = 0; i < z.goods.length; i++)
                SChip(
                  onTap: () => _restock(i),
                  selected: s.shelf[i] == 0,
                  tooltip: st(lang, 'bRestock'),
                  child: Row(children: [
                    Text(kGoodEmoji[z.goods[i]], style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(st(lang, kGoodKeys[z.goods[i]]),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        Text('${s.shelf[i]}/${s.cap} · ${s.restockCost(i)}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SNote(
          s.upgrades >= 2 ? st(lang, 'max') : '${st(lang, 'bShelfUp')} · ${s.upgradeCost}',
          icon: Icons.add_business,
          onTap: s.upgrades >= 2 ? null : _upgrade,
        ),
      ]),
    );
  }
}

class _GrocerPainter extends CustomPainter {
  final GrocerSim s;
  final GrocerPuzzle z;
  _GrocerPainter(this.s, this.z);

  @override
  void paint(Canvas c, Size size) {
    final look = kSeasonLooks[z.season];
    final rect = Offset.zero & size;
    c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)), fill(const Color(0xFFF3E3C3)));
    // tente
    final stripe = size.width / 10;
    for (var i = 0; i < 10; i++) {
      c.drawRect(Rect.fromLTWH(i * stripe, 0, stripe, size.height * 0.06),
          fill(i.isEven ? const Color(0xFF2F8F6B) : const Color(0xFFF5F1E6)));
    }
    // arka raflar ve ürünler
    final shelfTop = size.height * 0.50;
    c.drawRect(Rect.fromLTWH(8, shelfTop - 4, size.width - 16, 4), fill(const Color(0xFF8A6A4A)));
    final n = z.goods.length;
    for (var i = 0; i < n; i++) {
      final x = 14 + i * (size.width - 28) / n;
      final cnt = s.shelf[i];
      for (var k = 0; k < math.min(cnt, 6); k++) {
        drawLabel(c, kGoodEmoji[z.goods[i]], Offset(x + 6 + (k % 3) * 6.0, shelfTop - 12 - (k ~/ 3) * 9.0), 10, Colors.black);
      }
    }
    // pencere: mevsim
    final win = Rect.fromLTWH(size.width * 0.78, size.height * 0.56, size.width * 0.16, size.height * 0.08);
    c.drawRect(win, fill(look.skyTop));
    c.drawRect(win, stroke(const Color(0xFF8A6A4A), 2));
  }

  @override
  bool shouldRepaint(covariant _GrocerPainter old) => true;
}
