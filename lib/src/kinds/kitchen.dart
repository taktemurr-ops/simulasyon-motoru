import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

// =================================================================== Mutfak (yemek yapma: sırala ve pişir)

const List<String> kIngEmoji = ['🍅', '🥒', '🌶️', '🥔', '🥕', '🍚', '🍝', '🌽', '🥚', '🌾', '🥛', '🧀', '🍄', '🍎', '🍓', '🍋'];
const List<String> kActKeys = ['aWash', 'aChop', 'aGrate', 'aBoil', 'aSaute', 'aBake', 'aMix', 'aPlate'];
const List<IconData> kActIcons = [
  Icons.water_drop,
  Icons.content_cut,
  Icons.grid_on,
  Icons.soup_kitchen,
  Icons.local_fire_department,
  Icons.bakery_dining,
  Icons.blender,
  Icons.restaurant,
];
const List<String> kDishTypeEmoji = ['🍲', '🥗', '🍚', '🍝', '🍳', '🥘', '🍰', '🥤'];
const List<String> kDishTypeKeys = ['kSoup', 'kSalad', 'kPilaf', 'kPasta', 'kOmelette', 'kOvenVeg', 'kCake', 'kLemonade'];

class Act {
  static const wash = 0, chop = 1, grate = 2, boil = 3, saute = 4, bake = 5, mix = 6, plate = 7;
}

class KStep {
  final int act;
  final int ing;
  final List<int> deps;
  const KStep(this.act, this.ing, this.deps);

  bool get timed => act == Act.boil || act == Act.saute || act == Act.bake;
}

class Recipe {
  final int type;
  final List<KStep> steps;
  const Recipe(this.type, this.steps);
}

class KitchenPuzzle extends SPuzzle {
  final int d;
  final int season;
  final List<Recipe> dishes;
  final List<List<int>> shuffled;
  final double zone;
  final double speed;
  const KitchenPuzzle(this.d, this.season, this.dishes, this.shuffled, this.zone, this.speed);
}

/// Mevsimin öne çıkan malzemeleri (ilkbahar çilek, yaz domates, sonbahar
/// mantar-elma, kış patates-havuç).
const List<List<int>> kIngSeason = [
  [14, 1, 4, 8],
  [0, 1, 2, 7],
  [12, 13, 4, 3],
  [3, 4, 15, 10],
];

class _RB {
  final List<KStep> s = [];
  int add(int act, int ing, [List<int> deps = const []]) {
    s.add(KStep(act, ing, List<int>.of(deps)));
    return s.length - 1;
  }

  /// Malzemeyi hazırlar: yıka (gerekiyorsa) + doğra/rendele.
  int prep(int ing, {bool wash = true, int cut = Act.chop}) {
    final w = wash ? add(Act.wash, ing) : -1;
    return add(cut, ing, w >= 0 ? [w] : const []);
  }
}

List<int> _pickIngs(SeededRandom r, List<int> pool, int k, int season) {
  final weights = [for (final i in pool) kIngSeason[season].contains(i) ? 3 : 1];
  final out = <int>[];
  var guard = 0;
  while (out.length < k && guard++ < 60) {
    final i = pool[r.weighted(weights)];
    if (!out.contains(i)) out.add(i);
  }
  return out;
}

Recipe makeRecipe(int type, int d, SeededRandom r, int season) {
  final b = _RB();
  final extra = d >= 6 ? 1 : 0;
  switch (type) {
    case 0:
      final veg = _pickIngs(r, const [0, 3, 4, 7, 12, 2], 2 + extra, season);
      final cuts = [for (final v in veg) b.prep(v)];
      final boil = b.add(Act.boil, -1, cuts);
      final mix = b.add(Act.mix, -1, [boil]);
      b.add(Act.plate, -1, [mix]);
    case 1:
      final veg = _pickIngs(r, const [0, 1, 2, 4, 11, 13], 3 + extra, season);
      final cuts = [
        for (final v in veg) b.prep(v, wash: v != 11, cut: v == 4 || v == 11 ? Act.grate : Act.chop),
      ];
      if (r.chance(0.5)) cuts.add(b.prep(15));
      final mix = b.add(Act.mix, -1, cuts);
      b.add(Act.plate, -1, [mix]);
    case 2:
      final rice = b.add(Act.wash, 5);
      final veg = _pickIngs(r, const [2, 4, 12, 7], 1 + extra, season);
      final cuts = [for (final v in veg) b.prep(v)];
      final saute = b.add(Act.saute, -1, cuts);
      final boil = b.add(Act.boil, 5, [rice, saute]);
      b.add(Act.plate, -1, [boil]);
    case 3:
      final boil = b.add(Act.boil, 6);
      final veg = _pickIngs(r, const [0, 12, 2], 1 + extra, season);
      final cuts = [for (final v in veg) b.prep(v)];
      final saute = b.add(Act.saute, -1, cuts);
      final cheese = b.add(Act.grate, 11);
      final mix = b.add(Act.mix, -1, [boil, saute]);
      b.add(Act.plate, -1, [mix, cheese]);
    case 4:
      final whisk = b.add(Act.mix, 8);
      final veg = _pickIngs(r, const [0, 2, 12, 11], 1 + extra, season);
      final cuts = [for (final v in veg) b.prep(v, wash: v != 11, cut: v == 11 ? Act.grate : Act.chop)];
      final saute = b.add(Act.saute, -1, cuts);
      final cook = b.add(Act.saute, 8, [whisk, saute]);
      b.add(Act.plate, -1, [cook]);
    case 5:
      final veg = _pickIngs(r, const [3, 4, 0, 2, 12, 7], 3 + extra, season);
      final cuts = [for (final v in veg) b.prep(v)];
      final mix = b.add(Act.mix, -1, cuts);
      final bake = b.add(Act.bake, -1, [mix]);
      b.add(Act.plate, -1, [bake]);
    case 6:
      final egg = b.add(Act.mix, 8);
      final flour = b.add(Act.mix, 9, [egg]);
      final milk = b.add(Act.mix, 10, [flour]);
      final fruit = r.chance(0.5) ? 13 : 14;
      final cut = b.prep(fruit);
      final batter = b.add(Act.mix, -1, [milk, cut]);
      final bake = b.add(Act.bake, -1, [batter]);
      b.add(Act.plate, -1, [bake]);
    default:
      final lemon = b.prep(15);
      final fruit = b.prep(r.chance(0.5) ? 14 : 13);
      final mix = b.add(Act.mix, -1, [lemon, fruit]);
      b.add(Act.plate, -1, [mix]);
  }
  return Recipe(type, b.s);
}

/// Adımların bağımlılıkları çevrimsiz ve en az bir geçerli sıra var mı.
bool recipeOk(Recipe rc) {
  final n = rc.steps.length;
  if (n < 3 || n > 18) return false;
  final done = List<bool>.filled(n, false);
  for (var round = 0; round < n; round++) {
    var progressed = false;
    for (var i = 0; i < n; i++) {
      if (done[i]) continue;
      if (rc.steps[i].deps.every((j) => j >= 0 && j < n && done[j])) {
        done[i] = true;
        progressed = true;
        break;
      }
    }
    if (!progressed) return false;
  }
  return done.every((x) => x) && rc.steps.last.act == Act.plate;
}

class KitchenKind extends SimKind {
  @override
  String get id => 'mutfak';
  const KitchenKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final season = r.nextInt(4);
    final count = 1 + d ~/ 4;
    final types = [0, 1, 2, 3, 4, 5, 6, 7];
    r.shuffle(types);
    final dishes = [for (var i = 0; i < count; i++) makeRecipe(types[i], d, r, season)];
    final shuffled = <List<int>>[];
    for (final rc in dishes) {
      final o = [for (var i = 0; i < rc.steps.length; i++) i];
      r.shuffle(o);
      shuffled.add(o);
    }
    return KitchenPuzzle(d, season, dishes, shuffled, clampD(0.3 - 0.02 * d, 0.1, 0.3), 0.55 + 0.08 * d);
  }

  @override
  bool check(SPuzzle p) =>
      p is KitchenPuzzle &&
      p.dishes.isNotEmpty &&
      p.dishes.length == p.shuffled.length &&
      p.dishes.every(recipeOk) &&
      [for (var i = 0; i < p.dishes.length; i++) p.shuffled[i].length == p.dishes[i].steps.length].every((x) => x);

  @override
  Widget build(SimPlay play) => _KitchenView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('dishes', 'Pişen tarif', 'Recipes cooked', scale: 20),
        const GameStat('perfect_timing', 'Tam kıvamında', 'Perfect timing', scale: 20),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('dishes', 'dishes', [5, 20, 60]),
        const MissionTemplate('timing', 'perfect_timing', [5, 25, 80]),
      ];
}

class _KitchenView extends StatefulWidget {
  final SimPlay play;
  const _KitchenView({required this.play});

  @override
  State<_KitchenView> createState() => _KitchenViewState();
}

class _KitchenViewState extends State<_KitchenView> with SimClock<_KitchenView> {
  late final KitchenPuzzle z = widget.play.puzzle as KitchenPuzzle;
  bool calm = false;
  int dish = 0;
  late List<bool> done;
  int hearts = 3;
  int mistakes = 0;
  int perfect = 0;
  int okTiming = 0;
  int gaugeStep = -1;
  double gt = 0;
  double zoneAt = 0.5;
  int shake = -1;
  String verdict = '';
  final math.Random _rnd = math.Random();

  SimPlay get play => widget.play;
  String get lang => play.lang;
  Recipe get rc => z.dishes[dish];

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    done = List<bool>.filled(rc.steps.length, false);
    SimPrefs.init().then((_) {
      if (mounted) setState(() => calm = play.zenMode || SimPrefs.calm);
    });
    startLoop(50, (dt) {
      if (gaugeStep >= 0) gt += dt;
    });
  }

  double get needle => 0.5 - 0.5 * math.cos(gt * z.speed * 2 * math.pi);

  void _tapStep(int i) {
    if (ended || done[i] || gaugeStep >= 0) return;
    final s = rc.steps[i];
    setState(() {
      if (!s.deps.every((j) => done[j])) {
        _mistake(i);
        return;
      }
      if (s.timed) {
        gaugeStep = i;
        gt = 0;
        zoneAt = 0.25 + _rnd.nextDouble() * 0.5;
        play.sfx(Sfx.tap);
        return;
      }
      _complete(i);
    });
  }

  void _mistake(int i) {
    mistakes++;
    shake = i;
    play.sfx(Sfx.error);
    later(400, () => setState(() => shake = -1));
    if (!calm) {
      hearts--;
      if (hearts <= 0) {
        ended = true;
        stopLoop();
        play.sfx(Sfx.lose);
        play.lose(seconds: seconds, stats: {'dishes': dish, 'perfect_timing': perfect});
      }
    }
  }

  void _stopGauge() {
    if (gaugeStep < 0 || ended) return;
    final dist = (needle - zoneAt).abs();
    setState(() {
      final i = gaugeStep;
      gaugeStep = -1;
      if (dist <= z.zone / 2) {
        perfect++;
        verdict = st(lang, 'perfectCook');
        play.sfx(Sfx.combo);
        _complete(i);
      } else if (dist <= z.zone) {
        okTiming++;
        verdict = st(lang, 'okCook');
        _complete(i);
      } else {
        verdict = st(lang, 'burnt');
        _mistake(i);
      }
    });
  }

  void _complete(int i) {
    done[i] = true;
    play.sfx(Sfx.place);
    if (done.every((x) => x)) {
      if (dish + 1 >= z.dishes.length) {
        ended = true;
        stopLoop();
        play.sfx(Sfx.win);
        final penalty = mistakes * 2 + okTiming;
        final stars = penalty == 0 ? 3 : (penalty <= 2 ? 2 : 1);
        play.win(stars: stars, calm: calm, score: 1000 - penalty * 50 + perfect * 30, seconds: seconds, stats: {
          'dishes': z.dishes.length,
          'perfect_timing': perfect,
        });
      } else {
        dish++;
        done = List<bool>.filled(rc.steps.length, false);
        verdict = '';
        play.sfx(Sfx.unlock);
      }
    }
  }

  String _stepLabel(KStep s) => st(lang, kActKeys[s.act]);

  String _stepEmoji(KStep s) => s.ing >= 0 ? kIngEmoji[s.ing] : kDishTypeEmoji[rc.type];

  @override
  Widget build(BuildContext context) {
    final order = z.shuffled[dish];
    final scheme = Theme.of(context).colorScheme;
    final timeline = [for (var i = 0; i < rc.steps.length; i++) if (done[i]) i];
    final scene = Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StudioLook.of(context).accent.withValues(alpha: 0.45), width: 1.2),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Row(children: [
          Text(kDishTypeEmoji[rc.type], style: const TextStyle(fontSize: 34)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st(lang, kDishTypeKeys[rc.type]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                {for (final s in rc.steps) if (s.ing >= 0) kIngEmoji[s.ing]}.join(' '),
                style: const TextStyle(fontSize: 18),
              ),
            ]),
          ),
          if (!calm) Text('❤' * hearts, style: const TextStyle(fontSize: 16, color: StudioLook.bad)),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final i in timeline)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SBadge(kActIcons[rc.steps[i].act], _stepEmoji(rc.steps[i]), color: const Color(0xFFDDEFD9)),
              ),
          ]),
        ),
        Expanded(
          child: gaugeStep >= 0
              ? _gauge()
              : Stack(children: [
                  // Mutfak tezgâhı: kiremit duvar, ahşap tezgâh, ocakta tencere
                  // (tarif ilerledikçe dolar ve buharlanır), kesme tahtası.
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CustomPaint(painter: _KitchenScene(rc.steps.isEmpty ? 0 : timeline.length / rc.steps.length, seconds)),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, -0.85),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
                      child: Text(verdict.isEmpty ? st(lang, 'orderHint') : verdict,
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: scheme.onSurface.withValues(alpha: 0.92))),
                    ),
                  ),
                ]),
        ),
      ]),
    );
    final cards = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final i in order)
          if (!done[i])
            AnimatedSlide(
              duration: const Duration(milliseconds: 120),
              offset: shake == i ? const Offset(0.06, 0) : Offset.zero,
              child: SChip(
                onTap: () => _tapStep(i),
                color: rc.steps[i].timed ? const Color(0xFFFFE7CC) : null,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_stepEmoji(rc.steps[i]), style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 4),
                  Icon(kActIcons[rc.steps[i].act], size: 16),
                  const SizedBox(width: 3),
                  Text(_stepLabel(rc.steps[i]), style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
      ]),
    );
    final doneCount = timeline.length;
    var total = 0, before = 0;
    for (var k = 0; k < z.dishes.length; k++) {
      total += z.dishes[k].steps.length;
      if (k < dish) before += z.dishes[k].steps.length;
    }
    return SimFrame(
      play: play,
      moneyIcon: Icons.restaurant_menu,
      money: '${dish + 1}/${z.dishes.length}',
      sub: clock(),
      goalText: '${st(lang, 'recipe')} ${before + doneCount}/$total',
      progress: (before + doneCount) / total,
      season: z.season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      sceneFlex: 5,
      panelFlex: 4,
      scene: scene,
      panel: cards,
    );
  }

  Widget _gauge() {
    final s = rc.steps[gaugeStep];
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_stepEmoji(s), style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 6),
        Icon(kActIcons[s.act]),
        const SizedBox(width: 6),
        Text(_stepLabel(s), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 34,
        child: CustomPaint(size: Size.infinite, painter: _GaugePainter(needle, zoneAt, z.zone)),
      ),
      const SizedBox(height: 10),
      FilledButton(onPressed: _stopGauge, child: Text(st(lang, 'now'))),
    ]);
  }
}

class _GaugePainter extends CustomPainter {
  final double needle;
  final double zoneAt;
  final double zone;
  _GaugePainter(this.needle, this.zoneAt, this.zone);

  @override
  void paint(Canvas c, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(10));
    c.drawRRect(r, fill(const Color(0xFFE8A598)));
    final ok = Rect.fromLTWH((zoneAt - zone) * s.width, 0, zone * 2 * s.width, s.height);
    c.drawRect(ok, fill(const Color(0xFFF2D06B)));
    final good = Rect.fromLTWH((zoneAt - zone / 2) * s.width, 0, zone * s.width, s.height);
    c.drawRect(good, fill(const Color(0xFF7FB069)));
    final x = needle * s.width;
    c.drawLine(Offset(x, -2), Offset(x, s.height + 2), stroke(const Color(0xFF22303F), 4));
    c.drawRRect(r, stroke(const Color(0x55000000), 1.5));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => true;
}

/// Yemek yapma sahnesi (süs): tarifin ilerleyişini tencerede gösterir.
class _KitchenScene extends CustomPainter {
  final double progress;
  final int seconds;
  _KitchenScene(this.progress, this.seconds);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    // Duvar: krem kiremitler.
    c.drawRect(Offset.zero & s, fill(const Color(0xFFF3E9DA)));
    final tile = stroke(const Color(0x22000000), 1);
    final ts = math.max(18.0, w / 12);
    for (var y = 0.0; y < h * 0.62; y += ts) {
      c.drawLine(Offset(0, y), Offset(w, y), tile);
    }
    for (var x = 0.0; x < w; x += ts) {
      c.drawLine(Offset(x, 0), Offset(x, h * 0.62), tile);
    }
    // Raf ve kavanozlar.
    c.drawRect(Rect.fromLTWH(w * 0.08, h * 0.34, w * 0.4, 6), fill(const Color(0xFF9C6B3F)));
    for (var k = 0; k < 3; k++) {
      final jx = w * (0.12 + k * 0.12);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(jx, h * 0.34 - 26, 18, 26), const Radius.circular(4)),
          fill([const Color(0xFFE9C46A), const Color(0xFFC8553D), const Color(0xFF6B9080)][k]));
    }
    // Tezgâh.
    final top = h * 0.62;
    c.drawRect(Rect.fromLTWH(0, top, w, h - top), fill(const Color(0xFFB07B4F)));
    c.drawRect(Rect.fromLTWH(0, top, w, 8), fill(const Color(0xFF8A5A33)));
    // Kesme tahtası ve bıçak.
    final board = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, top + 14, w * 0.34, (h - top) * 0.42), const Radius.circular(8));
    c.drawRRect(board, fill(const Color(0xFFE0B887)));
    c.drawLine(Offset(w * 0.14, top + 24), Offset(w * 0.34, top + 24), stroke(const Color(0xFFB0BEC5), 4));
    // Ocak ve tencere.
    final cx = w * 0.7, base = top + 6;
    c.drawRect(Rect.fromCenter(center: Offset(cx, base + 4), width: w * 0.36, height: 10), fill(const Color(0xFF37474F)));
    final pot = Rect.fromCenter(center: Offset(cx, base - h * 0.09), width: w * 0.26, height: h * 0.17);
    c.drawRRect(RRect.fromRectAndRadius(pot, const Radius.circular(10)), fill(const Color(0xFF78909C)));
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      final f = Rect.fromLTRB(pot.left + 5, pot.bottom - (pot.height - 10) * p - 5, pot.right - 5, pot.bottom - 5);
      c.drawRRect(RRect.fromRectAndRadius(f, const Radius.circular(6)), fill(const Color(0xFFF4A261)));
      // Buhar.
      for (var k = 0; k < 3; k++) {
        final sx = pot.left + pot.width * (0.25 + k * 0.25);
        final ph = (seconds + k) % 3;
        c.drawCircle(Offset(sx, pot.top - 10 - ph * 8.0), 6 + ph * 2.0, fill(Colors.white.withValues(alpha: 0.45 - ph * 0.12)));
      }
    }
    c.drawRect(Rect.fromLTWH(pot.left - 8, pot.top, 8, 6), fill(const Color(0xFF546E7A)));
    c.drawRect(Rect.fromLTWH(pot.right, pot.top, 8, 6), fill(const Color(0xFF546E7A)));
  }

  @override
  bool shouldRepaint(covariant _KitchenScene old) => old.progress != progress || old.seconds != seconds;
}
