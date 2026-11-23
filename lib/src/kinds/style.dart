import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

// =================================================================== Stil Atölyesi (giydirme, üretilmiş kıyafetler)

/// Durumlar: (sıcaklık hedefi 0..3, şıklık 0..2, uygun aksesuar, mevsimler).
const List<(int, int, int, List<int>)> kOccasions = [
  (1, 0, 0, [0, 1, 2]),
  (2, 0, 3, [0, 2]),
  (1, 1, 2, [0, 1, 2, 3]),
  (3, 0, 1, [3]),
  (0, 0, 0, [1]),
  (1, 2, 2, [0, 1]),
  (2, 1, 1, [0, 2, 3]),
  (1, 0, 2, [0, 1, 2, 3]),
];
const List<String> kOccasionKeys = ['oPicnic', 'oRain', 'oConcert', 'oWinterWalk', 'oBeach', 'oGardenParty', 'oMuseum', 'oSports'];
const List<IconData> kOccasionIcons = [
  Icons.deck,
  Icons.umbrella,
  Icons.music_note,
  Icons.ac_unit,
  Icons.beach_access,
  Icons.local_florist,
  Icons.museum,
  Icons.sports_soccer,
];
const List<String> kSlotKeys = ['slotTop', 'slotBottom', 'slotShoes', 'slotAcc'];
const List<IconData> kSlotIcons = [Icons.checkroom, Icons.horizontal_split, Icons.directions_walk, Icons.shopping_bag];
const List<String> kPatternKeys = ['pPlain', 'pStripes', 'pDots', 'pChecks', 'pFloral'];

const List<Color> kHues = [
  Color(0xFFC8553D),
  Color(0xFFE07A5F),
  Color(0xFFF2C14E),
  Color(0xFF9BC53D),
  Color(0xFF4F9A6E),
  Color(0xFF3A8D8C),
  Color(0xFF4A90C2),
  Color(0xFF2E5E8C),
  Color(0xFF7A4E7E),
  Color(0xFFB56576),
  Color(0xFF8D6E63),
  Color(0xFF5B6770),
];

class Garment {
  final int hue;
  final int pat;
  final int warm;
  final int formal;
  final int acc;
  const Garment(this.hue, this.pat, this.warm, this.formal, this.acc);
}

class StylePuzzle extends SPuzzle {
  final int d;
  final int season;
  final int occasion;
  final List<int> palette;
  final int pattern;
  final List<List<Garment>> options;
  final int target;
  final int best;
  const StylePuzzle(this.d, this.season, this.occasion, this.palette, this.pattern, this.options, this.target, this.best);
}

int styleScore(StylePuzzle z, List<int> pick) {
  final o = kOccasions[z.occasion];
  var s = 0;
  var patterned = 0, wanted = 0;
  for (var slot = 0; slot < 4; slot++) {
    final g = z.options[slot][pick[slot]];
    if (z.palette.contains(g.hue)) {
      s += 3;
    } else if (z.palette.any((h) => (h - g.hue).abs() == 1 || (h - g.hue).abs() == kHues.length - 1)) {
      s += 1;
    }
    final wW = slot <= 1 ? 2 : 1;
    s -= (g.warm - o.$1).abs() * wW;
    s -= (g.formal - o.$2).abs() * wW;
    if (g.pat != 0) patterned++;
    if (g.pat == z.pattern) wanted++;
    if (slot == 3 && g.acc == o.$3) s += 3;
  }
  if (wanted == 1) s += 4;
  if (patterned > 2) s -= 3;
  return s;
}

(int, List<int>) styleBest(StylePuzzle z) {
  var best = -1 << 20;
  var arg = <int>[0, 0, 0, 0];
  final n = [for (final o in z.options) o.length];
  for (var a = 0; a < n[0]; a++) {
    for (var b = 0; b < n[1]; b++) {
      for (var c = 0; c < n[2]; c++) {
        for (var d = 0; d < n[3]; d++) {
          final s = styleScore(z, [a, b, c, d]);
          if (s > best) {
            best = s;
            arg = [a, b, c, d];
          }
        }
      }
    }
  }
  return (best, arg);
}

class StyleKind extends SimKind {
  @override
  String get id => 'stil';
  const StyleKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final season = r.nextInt(4);
    final fits = [for (var i = 0; i < kOccasions.length; i++) if (kOccasions[i].$4.contains(season)) i];
    final occasion = r.pick(fits);
    final palette = <int>[];
    final p0 = r.nextInt(kHues.length);
    palette.add(p0);
    palette.add((p0 + 4 + r.nextInt(5)) % kHues.length);
    if (d >= 5) palette.add((p0 + 2 + r.nextInt(2)) % kHues.length);
    final pattern = 1 + r.nextInt(4);
    final count = d <= 3 ? 4 : 5;
    final options = <List<Garment>>[];
    for (var slot = 0; slot < 4; slot++) {
      final list = <Garment>[];
      for (var k = 0; k < count; k++) {
        list.add(Garment(
          r.nextInt(kHues.length),
          r.chance(0.45) ? 0 : 1 + r.nextInt(4),
          r.nextInt(4),
          r.nextInt(3),
          slot == 3 ? r.nextInt(4) : -1,
        ));
      }
      options.add(list);
    }
    final probe = StylePuzzle(d, season, occasion, palette, pattern, options, 0, 0);
    final (best, _) = styleBest(probe);
    if (best < 8) return null;
    final target = math.min(best - 1, (best * (0.72 + 0.02 * d)).floor());
    return StylePuzzle(d, season, occasion, palette, pattern, options, target, best);
  }

  @override
  bool check(SPuzzle p) {
    if (p is! StylePuzzle || p.options.length != 4 || p.options.any((o) => o.length < 4)) return false;
    final (best, _) = styleBest(p);
    return best == p.best && best >= 8 && p.target < best && p.target >= 4;
  }

  @override
  Widget build(SimPlay play) => _StyleView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('outfits', 'Hazırlanan kombin', 'Outfits styled', scale: 20),
        const GameStat('top_looks', 'Kusursuz kombin', 'Perfect looks', scale: 10),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('outfits', 'outfits', [5, 20, 60]),
        const MissionTemplate('top', 'top_looks', [1, 5, 15]),
      ];
}

void paintPattern(Canvas c, Path clip, Rect b, int pat, Color base) {
  c.drawPath(clip, fill(base));
  if (pat == 0) return;
  c.save();
  c.clipPath(clip);
  final light = Color.lerp(base, Colors.white, 0.55)!;
  final dark = Color.lerp(base, Colors.black, 0.25)!;
  switch (pat) {
    case 1:
      for (var y = b.top; y < b.bottom; y += 8) {
        c.drawRect(Rect.fromLTWH(b.left, y, b.width, 3), fill(light));
      }
    case 2:
      for (var y = b.top + 4; y < b.bottom; y += 9) {
        for (var x = b.left + 4 + ((y - b.top) ~/ 9 % 2) * 4.5; x < b.right; x += 9) {
          c.drawCircle(Offset(x, y), 2, fill(light));
        }
      }
    case 3:
      for (var x = b.left; x < b.right; x += 10) {
        c.drawRect(Rect.fromLTWH(x, b.top, 3, b.height), fill(dark.withValues(alpha: 0.5)));
      }
      for (var y = b.top; y < b.bottom; y += 10) {
        c.drawRect(Rect.fromLTWH(b.left, y, b.width, 3), fill(dark.withValues(alpha: 0.5)));
      }
    default:
      for (var y = b.top + 6; y < b.bottom; y += 14) {
        for (var x = b.left + 6 + ((y - b.top) ~/ 14 % 2) * 7.0; x < b.right; x += 14) {
          for (var k = 0; k < 5; k++) {
            final a = k * 2 * math.pi / 5;
            c.drawCircle(Offset(x + math.cos(a) * 3, y + math.sin(a) * 3), 2, fill(light));
          }
          c.drawCircle(Offset(x, y), 1.5, fill(const Color(0xFFF2C14E)));
        }
      }
  }
  c.restore();
}

/// Ahşap manken ve üzerindeki kombin.
void paintOutfit(Canvas c, Size s, StylePuzzle z, List<int> pick, double t) {
  final cx = s.width / 2;
  final h = s.height * 0.9;
  final top = s.height * 0.05;
  final u = h / 10;
  const wood = Color(0xFFE3C9A0);
  const woodDark = Color(0xFFB8956A);
  // gölge ve kaide
  c.drawOval(Rect.fromCenter(center: Offset(cx, top + h), width: u * 4, height: u * 0.7), fill(const Color(0x22000000)));
  // baş, boyun, eller
  c.drawCircle(Offset(cx, top + u * 0.9), u * 0.75, fill(wood));
  c.drawCircle(Offset(cx, top + u * 0.9), u * 0.75, stroke(woodDark, 1.2));
  c.drawRect(Rect.fromCenter(center: Offset(cx, top + u * 1.8), width: u * 0.45, height: u * 0.5), fill(wood));
  final g = [for (var i = 0; i < 4; i++) z.options[i][pick[i]]];
  // bacaklar
  c.drawRect(Rect.fromLTWH(cx - u * 0.75, top + u * 5.2, u * 0.6, u * 3.6), fill(wood));
  c.drawRect(Rect.fromLTWH(cx + u * 0.15, top + u * 5.2, u * 0.6, u * 3.6), fill(wood));
  // alt
  final b = g[1];
  final legLen = [1.4, 2.4, 3.6, 3.7][b.warm];
  final bottom = Path()
    ..moveTo(cx - u * 1.05, top + u * 5.0)
    ..lineTo(cx + u * 1.05, top + u * 5.0)
    ..lineTo(cx + u * 0.95, top + u * (5.2 + legLen))
    ..lineTo(cx + u * 0.08, top + u * (5.2 + legLen))
    ..lineTo(cx, top + u * 5.8)
    ..lineTo(cx - u * 0.08, top + u * (5.2 + legLen))
    ..lineTo(cx - u * 0.95, top + u * (5.2 + legLen))
    ..close();
  paintPattern(c, bottom, bottom.getBounds(), b.pat, kHues[b.hue]);
  if (b.formal >= 1) {
    c.drawLine(Offset(cx - u * 0.5, top + u * 5.4), Offset(cx - u * 0.5, top + u * (5.0 + legLen)), stroke(const Color(0x33000000), 1));
    c.drawLine(Offset(cx + u * 0.5, top + u * 5.4), Offset(cx + u * 0.5, top + u * (5.0 + legLen)), stroke(const Color(0x33000000), 1));
  }
  // ayakkabı
  final sh = g[2];
  final shoeH = [0.25, 0.45, 0.45, 1.1][sh.warm];
  for (final side in const [-1.0, 1.0]) {
    final x = cx + side * u * 0.45;
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - u * 0.45, top + u * 8.9 - u * shoeH, u * 0.9 + (side > 0 ? u * 0.15 : 0.0), u * shoeH + u * 0.25), Radius.circular(u * 0.2));
    final p = Path()..addRRect(r);
    paintPattern(c, p, r.outerRect, sh.pat, kHues[sh.hue]);
    if (sh.formal == 2) c.drawRRect(r, stroke(const Color(0x66000000), 1));
  }
  // üst
  final tp = g[0];
  final len = tp.warm == 3 ? 4.3 : 3.4;
  final sleeve = [0.0, 1.0, 2.6, 2.8][tp.warm];
  final body = Path()
    ..moveTo(cx - u * 1.2, top + u * 2.0)
    ..lineTo(cx + u * 1.2, top + u * 2.0)
    ..lineTo(cx + u * 1.1, top + u * (2.0 + len))
    ..lineTo(cx - u * 1.1, top + u * (2.0 + len))
    ..close();
  // kollar
  for (final side in const [-1.0, 1.0]) {
    final ax = cx + side * u * 1.45;
    c.drawRect(Rect.fromCenter(center: Offset(ax, top + u * 3.6), width: u * 0.5, height: u * 3.0), fill(wood));
    c.drawCircle(Offset(ax, top + u * 5.2), u * 0.3, fill(wood));
    if (sleeve > 0) {
      final sl = Path()..addRect(Rect.fromLTWH(ax - u * 0.32, top + u * 2.05, u * 0.64, u * sleeve));
      paintPattern(c, sl, sl.getBounds(), tp.pat, kHues[tp.hue]);
    }
  }
  paintPattern(c, body, body.getBounds(), tp.pat, kHues[tp.hue]);
  if (tp.formal >= 1) {
    c.drawPath(
        Path()
          ..moveTo(cx - u * 0.5, top + u * 2.0)
          ..lineTo(cx, top + u * 2.6)
          ..lineTo(cx + u * 0.5, top + u * 2.0),
        stroke(Colors.white.withValues(alpha: 0.8), 2));
  }
  if (tp.formal == 2) {
    for (var i = 0; i < 3; i++) {
      c.drawCircle(Offset(cx, top + u * (3.0 + i * 0.6)), u * 0.08, fill(const Color(0xFFF7F3EA)));
    }
  }
  // aksesuar
  final a = g[3];
  final col = kHues[a.hue];
  switch (a.acc) {
    case 0:
      final brim = Rect.fromCenter(center: Offset(cx, top + u * 0.35), width: u * 2.4, height: u * 0.4);
      final crown = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, top + u * 0.05), width: u * 1.3, height: u * 0.8), Radius.circular(u * 0.3)));
      paintPattern(c, crown, crown.getBounds(), a.pat, col);
      c.drawOval(brim, fill(Color.lerp(col, Colors.black, 0.15)!));
    case 1:
      final sc = Path()
        ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, top + u * 1.95), width: u * 1.6, height: u * 0.55), Radius.circular(u * 0.25)))
        ..addRect(Rect.fromLTWH(cx + u * 0.25, top + u * 2.0, u * 0.42, u * 1.6));
      paintPattern(c, sc, sc.getBounds(), a.pat, col);
    case 2:
      final bag = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + u * 1.7, top + u * 4.8, u * 1.1, u * 0.9), Radius.circular(u * 0.2)));
      c.drawLine(Offset(cx + u * 1.45, top + u * 2.2), Offset(cx + u * 2.25, top + u * 4.8), stroke(Color.lerp(col, Colors.black, 0.3)!, 2));
      paintPattern(c, bag, bag.getBounds(), a.pat, col);
    default:
      final hx = cx - u * 1.45;
      c.drawLine(Offset(hx, top + u * 5.2), Offset(hx, top + u * 1.0), stroke(const Color(0xFF5B4636), 2));
      final dome = Path()
        ..moveTo(hx - u * 1.6, top + u * 1.2)
        ..quadraticBezierTo(hx, top - u * 0.6 + math.sin(t) * 2, hx + u * 1.6, top + u * 1.2)
        ..close();
      paintPattern(c, dome, dome.getBounds(), a.pat, col);
  }
}

class _StyleView extends StatefulWidget {
  final SimPlay play;
  const _StyleView({required this.play});

  @override
  State<_StyleView> createState() => _StyleViewState();
}

class _StyleViewState extends State<_StyleView> with SimClock<_StyleView> {
  late final StylePuzzle z = widget.play.puzzle as StylePuzzle;
  bool calm = false;
  int slot = 0;
  final List<int> pick = [0, 0, 0, 0];
  int tries = 0;
  int lastScore = -999;
  double t = 0;

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    SimPrefs.init().then((_) {
      if (mounted) setState(() => calm = play.zenMode || SimPrefs.calm);
    });
    startLoop(100, (dt) => t += dt);
  }

  void _show() {
    if (ended) return;
    setState(() {
      tries++;
      lastScore = styleScore(z, pick);
      if (lastScore >= z.target) {
        ended = true;
        stopLoop();
        play.sfx(Sfx.win);
        final stars = lastScore >= z.best ? 3 : (tries == 1 ? 3 : (tries == 2 ? 2 : 1));
        play.win(stars: stars, calm: calm, score: lastScore * 100, seconds: seconds, stats: {
          'outfits': 1,
          if (lastScore >= z.best) 'top_looks': 1,
        });
      } else if (!calm && tries >= 3) {
        ended = true;
        stopLoop();
        play.sfx(Sfx.lose);
        play.lose(score: math.max(0, lastScore) * 100, seconds: seconds, stats: const {'outfits': 1});
      } else {
        play.sfx(Sfx.error);
      }
    });
  }

  Widget _brief() {
    final o = kOccasions[z.occasion];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(kOccasionIcons[z.occasion], size: 18),
          const SizedBox(width: 4),
          Text(st(lang, kOccasionKeys[z.occasion]), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (final h in z.palette)
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(color: kHues[h], shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
            ),
          const SizedBox(width: 6),
          SizedBox(width: 22, height: 18, child: CustomPaint(painter: _SwatchPainter(Garment(10, z.pattern, 1, 0, -1), -1))),
        ]),
        const SizedBox(height: 2),
        Text('${st(lang, 'pattern')}: ${st(lang, kPatternKeys[z.pattern])}', style: const TextStyle(fontSize: 11)),
        Text('${'🌡' * (o.$1 + 1)}  ${'✦' * (o.$2 + 1)}', style: const TextStyle(fontSize: 11)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = kSeasonLooks[z.season];
    final scene = Stack(fit: StackFit.expand, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [look.skyTop, look.skyBottom]),
        ),
      ),
      CustomPaint(painter: _OutfitPainter(z, List<int>.of(pick), t)),
      Positioned(left: 8, top: 8, child: _brief()),
      if (lastScore > -999)
        Positioned(
          right: 8,
          top: 8,
          child: SBadge(lastScore >= z.target ? Icons.emoji_events : Icons.replay, '$lastScore / ${z.target}'),
        ),
    ]);
    final panel = Column(children: [
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
              child: SChip(
                selected: slot == i,
                onTap: () => setState(() => slot = i),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(kSlotIcons[i], size: 16),
                  const SizedBox(width: 4),
                  Text(st(lang, kSlotKeys[i]), style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
        ]),
      ),
      Expanded(
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
          for (var k = 0; k < z.options[slot].length; k++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SChip(
                selected: pick[slot] == k,
                onTap: () => setState(() {
                  pick[slot] = k;
                  play.sfx(Sfx.tap);
                }),
                child: SizedBox(width: 58, height: 64, child: CustomPaint(painter: _SwatchPainter(z.options[slot][k], slot))),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Row(children: [
          if (!calm) Text('${st(lang, 'tries')} ${3 - tries}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          FilledButton.icon(onPressed: _show, icon: const Icon(Icons.star_outline), label: Text(st(lang, 'showLook'))),
        ]),
      ),
    ]);
    return SimFrame(
      play: play,
      moneyIcon: Icons.checkroom,
      money: st(lang, kOccasionKeys[z.occasion]),
      sub: '',
      goalText: '${st(lang, 'target')} ${z.target}',
      progress: lastScore <= 0 ? 0.0 : lastScore / z.target,
      season: z.season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      sceneFlex: 6,
      panelFlex: 3,
      scene: ClipRRect(borderRadius: BorderRadius.circular(18), child: scene),
      panel: panel,
    );
  }
}

class _OutfitPainter extends CustomPainter {
  final StylePuzzle z;
  final List<int> pick;
  final double t;
  _OutfitPainter(this.z, this.pick, this.t);

  @override
  void paint(Canvas c, Size s) {
    final w = math.min(s.width, s.height * 0.62);
    c.save();
    c.translate(s.width / 2 - w / 2 + w * 0.12, 0);
    paintOutfit(c, Size(w, s.height), z, pick, t);
    c.restore();
    paintSeasonParticles(c, s, z.season, t, count: 8);
  }

  @override
  bool shouldRepaint(covariant _OutfitPainter old) => true;
}

class _SwatchPainter extends CustomPainter {
  final Garment g;
  final int slot;
  _SwatchPainter(this.g, this.slot);

  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(2, 2, s.width - 4, slot < 0 ? s.height - 4 : s.height - 16);
    final p = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)));
    paintPattern(c, p, r, g.pat, kHues[g.hue]);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), stroke(const Color(0x33000000), 1));
    if (slot < 0) return;
    if (slot == 3) drawIcon(c, const [Icons.wb_sunny, Icons.waves, Icons.shopping_bag, Icons.umbrella][g.acc], r.center, 20, Colors.white);
    for (var i = 0; i <= g.warm; i++) {
      c.drawCircle(Offset(6 + i * 7.0, s.height - 7), 2.5, fill(const Color(0xFFC8553D)));
    }
    for (var i = 0; i <= g.formal; i++) {
      c.drawCircle(Offset(s.width - 6 - i * 7.0, s.height - 7), 2.5, fill(const Color(0xFF2E5E8C)));
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) => old.g != g;
}
