import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../economy.dart';
import '../texts.dart';

/// Üretici simgeleri (renkli emoji; eski cihazlarda da bulunan sürümler).
const Map<int, List<String>> kIdleEmoji = {
  IdleTheme.lantern: ['🕯️', '🏮', '💡', '🛠️', '🏘️', '🎆'],
  IdleTheme.mine: ['⛏️', '👷', '⚙️', '💎', '🏔️', '🔮'],
  IdleTheme.factory: ['🔨', '✂️', '🎨', '🧸', '🚂', '🤖'],
  IdleTheme.farm: ['🌾', '🍅', '🎃', '🌻', '🍓', '🍎'],
  IdleTheme.aquarium: ['🐟', '🐠', '🐡', '🦐', '🐢', '🐙'],
  IdleTheme.zen: ['🌿', '🎋', '🏮', '🌳', '🐟', '⛲'],
  IdleTheme.bee: ['🐝', '🌼', '🏡', '🍯', '🌸', '👑'],
  IdleTheme.tea: ['🍵', '☕', '🥨', '⛱️', '🎶', '🌳'],
};

const Map<int, IconData> kIdleMoney = {
  IdleTheme.lantern: Icons.local_fire_department,
  IdleTheme.mine: Icons.terrain,
  IdleTheme.factory: Icons.toys,
  IdleTheme.farm: Icons.agriculture,
  IdleTheme.aquarium: Icons.water_drop,
  IdleTheme.zen: Icons.spa,
  IdleTheme.bee: Icons.hive,
  IdleTheme.tea: Icons.emoji_food_beverage,
};

class IdleKind extends SimKind {
  final String kindId;
  final int theme;
  const IdleKind(this.kindId, this.theme);

  @override
  String get id => kindId;

  @override
  SPuzzle? make(int d, SeededRandom r) => makeIdle(theme, d, r);

  @override
  bool check(SPuzzle p) => p is IdlePuzzle && p.theme == theme && checkIdle(p);

  @override
  Widget build(SimPlay play) => IdleView(play: play, theme: theme);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('prestige', 'Yeniden kurma', 'Fresh starts', scale: 2),
        const GameStat('upgrades', 'Alınan geliştirme', 'Upgrades bought', scale: 20),
        const GameStat('taps', 'Dokunuş', 'Taps', scale: 200),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('upg', 'upgrades', [5, 20, 60]),
        const MissionTemplate('taps', 'taps', [100, 500, 2000]),
        const MissionTemplate('prestige', 'prestige', [1, 3, 8]),
      ];
}

String idleName(String lang, int theme, int k, IdlePuzzle z) =>
    st(lang, z.bottle && k == z.p - 1 ? 'i${theme}_c' : 'i${theme}_$k');

String idleEmoji(int theme, int k, IdlePuzzle z) => z.bottle && k == z.p - 1 ? '⬆️' : kIdleEmoji[theme]![k % 6];

double numOf(Object? v, double def) => v is num ? v.toDouble() : def;
int intOf(Object? v, int def) => v is num ? v.toInt() : def;
List<int> intsOf(Object? v, int len) {
  final out = List<int>.filled(len, 0);
  if (v is List) {
    for (var i = 0; i < len && i < v.length; i++) {
      out[i] = intOf(v[i], 0);
    }
  }
  return out;
}

class IdleView extends StatefulWidget {
  final SimPlay play;
  final int theme;
  const IdleView({super.key, required this.play, required this.theme});

  @override
  State<IdleView> createState() => _IdleViewState();
}

class _Float {
  final Offset at;
  final double born;
  final String text;
  const _Float(this.at, this.born, this.text);
}

class _IdleViewState extends State<IdleView> with SimClock<IdleView> {
  late final IdlePuzzle z = widget.play.puzzle as IdlePuzzle;
  late final Econ e = Econ(z);
  final math.Random _rnd = math.Random();
  bool calm = false;
  int buyMode = 0;
  double combo = 1;
  int taps = 0;
  int eventIdx = 0;
  double eventUntil = -1;
  double boostUntil = -1;
  double rakeUntil = -1;
  double nextBud = 15;
  final List<Offset> buds = [];
  final List<List<Offset>> rake = [];
  final List<_Float> floats = [];
  String note = '';
  double noteUntil = -1;
  double saveIn = 5;
  double armUntil = -1;

  SimPlay get play => widget.play;
  String get lang => play.lang;
  int get theme => widget.theme;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    e.extra = SimPrefs.renownMul(play.gameId);
    _restore();
    SimPrefs.init().then((_) {
      if (!mounted) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        e.extra = SimPrefs.renownMul(play.gameId);
      });
    });
    startLoop(200, _tick);
  }

  void _restore() {
    final m = play.restored;
    if (m.isEmpty) return;
    e.n = intsOf(m['n'], z.p);
    final b = intsOf(m['b'], z.upg.length);
    e.bought = [for (final x in b) x == 1];
    e.refresh();
    e.coins = numOf(m['coins'], 15);
    e.runEarned = numOf(m['run'], 0);
    e.levelEarned = numOf(m['lvl'], 0);
    e.store = numOf(m['store'], 0);
    e.clean = numOf(m['clean'], 1);
    e.t = numOf(m['t'], 0);
    e.points = intOf(m['pts'], 0);
    e.prestiges = intOf(m['pre'], 0);
    e.upgrades = intOf(m['upc'], 0);
    e.peakIncome = numOf(m['pi'], 0);
    e.peakOwn = intsOf(m['po'], z.p);
    seconds = intOf(m['sec'], 0);
    taps = intOf(m['taps'], 0);
    eventIdx = intOf(m['ev'], 0);
    final away = play.awaySeconds();
    if (away >= 20) {
      final gain = e.rawOf(e.n) * e.extra * away * 0.5;
      if (z.harvest && !e.auto) {
        e.store = math.min(e.store + gain, e.storeCap);
      } else {
        e.earn(gain);
      }
      if (gain >= 1) {
        note = st(lang, 'offline').replaceAll('{0}', fmtNum(gain));
        noteUntil = e.t + 8;
      }
    }
  }

  void _save() {
    play.save({
      'n': e.n,
      'b': [for (final x in e.bought) x ? 1 : 0],
      'coins': e.coins,
      'run': e.runEarned,
      'lvl': e.levelEarned,
      'store': e.store,
      'clean': e.clean,
      't': e.t,
      'pts': e.points,
      'pre': e.prestiges,
      'upc': e.upgrades,
      'pi': e.peakIncome,
      'po': e.peakOwn,
      'sec': seconds,
      'taps': taps,
      'ev': eventIdx,
    });
  }

  void _tick(double dt) {
    if (ended) return;
    var b = 1.0;
    if (e.t < boostUntil) b *= 2;
    if (e.t < rakeUntil) b *= 1.5;
    e.boost = b;
    e.step(dt);
    combo = math.max(1.0, combo - dt * 0.6);
    if (!calm && eventIdx < z.events.length && e.t >= z.events[eventIdx]) {
      eventUntil = e.t + 10;
      eventIdx++;
    }
    if (theme == IdleTheme.zen && e.t >= nextBud) {
      if (buds.length < 4) buds.add(Offset(0.18 + _rnd.nextDouble() * 0.34, 0.2 + _rnd.nextDouble() * 0.35));
      nextBud = e.t + 15;
    }
    floats.removeWhere((f) => e.t - f.born > 1.2);
    saveIn -= dt;
    if (saveIn <= 0) {
      saveIn = 5;
      _save();
    }
    if (e.reached) _win();
  }

  void _win() {
    if (ended) return;
    ended = true;
    stopLoop();
    _save();
    play.sfx(Sfx.win);
    play.win(
      stars: starsByTime(seconds, z.par),
      calm: calm,
      score: math.min(e.levelEarned, 1e15).round(),
      seconds: seconds,
      stats: {'prestige': e.prestiges, 'upgrades': e.upgrades, 'taps': taps},
    );
  }

  void _tapScene(Offset p, Size s) {
    if (ended) return;
    setState(() {
      if (theme == IdleTheme.zen) {
        for (var i = 0; i < buds.length; i++) {
          final bp = Offset(buds[i].dx * s.width, buds[i].dy * s.height);
          if ((bp - p).distance < 30) {
            buds.removeAt(i);
            final g = e.income * 10;
            e.earn(g);
            floats.add(_Float(Offset(p.dx / s.width, p.dy / s.height), e.t, '✂ +${fmtNum(g)}'));
            play.sfx(Sfx.coin);
            return;
          }
        }
      }
      if (z.harvest && e.store >= 1) {
        final g = e.store;
        e.collect();
        floats.add(_Float(Offset(p.dx / s.width, p.dy / s.height), e.t, '🧺 +${fmtNum(g)}'));
        play.sfx(Sfx.coin);
        return;
      }
      final mul = theme == IdleTheme.lantern ? combo : 1.0;
      final v = e.tapValue * mul;
      e.earn(v);
      taps++;
      if (theme == IdleTheme.lantern) combo = math.min(3.0, combo + 0.12);
      floats.add(_Float(Offset(p.dx / s.width, p.dy / s.height), e.t, '+${fmtNum(v)}'));
      if (floats.length > 12) floats.removeAt(0);
      play.sfx(Sfx.tap);
    });
  }

  void _rakeAt(Offset p, Size s) {
    if (theme != IdleTheme.zen || ended) return;
    final q = Offset(clampD(p.dx / s.width, 0, 1), clampD(p.dy / s.height, 0, 1));
    if (rake.isEmpty || rake.last.length > 60) {
      rake.add([q]);
      if (rake.length > 14) rake.removeAt(0);
    } else {
      rake.last.add(q);
    }
    if (rake.last.length == 14) {
      rakeUntil = e.t + 20;
      play.sfx(Sfx.combo);
    }
  }

  void _rakeEnd() {
    if (theme != IdleTheme.zen) return;
    rake.add([]);
    if (rake.length > 14) rake.removeAt(0);
  }

  int _count(int k) => switch (buyMode) {
        1 => 10,
        2 => math.max(1, e.affordable(k)),
        _ => 1,
      };

  void _buy(int k) {
    if (ended) return;
    setState(() {
      if (e.buyProducer(k, _count(k))) {
        play.sfx(Sfx.place);
      } else {
        play.sfx(Sfx.error);
      }
    });
  }

  void _upgrade(int i) {
    if (ended) return;
    setState(() {
      if (e.buyUpgrade(i)) {
        play.sfx(Sfx.unlock);
      } else {
        play.sfx(Sfx.error);
      }
    });
  }

  void _prestige() {
    if (ended || e.prestigeGain <= 0) return;
    setState(() {
      if (armUntil < e.t) {
        armUntil = e.t + 3;
        return;
      }
      armUntil = -1;
      e.prestige();
      play.sfx(Sfx.unlock);
      note = st(lang, 'prestigeDone').replaceAll('{0}', '×${(1 + 0.6 * e.points).toStringAsFixed(1)}');
      noteUntil = e.t + 6;
    });
  }

  String _goalText() {
    final g = z.goal;
    return switch (z.goalType) {
      GoalType.income => st(lang, 'goalIncome').replaceAll('{0}', fmtNum(g)),
      GoalType.own => st(lang, 'goalOwn').replaceAll('{0}', g.round().toString()).replaceAll('{1}', idleEmoji(theme, z.goalK, z)),
      _ => st(lang, 'goalEarn').replaceAll('{0}', fmtNum(g)),
    };
  }

  Widget? _banner() {
    if (eventUntil > e.t) {
      return SNote(st(lang, 'event'), icon: Icons.celebration, color: const Color(0xFFFFE7A3), onTap: () {
        setState(() {
          boostUntil = e.t + 15;
          eventUntil = -1;
        });
        play.sfx(Sfx.combo);
      });
    }
    if (noteUntil > e.t && note.isNotEmpty) return SNote(note, icon: Icons.nightlight_round);
    return null;
  }

  Widget _special() {
    final items = <Widget>[];
    if (z.harvest) {
      items.add(SChip(
        onTap: e.store >= 1
            ? () => setState(() {
                  e.collect();
                  play.sfx(Sfx.coin);
                })
            : null,
        child: Text('🧺 ${st(lang, 'harvest')} ${fmtNum(e.store)}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ));
    }
    if (z.cleaning) {
      items.add(SChip(
        onTap: () => setState(() {
          e.clean = 1;
          play.sfx(Sfx.clear);
        }),
        child: Text('🫧 ${st(lang, 'clean')} ${(e.clean * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
      ));
    }
    if (theme == IdleTheme.lantern) {
      items.add(SBadge(Icons.bolt, '${st(lang, 'combo')} ×${combo.toStringAsFixed(1)}'));
    }
    if (z.bottle) {
      items.add(SBadge(Icons.swap_vert, '${fmtNum(math.min(e.prodOf(e.n), e.capOf(e.n[z.p - 1])))} / ${fmtNum(e.capOf(e.n[z.p - 1]))}'));
    }
    if (theme == IdleTheme.zen) {
      items.add(SBadge(Icons.gesture, e.t < rakeUntil ? '×1.5' : st(lang, 'rake')));
    }
    final gain = e.prestigeGain;
    items.add(SChip(
      selected: armUntil > e.t,
      onTap: gain > 0 ? _prestige : null,
      tooltip: st(lang, 'prestigeInfo'),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.autorenew, size: 18),
        const SizedBox(width: 4),
        Text(
          gain > 0
              ? (armUntil > e.t ? st(lang, 'sure') : '${st(lang, 'prestige')} +$gain')
              : '${st(lang, 'prestige')} ${fmtNum(e.runEarned)}/${fmtNum(z.pt)}',
          style: const TextStyle(fontSize: 13),
        ),
      ]),
    ));
    items.add(SChip(
      onTap: () => setState(() => buyMode = (buyMode + 1) % 3),
      child: Text(buyMode == 2 ? st(lang, 'max') : (buyMode == 1 ? '×10' : '×1'), style: const TextStyle(fontWeight: FontWeight.w800)),
    ));
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [for (final w in items) Padding(padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4), child: w)],
      ),
    );
  }

  Widget _upgrades() {
    final open = <int>[for (var i = 0; i < z.upg.length; i++) if (!e.bought[i]) i];
    if (open.isEmpty) return const SizedBox.shrink();
    final show = open.take(8).toList();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final i in show)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
              child: Opacity(
                opacity: z.upg[i].cost <= e.coins ? 1.0 : 0.55,
                child: SChip(
                  onTap: () => _upgrade(i),
                  tooltip: st(lang, 'upgrades'),
                  child: Text('${_upgSymbol(z.upg[i])} ×${_fmtMult(z.upg[i])}  ${fmtNum(z.upg[i].cost)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtMult(Upg u) => u.target == -3 ? 'A' : (u.mult == u.mult.roundToDouble() ? u.mult.round().toString() : u.mult.toString());

  String _upgSymbol(Upg u) => switch (u.target) {
        -1 => '✨',
        -2 => '👆',
        -3 => z.harvest ? '🚜' : '🫧',
        _ => idleEmoji(theme, u.target, z),
      };

  Widget _producer(BuildContext context, int k) {
    final carrier = z.bottle && k == z.p - 1;
    final count = _count(k);
    final cost = e.costMany(k, count);
    final can = cost <= e.coins;
    final scheme = Theme.of(context).colorScheme;
    final next = const [10, 25, 50, 100, 200].firstWhere((m) => m > e.n[k], orElse: () => 0);
    final rate = carrier ? '${st(lang, 'capacity')} ${fmtNum(e.capOf(e.n[k]))}' : '+${fmtNum(z.rate0[k] * e.mult(k, math.max(1, e.n[k])))}${st(lang, 'perSec')}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Text(idleEmoji(theme, k, z), style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${idleName(lang, theme, k, z)} · ${e.n[k]}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(next > 0 ? '$rate · ${e.n[k]}/$next ×2' : rate,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7))),
            ]),
          ),
          const SizedBox(width: 6),
          FilledButton.tonal(
            onPressed: can ? () => _buy(k) : null,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(72, 38)),
            child: Text(count > 1 ? '×$count ${fmtNum(cost)}' : fmtNum(cost), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final season = e.season;
    final scene = SceneCanvas(
      semantics: st(lang, 'tapScene'),
      paint: (c, s) => paintIdle(c, s, theme, z, e, season, combo: combo, buds: buds, rake: rake, calm: calm, event: eventUntil > e.t),
      onTap: _tapScene,
      onPan: theme == IdleTheme.zen ? _rakeAt : null,
      onPanEnd: theme == IdleTheme.zen ? _rakeEnd : null,
    );
    final floatLayer = IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        return Stack(children: [
          for (final f in floats)
            Positioned(
              left: f.at.dx * box.maxWidth - 30,
              top: f.at.dy * box.maxHeight - 20 - (e.t - f.born) * 40,
              child: Opacity(
                opacity: clampD(1.2 - (e.t - f.born), 0, 1),
                child: Text(f.text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white, shadows: [Shadow(blurRadius: 4)])),
              ),
            ),
        ]);
      }),
    );
    return SimFrame(
      play: play,
      moneyIcon: kIdleMoney[theme]!,
      money: fmtNum(e.coins),
      sub: '+${fmtNum(e.income)}${st(lang, 'perSec')}',
      goalText: _goalText(),
      progress: e.progress(),
      season: season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      banner: _banner(),
      actions: [
        if (e.points > 0)
          Padding(padding: const EdgeInsets.only(left: 4), child: SBadge(Icons.auto_awesome, '×${(1 + 0.6 * e.points).toStringAsFixed(1)}')),
      ],
      scene: Stack(fit: StackFit.expand, children: [scene, floatLayer]),
      panel: Column(children: [
        _special(),
        _upgrades(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: z.p,
            itemBuilder: _producer,
          ),
        ),
      ]),
    );
  }
}

// ======================================================================= sahneler

void paintIdle(Canvas c, Size s, int theme, IdlePuzzle z, Econ e, int season,
    {double combo = 1, List<Offset> buds = const [], List<List<Offset>> rake = const [], bool calm = false, bool event = false}) {
  switch (theme) {
    case IdleTheme.lantern:
      _paintLantern(c, s, z, e, season, combo);
    case IdleTheme.mine:
      _paintMine(c, s, z, e, season);
    case IdleTheme.factory:
      _paintFactory(c, s, z, e, season);
    case IdleTheme.farm:
      _paintFarm(c, s, z, e, season);
    case IdleTheme.aquarium:
      _paintAquarium(c, s, z, e, season);
    case IdleTheme.bee:
      _paintBee(c, s, z, e, season);
    case IdleTheme.tea:
      _paintTea(c, s, z, e, season);
    default:
      _paintZen(c, s, z, e, season, buds, rake);
  }
  if (event) {
    final pulse = 0.5 + 0.5 * math.sin(e.t * 6);
    c.drawCircle(Offset(s.width - 34, 34), 18 + pulse * 6, fill(const Color(0xFFFFD166).withValues(alpha: 0.5 + 0.3 * pulse)));
    drawLabel(c, '×2', Offset(s.width - 34, 34), 15, const Color(0xFF5B3A00));
  }
}

int _units(Econ e) => e.n.fold<int>(0, (a, b) => a + b);

void _paintLantern(Canvas c, Size s, IdlePuzzle z, Econ e, int season, double combo) {
  final look = kSeasonLooks[season];
  final rect = Offset.zero & s;
  c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1D2540), Color.lerp(const Color(0xFF3A3F66), look.accent, 0.25)!],
        ).createShader(rect));
  // yıldızlar
  for (var i = 0; i < 26; i++) {
    final x = (i * 73.3) % s.width, y = (i * 41.7) % (s.height * 0.45);
    final a = 0.4 + 0.4 * math.sin(e.t * 1.5 + i);
    c.drawCircle(Offset(x, y), 1.3, fill(Colors.white.withValues(alpha: a)));
  }
  // evler
  final gy = s.height * 0.78;
  for (var i = 0; i < 6; i++) {
    final w = s.width / 6;
    final h = 40.0 + (i * 37) % 50;
    final r = Rect.fromLTWH(i * w + 2, gy - h, w - 4, h);
    c.drawRect(r, fill(const Color(0xFF2B2F4A)));
    final roof = Path()
      ..moveTo(r.left - 2, r.top)
      ..lineTo(r.center.dx, r.top - 18)
      ..lineTo(r.right + 2, r.top)
      ..close();
    c.drawPath(roof, fill(const Color(0xFF3B2F4A)));
    final lit = i < _units(e) ~/ 3 + 1;
    c.drawRect(Rect.fromCenter(center: Offset(r.center.dx, r.top + h * 0.45), width: 12, height: 14),
        fill(lit ? const Color(0xFFFFD27D) : const Color(0xFF454A66)));
  }
  c.drawRect(Rect.fromLTWH(0, gy, s.width, s.height - gy), fill(season == 3 ? const Color(0xFFDDE5EE) : const Color(0xFF4A4458)));
  // ip ve fenerler
  final n = math.min<int>(_units(e), 36);
  final rope = Path()..moveTo(0, s.height * 0.22);
  rope.quadraticBezierTo(s.width / 2, s.height * 0.4, s.width, s.height * 0.22);
  c.drawPath(rope, stroke(const Color(0xFF8A7A6A), 1.5));
  for (var i = 0; i < n; i++) {
    final u = (i + 0.5) / math.max(1, n);
    final x = u * s.width;
    final y = s.height * 0.22 + 4 * u * (1 - u) * s.height * 0.18 + 8;
    final col = HSVColor.fromAHSV(1, (20 + i * 23) % 60.0 + 5, 0.75, 1).toColor();
    c.drawCircle(Offset(x, y), 9, fill(col.withValues(alpha: 0.25)));
    c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 10, height: 13), fill(col));
  }
  // büyük fener
  final cx = s.width / 2, cy = s.height * 0.56;
  final flick = 1 + 0.06 * math.sin(e.t * 9) + 0.04 * math.sin(e.t * 13);
  final glow = 34 + 14 * (combo - 1);
  c.drawCircle(Offset(cx, cy), glow * flick, fill(const Color(0xFFFFB347).withValues(alpha: 0.28)));
  final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: 46, height: 60), const Radius.circular(20));
  c.drawRRect(body, fill(const Color(0xFFE4572E)));
  c.drawRRect(body, stroke(const Color(0xFF7A2E14), 2));
  for (var i = -1; i <= 1; i++) {
    c.drawLine(Offset(cx + i * 12, cy - 28), Offset(cx + i * 12, cy + 28), stroke(const Color(0x667A2E14), 1.2));
  }
  c.drawCircle(Offset(cx, cy + 4), 7 * flick, fill(const Color(0xFFFFE08A)));
  c.drawRect(Rect.fromCenter(center: Offset(cx, cy - 33), width: 22, height: 6), fill(const Color(0xFF3B2F2F)));
  c.drawLine(Offset(cx, cy - 36), Offset(cx, cy - 60), stroke(const Color(0xFF8A7A6A), 1.5));
  paintSeasonParticles(c, s, season, e.t, count: 10);
}

void _paintMine(Canvas c, Size s, IdlePuzzle z, Econ e, int season) {
  paintSky(c, s, season, groundAt: 0.16);
  final top = s.height * 0.16;
  final rect = Rect.fromLTWH(0, top, s.width, s.height - top);
  c.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8B6B4A), Color(0xFF4E3B2C), Color(0xFF2E2420)],
        ).createShader(rect));
  final prods = z.producers;
  final shaftX = 34.0;
  // asansör kuyusu
  c.drawRect(Rect.fromLTWH(shaftX - 12, top - 10, 24, s.height - top + 10), fill(const Color(0xFF1E1814)));
  final cabin = top + (s.height - top - 30) * (0.5 + 0.5 * math.sin(e.t * (0.8 + 0.05 * e.n[z.p - 1])));
  c.drawRect(Rect.fromLTWH(shaftX - 10, cabin, 20, 22), fill(const Color(0xFFD9A441)));
  c.drawLine(Offset(shaftX, top - 10), Offset(shaftX, cabin), stroke(const Color(0xFF999999), 1));
  // galeriler
  final gh = (s.height - top - 10) / prods;
  for (var k = 0; k < prods; k++) {
    final y = top + 8 + k * gh;
    final open = e.n[k] > 0;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(shaftX + 14, y + gh * 0.2, s.width - shaftX - 24, gh * 0.6), const Radius.circular(8));
    c.drawRRect(r, fill(open ? const Color(0xFF3A2C22) : const Color(0xFF5A4636)));
    if (!open) continue;
    final gems = math.min<int>(e.n[k], 10);
    final col = HSVColor.fromAHSV(1, (190 + k * 47) % 360.0, 0.55, 0.95).toColor();
    for (var i = 0; i < gems; i++) {
      final gx = r.left + 20 + (i * 37 + k * 11) % (r.width - 30);
      final gy = r.top + 6 + (i * 13) % math.max(4.0, r.height - 12);
      final tw = 0.6 + 0.4 * math.sin(e.t * 3 + i + k);
      final p = Path()
        ..moveTo(gx, gy)
        ..lineTo(gx + 5, gy + 6)
        ..lineTo(gx, gy + 12)
        ..lineTo(gx - 5, gy + 6)
        ..close();
      c.drawPath(p, fill(col.withValues(alpha: tw)));
    }
    final mx = r.left + 12 + (r.width - 30) * (0.5 + 0.5 * math.sin(e.t * 0.9 + k));
    c.drawCircle(Offset(mx, r.bottom - 10), 6, fill(const Color(0xFFF2C14E)));
    c.drawRect(Rect.fromCenter(center: Offset(mx, r.bottom - 3), width: 8, height: 6), fill(const Color(0xFF2E5E8C)));
  }
}

void _paintFactory(Canvas c, Size s, IdlePuzzle z, Econ e, int season) {
  c.drawRect(Offset.zero & s, fill(const Color(0xFFE9E2D3)));
  // pencereler
  final look = kSeasonLooks[season];
  for (var i = 0; i < 3; i++) {
    final r = Rect.fromLTWH(20 + i * (s.width - 40) / 3, 14, (s.width - 40) / 3 - 14, s.height * 0.22);
    c.drawRect(r, fill(look.skyTop));
    c.drawRect(Rect.fromLTWH(r.left, r.bottom - 8, r.width, 8), fill(look.ground));
    c.drawRect(r, stroke(const Color(0xFF8A7A6A), 3));
  }
  paintSeasonParticles(c, Size(s.width, s.height * 0.26), season, e.t, count: 6);
  // makineler
  final prods = z.producers;
  final mw = (s.width - 20) / prods;
  final my = s.height * 0.36;
  for (var k = 0; k < prods; k++) {
    final x = 10 + k * mw;
    final on = e.n[k] > 0;
    final col = on ? HSVColor.fromAHSV(1, (k * 53 + 10) % 360.0, 0.45, 0.85).toColor() : const Color(0xFFC9C0B0);
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x + 4, my, mw - 8, s.height * 0.26), const Radius.circular(10));
    c.drawRRect(r, fill(col));
    final g = Offset(r.center.dx, r.top + 20);
    c.save();
    c.translate(g.dx, g.dy);
    if (on) c.rotate(e.t * (1 + k * 0.3));
    for (var i = 0; i < 8; i++) {
      c.drawRect(Rect.fromCenter(center: Offset(math.cos(i * math.pi / 4) * 11, math.sin(i * math.pi / 4) * 11), width: 5, height: 5),
          fill(const Color(0xFF5B4636)));
    }
    c.drawCircle(Offset.zero, 9, fill(const Color(0xFF5B4636)));
    c.drawCircle(Offset.zero, 3, fill(col));
    c.restore();
    drawLabel(c, '${e.n[k]}', Offset(r.center.dx, r.bottom - 14), 13, const Color(0xFF2B2B2B));
  }
  // konveyör
  final by = s.height * 0.72;
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6, by, s.width - 12, 22), const Radius.circular(11)), fill(const Color(0xFF4A4A4A)));
  final speed = 20 + 8 * math.log(1 + e.income);
  for (var i = 0; i < 14; i++) {
    final x = (i * 40 + e.t * speed) % (s.width + 40) - 20;
    c.drawLine(Offset(x, by + 4), Offset(x, by + 18), stroke(const Color(0xFF6A6A6A), 2));
  }
  final toys = math.min<int>(_units(e), 9);
  for (var i = 0; i < toys; i++) {
    final x = (i * (s.width / 9) + e.t * speed) % (s.width + 30) - 15;
    final col = HSVColor.fromAHSV(1, (i * 41) % 360.0, 0.6, 0.9).toColor();
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 9, by - 16, 18, 16), const Radius.circular(4)), fill(col));
    c.drawCircle(Offset(x, by - 20), 5, fill(col));
  }
  c.drawRect(Rect.fromLTWH(0, by + 22, s.width, s.height - by - 22), fill(const Color(0xFFBFB3A0)));
}

void _paintFarm(Canvas c, Size s, IdlePuzzle z, Econ e, int season) {
  paintSky(c, s, season, groundAt: 0.3);
  final look = kSeasonLooks[season];
  c.drawCircle(Offset(s.width * 0.85, s.height * 0.1), 16, fill(season == 3 ? const Color(0xFFF2F2F2) : const Color(0xFFFFD166)));
  // ahır
  final barn = Rect.fromLTWH(s.width - 86, s.height * 0.18, 70, 52);
  c.drawRect(barn, fill(const Color(0xFFB5433A)));
  c.drawPath(
      Path()
        ..moveTo(barn.left - 6, barn.top)
        ..lineTo(barn.center.dx, barn.top - 22)
        ..lineTo(barn.right + 6, barn.top)
        ..close(),
      fill(const Color(0xFF7A2E24)));
  c.drawRect(Rect.fromCenter(center: Offset(barn.center.dx, barn.bottom - 14), width: 22, height: 28), fill(const Color(0xFFF3E6D0)));
  final fill01 = e.auto ? 0.8 : clampD(e.store / math.max(1.0, e.storeCap), 0, 1);
  final prods = z.producers;
  final top = s.height * 0.36;
  final rh = (s.height - top - 6) / prods;
  const cropCol = [Color(0xFFE3C567), Color(0xFFD64933), Color(0xFFE88D2A), Color(0xFFF2C14E), Color(0xFFE5446D), Color(0xFFC0392B)];
  for (var k = 0; k < prods; k++) {
    final y = top + k * rh;
    final soil = season == 3 ? const Color(0xFFE8EDF2) : Color.lerp(const Color(0xFF7A5230), look.ground, 0.2)!;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(8, y + 2, s.width - 16, rh - 4), const Radius.circular(6)), fill(soil));
    final plants = math.min<int>(e.n[k], 14);
    final grow = (0.35 + 0.65 * fill01) * clampD(z.seas[k][season], 0.2, 1.4);
    for (var i = 0; i < plants; i++) {
      final x = 20 + i * (s.width - 40) / 14;
      final base = y + rh - 6;
      final h = (rh - 10) * grow * (0.8 + 0.2 * math.sin(e.t * 2 + i));
      c.drawLine(Offset(x, base), Offset(x, base - h), stroke(const Color(0xFF4F7F52), 2));
      c.drawCircle(Offset(x, base - h), 3.5 + 2 * fill01, fill(cropCol[k % cropCol.length]));
    }
  }
  paintSeasonParticles(c, s, season, e.t, count: 10);
}

void _paintAquarium(Canvas c, Size s, IdlePuzzle z, Econ e, int season) {
  final rect = Offset.zero & s;
  c.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8FD3E8), Color(0xFF2E7FA8), Color(0xFF1B4F72)],
        ).createShader(rect));
  // ışık hüzmeleri
  for (var i = 0; i < 4; i++) {
    final x = s.width * (0.15 + i * 0.25) + math.sin(e.t * 0.4 + i) * 10;
    final p = Path()
      ..moveTo(x - 10, 0)
      ..lineTo(x + 10, 0)
      ..lineTo(x + 40, s.height)
      ..lineTo(x - 20, s.height)
      ..close();
    c.drawPath(p, fill(Colors.white.withValues(alpha: 0.06)));
  }
  // kum ve bitkiler
  c.drawRect(Rect.fromLTWH(0, s.height * 0.86, s.width, s.height * 0.14), fill(const Color(0xFFE6D3A3)));
  for (var i = 0; i < 7; i++) {
    final x = 16 + i * (s.width - 32) / 6;
    final h = 30.0 + (i * 17) % 40;
    final sway = math.sin(e.t * 1.2 + i) * 6;
    final p = Path()
      ..moveTo(x, s.height * 0.88)
      ..quadraticBezierTo(x + sway, s.height * 0.88 - h / 2, x + sway * 1.5, s.height * 0.88 - h);
    c.drawPath(p, stroke(const Color(0xFF3F8F5A), 4));
  }
  // balıklar
  final prods = z.producers;
  for (var k = 0; k < prods; k++) {
    final cnt = math.min<int>(e.n[k], 6);
    final col = HSVColor.fromAHSV(1, (20 + k * 61) % 360.0, 0.7, 0.98).toColor();
    for (var i = 0; i < cnt; i++) {
      final sp = 0.25 + 0.07 * ((i + k) % 4);
      final ph = i * 1.7 + k * 0.9;
      final u = (math.sin(e.t * sp + ph) + 1) / 2;
      final x = 20 + u * (s.width - 40);
      final y = s.height * (0.12 + 0.12 * k) % (s.height * 0.75) + 20 + math.sin(e.t * 1.3 + ph) * 8;
      final dir = math.cos(e.t * sp + ph) >= 0 ? 1.0 : -1.0;
      final size = 8.0 + k * 2;
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: size * 2.2, height: size * 1.2), fill(col));
      final tail = Path()
        ..moveTo(x - dir * size, y)
        ..lineTo(x - dir * size * 1.7, y - size * 0.6)
        ..lineTo(x - dir * size * 1.7, y + size * 0.6)
        ..close();
      c.drawPath(tail, fill(col));
      c.drawCircle(Offset(x + dir * size * 0.6, y - 2), 1.8, fill(const Color(0xFF1B1B1B)));
    }
  }
  // kabarcıklar
  for (var i = 0; i < 10; i++) {
    final x = (i * 53.7) % s.width;
    final y = s.height - ((e.t * (20 + i * 3) + i * 40) % s.height);
    c.drawCircle(Offset(x, y), 2 + (i % 3).toDouble(), stroke(Colors.white.withValues(alpha: 0.6), 1));
  }
  // yosun bulanıklığı
  final dirt = 1 - e.clean;
  if (dirt > 0.05) c.drawRect(rect, fill(const Color(0xFF6B8E23).withValues(alpha: dirt * 0.45)));
  if (season == 3) c.drawRect(Rect.fromLTWH(0, 0, s.width, 6), fill(Colors.white.withValues(alpha: 0.7)));
}

void _paintZen(Canvas c, Size s, IdlePuzzle z, Econ e, int season, List<Offset> buds, List<List<Offset>> rake) {
  final look = kSeasonLooks[season];
  c.drawRect(Offset.zero & s, fill(const Color(0xFFEDE3CF)));
  // tırmık izleri (her çizgiye paralel üç iz)
  final rp = stroke(const Color(0xFFCDBE9F), 2);
  for (final line in rake) {
    if (line.length < 2) continue;
    for (final off in const [-6.0, 0.0, 6.0]) {
      final p = Path()..moveTo(line.first.dx * s.width, line.first.dy * s.height + off);
      for (final q in line.skip(1)) {
        p.lineTo(q.dx * s.width, q.dy * s.height + off);
      }
      c.drawPath(p, rp);
    }
  }
  // varsayılan dalga izleri
  for (var i = 0; i < 6; i++) {
    final y = s.height * (0.62 + i * 0.06);
    final p = Path()..moveTo(0, y);
    for (var x = 0.0; x <= s.width; x += 12) {
      p.lineTo(x, y + math.sin(x / 30 + i) * 3);
    }
    c.drawPath(p, stroke(const Color(0xFFD8CBB0), 1.5));
  }
  // taşlar (yosun ve taş sayısına göre)
  final stones = math.min<int>(e.n[0] + e.n[1], 7);
  for (var i = 0; i < stones; i++) {
    final x = s.width * (0.55 + (i * 0.13) % 0.4);
    final y = s.height * (0.7 + (i * 0.07) % 0.22);
    c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 30 + (i % 3) * 8, height: 18), fill(const Color(0xFF8C8C88)));
    c.drawOval(Rect.fromCenter(center: Offset(x - 3, y - 4), width: 18, height: 7), fill(const Color(0xFF6E9E5A).withValues(alpha: 0.8)));
  }
  // koi havuzu
  if (z.producers > 4 && e.n[4] > 0) {
    final pond = Rect.fromCenter(center: Offset(s.width * 0.78, s.height * 0.32), width: s.width * 0.34, height: s.height * 0.22);
    c.drawOval(pond, fill(const Color(0xFF5DA9C9)));
    for (var i = 0; i < math.min<int>(e.n[4], 5); i++) {
      final a = e.t * 0.6 + i * 1.3;
      final p = Offset(pond.center.dx + math.cos(a) * pond.width * 0.3, pond.center.dy + math.sin(a) * pond.height * 0.3);
      c.drawOval(Rect.fromCenter(center: p, width: 14, height: 7), fill(i.isEven ? const Color(0xFFF28C28) : Colors.white));
    }
  }
  // fener
  if (e.n[2] > 0) {
    final x = s.width * 0.12, y = s.height * 0.68;
    c.drawRect(Rect.fromLTWH(x - 4, y, 8, 30), fill(const Color(0xFF8C8C88)));
    c.drawRect(Rect.fromLTWH(x - 12, y - 16, 24, 16), fill(const Color(0xFF9E9E99)));
    c.drawRect(Rect.fromLTWH(x - 6, y - 12, 12, 9), fill(const Color(0xFFFFE08A)));
    c.drawPath(
        Path()
          ..moveTo(x - 16, y - 16)
          ..lineTo(x, y - 28)
          ..lineTo(x + 16, y - 16)
          ..close(),
        fill(const Color(0xFF7A7A75)));
  }
  // bonsai
  final total = _units(e);
  final depth = 2 + math.min<int>(5, (math.log(total + 1) / math.ln2).floor());
  final base = Offset(s.width * 0.36, s.height * 0.62);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: base + const Offset(0, 10), width: 80, height: 20), const Radius.circular(6)),
      fill(const Color(0xFF7A4E2D)));
  final leaf = season == 2 ? const Color(0xFFD9772F) : (season == 0 ? const Color(0xFFF2A7B8) : const Color(0xFF4F7F52));
  void branch(Offset from, double ang, double len, int d) {
    final to = from + Offset(math.cos(ang) * len, math.sin(ang) * len);
    c.drawLine(from, to, stroke(const Color(0xFF5B3A22), math.max(1.5, d * 1.6)));
    if (d <= 1) {
      if (season != 3) c.drawCircle(to, 9, fill(leaf.withValues(alpha: 0.85)));
      if (season == 3) c.drawCircle(to, 4, fill(Colors.white));
      return;
    }
    final sway = math.sin(e.t * 0.8 + d) * 0.04;
    branch(to, ang - 0.45 + sway, len * 0.74, d - 1);
    branch(to, ang + 0.4 + sway, len * 0.7, d - 1);
  }

  branch(base, -math.pi / 2, s.height * 0.13, depth);
  for (final b in buds) {
    final p = Offset(b.dx * s.width, b.dy * s.height);
    c.drawCircle(p, 10, fill(const Color(0x55E5446D)));
    c.drawCircle(p, 5, fill(const Color(0xFFE5446D)));
  }
  paintSeasonParticles(c, s, season, e.t, count: 8);
  c.drawRect(Offset.zero & s, stroke(look.accent.withValues(alpha: 0.4), 4));
}

/// Arı kovanı: çiçekli çayır, petek kovanları ve uçuşan arılar. Kışın arılar
/// kovanda kalır, çiçekler kar altında.
void _paintBee(Canvas c, Size s, IdlePuzzle z, Econ e, int season) {
  paintSky(c, s, season, groundAt: 0.55);
  final look = kSeasonLooks[season];
  final gy = s.height * 0.55;
  c.drawRect(Rect.fromLTWH(0, gy, s.width, s.height - gy), fill(season == 3 ? const Color(0xFFE9EEF2) : look.ground));
  // çiçekler
  const petal = [Color(0xFFF2C14E), Color(0xFFE88DB0), Color(0xFFFFFFFF), Color(0xFFB38CD9)];
  final flowers = season == 3 ? 4 : 10 + math.min<int>(_units(e), 30);
  for (var i = 0; i < flowers; i++) {
    final x = (i * 61.7 + 17) % s.width;
    final y = gy + 12 + (i * 37.3) % (s.height - gy - 24);
    final r = 4.0 + (i % 3);
    final col = petal[i % petal.length];
    for (var k = 0; k < 5; k++) {
      final a = k * math.pi * 2 / 5 + e.t * 0.2;
      c.drawCircle(Offset(x + math.cos(a) * r, y + math.sin(a) * r), r * 0.7, fill(col.withValues(alpha: season == 3 ? 0.35 : 0.95)));
    }
    c.drawCircle(Offset(x, y), r * 0.55, fill(const Color(0xFF8A5A14)));
  }
  // kovanlar (her üretici türü için bir kovan, dolulukla altın rengi artar)
  final hives = z.producers;
  final w = s.width / (hives + 1);
  for (var k = 0; k < hives; k++) {
    final cx = w * (k + 1);
    final by = gy - 4;
    final filled = clampD(e.n[k] / 25, 0, 1);
    for (var row = 0; row < 3; row++) {
      final rw = 34.0 - row * 7;
      final rect = Rect.fromCenter(center: Offset(cx, by - 9 - row * 13), width: rw, height: 13);
      c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          fill(Color.lerp(const Color(0xFFD9B26F), const Color(0xFFF2A516), filled)!));
      c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), stroke(const Color(0xFF8A5A14), 1.2));
    }
    c.drawCircle(Offset(cx, by - 8), 3.5, fill(const Color(0xFF4A2E0A)));
  }
  // arılar
  final bees = season == 3 ? 2 : math.min<int>(4 + _units(e) ~/ 2, 26);
  for (var i = 0; i < bees; i++) {
    final ph = e.t * (0.6 + (i % 5) * 0.11) + i * 1.7;
    final x = s.width * (0.5 + 0.42 * math.sin(ph));
    final y = gy * (0.35 + 0.3 * math.sin(ph * 1.7 + i)) + 20;
    c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 9, height: 6), fill(const Color(0xFFF2C14E)));
    c.drawLine(Offset(x - 1, y - 3), Offset(x - 1, y + 3), stroke(const Color(0xFF2B2B2B), 1.4));
    final flap = 2 + 2 * math.sin(e.t * 30 + i).abs();
    c.drawOval(Rect.fromCenter(center: Offset(x + 1, y - 4), width: 6, height: flap * 2), fill(Colors.white.withValues(alpha: 0.7)));
  }
  paintSeasonParticles(c, s, season, e.t, count: 8);
}

/// Çay bahçesi: ağaç gölgesinde masalar, demlikten yükselen buhar, akşamüstü
/// ışıkları. Masalar dolduğunda bahçe kalabalıklaşır.
void _paintTea(Canvas c, Size s, IdlePuzzle z, Econ e, int season) {
  paintSky(c, s, season, groundAt: 0.42);
  final look = kSeasonLooks[season];
  final gy = s.height * 0.42;
  c.drawRect(Rect.fromLTWH(0, gy, s.width, s.height - gy), fill(Color.lerp(const Color(0xFFCDB58E), look.ground, 0.35)!));
  // çınar ağaçları
  for (var i = 0; i < 3; i++) {
    final x = s.width * (0.15 + i * 0.35);
    c.drawRect(Rect.fromCenter(center: Offset(x, gy - 18), width: 10, height: 40), fill(const Color(0xFF6B4A2B)));
    final leaf = season == 2 ? const Color(0xFFD9772F) : (season == 3 ? const Color(0xFFDCE4EA) : const Color(0xFF4F8F4A));
    for (var k = 0; k < 4; k++) {
      c.drawCircle(Offset(x + (k - 1.5) * 12, gy - 46 - (k % 2) * 10), 18, fill(leaf.withValues(alpha: 0.9)));
    }
  }
  // ışık zinciri
  final bulbs = math.min<int>(4 + _units(e) ~/ 3, 24);
  for (var i = 0; i < bulbs; i++) {
    final u = (i + 0.5) / bulbs;
    final x = u * s.width;
    final y = gy * 0.35 + 4 * u * (1 - u) * 26;
    final a = 0.6 + 0.4 * math.sin(e.t * 2 + i);
    c.drawCircle(Offset(x, y), 3.2, fill(const Color(0xFFFFD27D).withValues(alpha: a)));
  }
  // masalar ve bardaklar
  final tables = math.min<int>(2 + _units(e) ~/ 4, 12);
  const cols = 4;
  final cw = s.width / cols;
  final rows = (tables + cols - 1) ~/ cols;
  final rh = (s.height - gy - 10) / math.max(1, rows);
  for (var i = 0; i < tables; i++) {
    final cx = cw * (i % cols + 0.5);
    final cy = gy + 10 + rh * (i ~/ cols + 0.5);
    c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: cw * 0.55, height: 16), fill(const Color(0xFF9C6B3E)));
    c.drawLine(Offset(cx, cy + 8), Offset(cx, cy + 22), stroke(const Color(0xFF6B4A2B), 3));
    for (var g = -1; g <= 1; g += 2) {
      final gx = cx + g * cw * 0.12;
      final glass = Path()
        ..moveTo(gx - 3, cy - 12)
        ..quadraticBezierTo(gx, cy - 6, gx - 2.5, cy - 2)
        ..lineTo(gx + 2.5, cy - 2)
        ..quadraticBezierTo(gx, cy - 6, gx + 3, cy - 12)
        ..close();
      c.drawPath(glass, fill(const Color(0xFFB2361F).withValues(alpha: 0.85)));
      final steam = Path()..moveTo(gx, cy - 13);
      for (var k = 1; k <= 3; k++) {
        steam.lineTo(gx + math.sin(e.t * 2 + k + i) * 3, cy - 13 - k * 5);
      }
      c.drawPath(steam, stroke(Colors.white.withValues(alpha: season == 1 ? 0.25 : 0.55), 1.2));
    }
  }
  // semaver
  final sx = s.width - 30, sy = gy - 6;
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx, sy), width: 22, height: 30), const Radius.circular(6)),
      fill(const Color(0xFFC9A227)));
  c.drawCircle(Offset(sx, sy - 18), 6, fill(const Color(0xFFB58A1C)));
  paintSeasonParticles(c, s, season, e.t, count: 8);
}
