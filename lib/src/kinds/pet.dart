import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';
import 'idle.dart' show numOf, intOf;

// =================================================================== Pofu (sanal evcil hayvan)

/// İhtiyaçlar: 0 tokluk, 1 neşe, 2 temizlik, 3 enerji.
const List<String> kNeedKeys = ['nFull', 'nJoy', 'nClean', 'nEnergy'];
const List<IconData> kNeedIcons = [Icons.restaurant, Icons.sentiment_satisfied_alt, Icons.bathtub, Icons.bolt];
const List<Color> kNeedColors = [Color(0xFFE07A5F), Color(0xFFF2C14E), Color(0xFF4A90C2), Color(0xFF7FB069)];
const List<String> kPetActKeys = ['feed', 'playPet', 'wash', 'rest'];
const List<IconData> kPetActIcons = [Icons.lunch_dining, Icons.sports_baseball, Icons.shower, Icons.bedtime];
const List<String> kStageKeys = ['stage0', 'stage1', 'stage2', 'stage3', 'stage4', 'stage5'];
const List<double> kStageAt = [0, 0.15, 0.35, 0.6, 0.85, 1.0];

/// Mevsim etkisi: ilkbahar neşeli, yazın çabuk kirlenir, sonbaharda iştah
/// artar, kışın enerji çabuk biter.
const List<List<double>> kPetSeason = [
  [1.0, 0.8, 1.0, 1.0],
  [1.0, 1.0, 1.25, 1.0],
  [1.15, 1.0, 1.0, 1.0],
  [1.0, 1.0, 0.9, 1.3],
];

class PetPuzzle extends SPuzzle {
  final int d;
  final int season0;
  final List<double> decay;
  final int goalXp;
  final int par;
  final int limit;
  const PetPuzzle(this.d, this.season0, this.decay, this.goalXp, this.par, this.limit);

  PetPuzzle withGoal(int g, int p) => PetPuzzle(d, season0, decay, g, p, limit);
}

class PetSim {
  final PetPuzzle z;
  List<double> need = [80, 80, 80, 80];
  double coins = 20;
  double xp = 0;
  double t = 0;
  double sleep = 0;
  bool calm = false;
  final List<int> used = [0, 0, 0, 0];

  PetSim(this.z);

  int get season => (z.season0 + t ~/ kSeasonLen) % 4;
  bool get sleeping => sleep > 0;
  double get avg => need.fold<double>(0, (a, b) => a + b) / 4;
  double get lowest => need.reduce(math.min);
  double get xpRate => lowest >= 25 ? clampD((avg - 45) / 25, 0, 1.5) : 0.0;

  void step(double dt) {
    final s = season;
    for (var i = 0; i < 4; i++) {
      need[i] -= z.decay[i] * kPetSeason[s][i] * (sleeping ? 0.5 : 1) * (calm ? 0.6 : 1) * dt;
    }
    if (sleeping) {
      need[3] += 5 * dt;
      sleep -= dt;
    }
    for (var i = 0; i < 4; i++) {
      need[i] = clampD(need[i], 0, 100);
    }
    xp += xpRate * dt;
    t += dt;
  }

  bool act(int a) {
    if (sleeping) return false;
    switch (a) {
      case 0:
        if (coins < 4) return false;
        coins -= 4;
        need[0] += 30;
        need[1] += 3;
      case 1:
        if (need[3] < 10) return false;
        need[1] += 22;
        need[3] -= 8;
        coins += 5;
      case 2:
        need[2] += 45;
        need[3] -= 3;
        need[1] -= 2;
      default:
        sleep = 12;
    }
    for (var i = 0; i < 4; i++) {
      need[i] = clampD(need[i], 0, 100);
    }
    used[a]++;
    return true;
  }

  void botAct() {
    if (sleeping) return;
    var lo = 0;
    for (var i = 1; i < 4; i++) {
      if (need[i] < need[lo]) lo = i;
    }
    if (need[3] < 35) {
      act(3);
    } else if (lo == 0 && coins >= 4) {
      act(0);
    } else if (lo == 2) {
      act(2);
    } else if (lo == 3) {
      act(3);
    } else {
      act(1);
    }
  }
}

int petReach(PetPuzzle z, int limit) {
  final s = PetSim(z);
  for (var i = 1; i <= limit; i++) {
    if (i % 3 == 0) s.botAct();
    s.step(1);
    if (s.xp >= z.goalXp) return i;
  }
  return -1;
}

class PetKind extends SimKind {
  @override
  String get id => 'evcil';
  const PetKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final seconds = 150 + 45 * d;
    final k = (1 + 0.06 * d) * (0.92 + 0.16 * r.nextDouble());
    final base = PetPuzzle(d, r.nextInt(4), [0.5 * k, 0.4 * k, 0.25 * k, 0.22 * k], 1 << 30, seconds, seconds + seconds ~/ 4);
    final s = PetSim(base);
    for (var i = 1; i <= seconds; i++) {
      if (i % 3 == 0) s.botAct();
      s.step(1);
    }
    final goal = (niceFloor(s.xp * 0.85)).round();
    if (goal < 30) return null;
    final z = base.withGoal(goal, seconds);
    final reach = petReach(z, z.limit);
    if (reach < 0) return null;
    return z.withGoal(goal, reach);
  }

  @override
  bool check(SPuzzle p) => p is PetPuzzle && p.goalXp >= 30 && p.decay.length == 4 && petReach(p, p.limit) == p.par;

  @override
  Widget build(SimPlay play) => _PetView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('care', 'Bakım', 'Care actions', scale: 50),
        const GameStat('stars_caught', 'Yakalanan yıldız', 'Stars caught', scale: 20),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('care', 'care', [20, 80, 250]),
        const MissionTemplate('stars', 'stars_caught', [5, 20, 60]),
      ];
}

class _PetView extends StatefulWidget {
  final SimPlay play;
  const _PetView({required this.play});

  @override
  State<_PetView> createState() => _PetViewState();
}

class _PetViewState extends State<_PetView> with SimClock<_PetView> {
  late final PetPuzzle z = widget.play.puzzle as PetPuzzle;
  late final PetSim p = PetSim(z);
  bool calm = false;
  double saveIn = 5;
  Offset? star;
  double starUntil = -1;
  double nextStar = 8;
  int caught = 0;
  double bounce = -10;
  String note = '';
  double noteUntil = -1;
  final math.Random _rnd = math.Random();

  SimPlay get play => widget.play;
  String get lang => play.lang;

  int get stage {
    var s = 0;
    for (var i = 0; i < kStageAt.length; i++) {
      if (p.xp >= kStageAt[i] * z.goalXp) s = i;
    }
    return s;
  }

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    p.calm = calm;
    final r = play.restored;
    if (r.isNotEmpty) {
      final nd = r['need'];
      if (nd is List && nd.length == 4) p.need = [for (final x in nd) clampD(numOf(x, 80), 0, 100)];
      p.coins = numOf(r['coins'], 20);
      p.xp = numOf(r['xp'], 0);
      p.t = numOf(r['t'], 0);
      p.sleep = numOf(r['sleep'], 0);
      caught = intOf(r['cg'], 0);
      seconds = intOf(r['sec'], 0);
      final away = play.awaySeconds();
      if (away >= 20) {
        for (var i = 0; i < 4; i++) {
          p.need[i] = math.max(math.min(15.0, p.need[i]), p.need[i] - z.decay[i] * away * 0.25);
        }
        note = st(lang, 'petMissed');
        noteUntil = p.t + 8;
      }
    }
    SimPrefs.init().then((_) {
      if (!mounted) return;
      setState(() {
        calm = play.zenMode || SimPrefs.calm;
        p.calm = calm;
      });
    });
    startLoop(200, _tick);
  }

  void _save() => play.save({
        'need': p.need,
        'coins': p.coins,
        'xp': p.xp,
        't': p.t,
        'sleep': p.sleep,
        'cg': caught,
        'sec': seconds,
      });

  void _tick(double dt) {
    if (ended) return;
    p.step(dt);
    if (p.t >= nextStar) {
      nextStar = p.t + 9 + _rnd.nextDouble() * 6;
      star = Offset(0.15 + _rnd.nextDouble() * 0.7, 0.12 + _rnd.nextDouble() * 0.4);
      starUntil = p.t + 4;
    }
    if (star != null && p.t > starUntil) star = null;
    saveIn -= dt;
    if (saveIn <= 0) {
      saveIn = 5;
      _save();
    }
    if (p.xp >= z.goalXp) _win();
  }

  void _win() {
    if (ended) return;
    ended = true;
    stopLoop();
    _save();
    play.sfx(Sfx.win);
    play.win(stars: starsByTime(seconds, z.par), calm: calm, score: p.xp.round(), seconds: seconds, stats: {
      'care': p.used.fold<int>(0, (a, b) => a + b),
      'stars_caught': caught,
    });
  }

  void _act(int a) {
    if (ended) return;
    setState(() {
      if (p.act(a)) {
        play.sfx(a == 3 ? Sfx.unlock : Sfx.place);
        bounce = p.t;
      } else {
        play.sfx(Sfx.error);
      }
    });
  }

  void _tap(Offset q, Size s) {
    if (ended) return;
    setState(() {
      final st0 = star;
      if (st0 != null && (Offset(st0.dx * s.width, st0.dy * s.height) - q).distance < 40) {
        star = null;
        caught++;
        p.coins += 3;
        p.need[1] = math.min(100.0, p.need[1] + 5);
        play.sfx(Sfx.coin);
        return;
      }
      bounce = p.t;
      if (!p.sleeping) p.need[1] = math.min(100.0, p.need[1] + 0.5);
      play.sfx(Sfx.tap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final season = p.season;
    final costs = ['−4', '+5', '', '12s'];
    return SimFrame(
      play: play,
      moneyIcon: Icons.toll,
      money: fmtNum(p.coins),
      sub: st(lang, kStageKeys[stage]),
      goalText: '${st(lang, 'growth')} ${p.xp.floor()}/${z.goalXp}',
      progress: p.xp / z.goalXp,
      season: season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        p.calm = v;
        SimPrefs.calm = v;
      }),
      banner: noteUntil > p.t && note.isNotEmpty ? SNote(note, icon: Icons.nightlight_round) : null,
      sceneFlex: 6,
      panelFlex: 3,
      scene: SceneCanvas(paint: (c, s) => _paintPet(c, s, p, stage, season, star, p.t - bounce), onTap: _tap, semantics: st(lang, 'tapScene')),
      panel: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(children: [
          Row(children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(children: [
                    Icon(kNeedIcons[i], size: 18, color: kNeedColors[i]),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: p.need[i] / 100, minHeight: 8, color: kNeedColors[i]),
                    ),
                    FittedBox(child: Text(st(lang, kNeedKeys[i]), style: const TextStyle(fontSize: 11))),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Row(children: [
              for (var a = 0; a < 4; a++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FilledButton.tonal(
                      onPressed: p.sleeping ? null : () => _act(a),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
                        disabledForegroundColor: Colors.white54,
                        side: BorderSide(color: StudioLook.of(context).accent.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(kPetActIcons[a], size: 22),
                        FittedBox(child: Text(st(lang, kPetActKeys[a]), style: const TextStyle(fontSize: 12))),
                        if (costs[a].isNotEmpty) Text(costs[a], style: const TextStyle(fontSize: 10)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

void _paintPet(Canvas c, Size s, PetSim p, int stage, int season, Offset? star, double sinceBounce) {
  final look = kSeasonLooks[season];
  // oda: duvar, pencere, halı
  c.drawRect(Offset.zero & s, fill(const Color(0xFFF3E6D3)));
  c.drawRect(Rect.fromLTWH(0, s.height * 0.72, s.width, s.height * 0.28), fill(const Color(0xFFD8C3A5)));
  final win = Rect.fromLTWH(s.width * 0.08, s.height * 0.08, s.width * 0.3, s.height * 0.3);
  c.drawRect(win, fill(look.skyTop));
  c.drawRect(Rect.fromLTWH(win.left, win.bottom - win.height * 0.25, win.width, win.height * 0.25), fill(look.ground));
  c.save();
  c.clipRect(win);
  paintSeasonParticles(c, win.size, season, p.t, count: 6);
  c.restore();
  c.drawRect(win, stroke(const Color(0xFF9C6644), 4));
  c.drawLine(win.topCenter, win.bottomCenter, stroke(const Color(0xFF9C6644), 2));
  c.drawOval(Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.84), width: s.width * 0.7, height: s.height * 0.14), fill(look.accent.withValues(alpha: 0.5)));
  // Pofu
  final size = s.shortestSide * (0.16 + 0.025 * stage);
  final hop = sinceBounce >= 0 && sinceBounce < 0.5 ? math.sin(sinceBounce * math.pi * 2) * 14 : 0.0;
  final breathe = math.sin(p.t * 2) * (p.sleeping ? 3 : 1.5);
  final ctr = Offset(s.width / 2, s.height * 0.6 - hop.abs());
  final hue = (200 + stage * 30) % 360.0;
  final body = HSVColor.fromAHSV(1, hue, 0.22 + 0.04 * stage, 1).toColor();
  final shade = HSVColor.fromAHSV(1, hue, 0.35 + 0.04 * stage, 0.92).toColor();
  c.drawOval(Rect.fromCenter(center: Offset(ctr.dx, s.height * 0.78), width: size * 2, height: size * 0.35), fill(const Color(0x22000000)));
  for (var i = 0; i < 9; i++) {
    final a = i * 2 * math.pi / 9;
    c.drawCircle(ctr + Offset(math.cos(a) * size * 0.72, math.sin(a) * size * 0.55), size * 0.5 + breathe, fill(shade));
  }
  c.drawCircle(ctr, size * 0.95 + breathe, fill(body));
  if (stage >= 4) {
    // gökkuşağı yelesi
    for (var k = 0; k < 5; k++) {
      final col = HSVColor.fromAHSV(0.85, k * 60.0, 0.55, 1).toColor();
      c.drawArc(Rect.fromCircle(center: ctr, radius: size * (1.05 + k * 0.08)), math.pi * 1.1, math.pi * 0.8, false, stroke(col, 4));
    }
  }
  if (stage >= 5) {
    for (var k = 0; k < 3; k++) {
      drawIcon(c, Icons.star_rounded, ctr + Offset(-size + k * size, -size * 1.35), 16, const Color(0xFFF2C14E));
    }
  }
  // kirlilik
  if (p.need[2] < 40) {
    final n = ((40 - p.need[2]) / 8).ceil();
    for (var i = 0; i < n; i++) {
      c.drawCircle(ctr + Offset(math.cos(i * 2.3) * size * 0.6, math.sin(i * 1.7) * size * 0.5), 4, fill(const Color(0x667A5230)));
    }
  }
  // yüz
  final eyeY = ctr.dy - size * 0.15;
  final blink = (p.t % 4) < 0.15;
  final tired = p.need[3] < 30;
  for (final side in const [-1.0, 1.0]) {
    final e = Offset(ctr.dx + side * size * 0.32, eyeY);
    if (p.sleeping || blink) {
      c.drawArc(Rect.fromCenter(center: e, width: size * 0.22, height: size * 0.14), 0, math.pi, false, stroke(const Color(0xFF3B2F2F), 2.5));
    } else {
      c.drawCircle(e, size * 0.09, fill(const Color(0xFF3B2F2F)));
      c.drawCircle(e + Offset(size * 0.03, -size * 0.03), size * 0.03, fill(Colors.white));
      if (tired) c.drawLine(e + Offset(-size * 0.1, -size * 0.1), e + Offset(size * 0.1, -size * 0.07), stroke(const Color(0xFF3B2F2F), 2));
    }
    c.drawCircle(Offset(ctr.dx + side * size * 0.52, ctr.dy + size * 0.05), size * 0.1, fill(const Color(0x55E5446D)));
  }
  final joy = p.need[1] / 100;
  final smile = Path()
    ..moveTo(ctr.dx - size * 0.18, ctr.dy + size * 0.18)
    ..quadraticBezierTo(ctr.dx, ctr.dy + size * (0.05 + 0.3 * joy), ctr.dx + size * 0.18, ctr.dy + size * 0.18);
  c.drawPath(smile, stroke(const Color(0xFF3B2F2F), 2.5));
  if (p.need[0] < 30) drawLabel(c, '🍽', ctr + Offset(size * 1.1, -size * 0.9), 20, Colors.black);
  if (p.sleeping) {
    for (var k = 0; k < 3; k++) {
      final y = ((p.t * 0.8 + k * 0.33) % 1.0);
      drawLabel(c, 'z', ctr + Offset(size * 0.8 + y * 20, -size * 0.9 - y * 30), 14 + k * 3.0, const Color(0xFF5B6770).withValues(alpha: 1 - y));
    }
  }
  if (star != null) {
    final q = Offset(star.dx * s.width, star.dy * s.height);
    c.drawCircle(q, 18 + math.sin(p.t * 6) * 3, fill(const Color(0x55FFD166)));
    drawIcon(c, Icons.star_rounded, q, 30, const Color(0xFFF2C14E));
  }
}
