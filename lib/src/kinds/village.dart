import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

// =================================================================== Kasaba Hayatı (rahat yaşam simülasyonu)
//
// Gün saat saat geçer (06:00-22:00). Her iş bir saat sürer: ekmek, sulamak,
// toplamak, balık tutmak, ormanda dolaşmak, tezgâhta bir şey yapmak.
// Komşuların istekleri gün bitmeden teslim edilir; teslim etmek saat harcamaz.

/// Eşyalar: 0 domates, 1 çilek, 2 kabak, 3 balık, 4 deniz kabuğu, 5 odun,
/// 6 böğürtlen, 7 reçel, 8 turta, 9 sandalye, 10 çorba, 11 kolye.
const List<String> kVilItem = ['🍅', '🍓', '🎃', '🐟', '🐚', '🪵', '🫐', '🍯', '🥧', '🪑', '🍲', '📿'];
const List<String> kVilKeys = [
  'vTomato', 'vStrawberry', 'vPumpkin', 'vFish', 'vShell', 'vWood', 'vBerry', 'vJam', 'vPie', 'vChair', 'vSoup', 'vNecklace'
];

/// Ekin büyüme süreleri (saat): domates, çilek, kabak.
const List<int> kCropHours = [3, 4, 6];

/// Tarifler: ürün -> malzemeler.
const Map<int, List<int>> kRecipes = {
  7: [1, 1], // reçel: 2 çilek
  8: [2, 6], // turta: kabak + böğürtlen
  9: [5, 5], // sandalye: 2 odun
  10: [3, 0], // çorba: balık + domates
  11: [4, 4], // kolye: 2 kabuk
};

const int kDayStart = 6;
const int kDayEnd = 22;
const int kPlots = 4;

class VilRequest {
  final int who;
  final int item;
  final int qty;
  const VilRequest(this.who, this.item, this.qty);
}

class VillagePuzzle extends SPuzzle {
  final int season;
  final List<VilRequest> requests;
  final List<int> fishSeq;
  final List<int> forestSeq;
  final int par;
  const VillagePuzzle(this.season, this.requests, this.fishSeq, this.forestSeq, this.par);
}

class Plot {
  int crop = -1;
  bool watered = false;
  int growth = 0;
  bool get ripe => crop >= 0 && watered && growth >= kCropHours[crop];
}

class VillageSim {
  final VillagePuzzle z;
  int hour = kDayStart;
  final List<int> inv = List<int>.filled(kVilItem.length, 0);
  final List<Plot> plots = [for (var i = 0; i < kPlots; i++) Plot()];
  final List<bool> done;
  int fishI = 0;
  int forestI = 0;
  int crafted = 0;
  int harvested = 0;
  VillageSim(this.z) : done = List<bool>.filled(z.requests.length, false);

  bool get allDone => done.every((x) => x);
  bool get outOfTime => hour >= kDayEnd;
  int get used => hour - kDayStart;

  void _pass() {
    hour++;
    for (final p in plots) {
      if (p.crop >= 0 && p.watered) p.growth++;
    }
  }

  bool plant(int i, int crop) {
    final p = plots[i];
    if (outOfTime || p.crop >= 0) return false;
    p.crop = crop;
    p.watered = false;
    p.growth = 0;
    _pass();
    return true;
  }

  bool water(int i) {
    final p = plots[i];
    if (outOfTime || p.crop < 0 || p.watered) return false;
    p.watered = true;
    _pass();
    return true;
  }

  bool harvest(int i) {
    final p = plots[i];
    if (outOfTime || !p.ripe) return false;
    inv[p.crop] += 2;
    p.crop = -1;
    p.watered = false;
    p.growth = 0;
    harvested++;
    _pass();
    return true;
  }

  bool fish() {
    if (outOfTime) return false;
    inv[z.fishSeq[fishI % z.fishSeq.length]]++;
    fishI++;
    _pass();
    return true;
  }

  bool forest() {
    if (outOfTime) return false;
    inv[z.forestSeq[forestI % z.forestSeq.length]]++;
    forestI++;
    _pass();
    return true;
  }

  bool canCraft(int item) {
    final need = kRecipes[item];
    if (need == null) return false;
    final c = List<int>.of(inv);
    for (final x in need) {
      if (c[x] <= 0) return false;
      c[x]--;
    }
    return true;
  }

  bool craft(int item) {
    if (outOfTime || !canCraft(item)) return false;
    for (final x in kRecipes[item]!) {
      inv[x]--;
    }
    inv[item]++;
    crafted++;
    _pass();
    return true;
  }

  bool deliver(int r) {
    if (done[r]) return false;
    final q = z.requests[r];
    if (inv[q.item] < q.qty) return false;
    inv[q.item] -= q.qty;
    done[r] = true;
    return true;
  }

  /// Açık isteklerin ham malzeme ihtiyacı (eldekiler düşülmeden).
  List<int> need() {
    final n = List<int>.filled(kVilItem.length, 0);
    for (var r = 0; r < z.requests.length; r++) {
      if (done[r]) continue;
      final q = z.requests[r];
      n[q.item] += q.qty;
    }
    return n;
  }

  /// Bot: teslim et, yap, topla, sula, ek, balık tut, ormana git.
  bool botAct() {
    for (var r = 0; r < z.requests.length; r++) {
      if (deliver(r)) return true;
    }
    final n = need();
    // Yapılacak ürünlerin eksiği ham malzeme ihtiyacına eklenir.
    final raw = List<int>.of(n);
    for (final e in kRecipes.entries) {
      final miss = math.max(0, n[e.key] - inv[e.key]);
      raw[e.key] = 0;
      for (final x in e.value) {
        raw[x] += miss;
      }
    }
    for (final e in kRecipes.entries) {
      if (n[e.key] > inv[e.key] && craft(e.key)) return true;
    }
    for (var i = 0; i < kPlots; i++) {
      if (harvest(i)) return true;
    }
    for (var i = 0; i < kPlots; i++) {
      if (water(i)) return true;
    }
    for (final crop in const [2, 1, 0]) {
      var have = inv[crop];
      for (final p in plots) {
        if (p.crop == crop) have += 2;
      }
      if (raw[crop] > have) {
        for (var i = 0; i < kPlots; i++) {
          if (plots[i].crop < 0) return plant(i, crop);
        }
      }
    }
    if (raw[3] > inv[3] || raw[4] > inv[4]) return fish();
    if (raw[5] > inv[5] || raw[6] > inv[6]) return forest();
    if (outOfTime) return false;
    _pass(); // bekle
    return true;
  }
}

/// Botun bütün istekleri bitirdiği saat sayısı (-1: yetişmedi).
int villageBot(VillagePuzzle z) {
  final s = VillageSim(z);
  for (var guard = 0; guard < 200; guard++) {
    if (s.allDone) return s.used;
    if (!s.botAct()) break;
  }
  return s.allDone ? s.used : -1;
}

class VillageKind extends SimKind {
  @override
  String get id => 'hayat';
  const VillageKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final season = r.nextInt(4);
    final fishSeq = [for (var i = 0; i < 24; i++) r.chance(0.3) ? 4 : 3];
    final forestSeq = [for (var i = 0; i < 24; i++) r.chance(0.45) ? 6 : 5];
    final count = 2 + d ~/ 3;
    final pool = <int>[0, 1, 2, 3, 4, 5, 6, if (d >= 2) ...[7, 9], if (d >= 4) ...[10, 11], if (d >= 6) 8];
    final req = <VilRequest>[];
    final used = <int>{};
    for (var i = 0; i < count; i++) {
      var item = r.pick(pool);
      for (var a = 0; a < 6 && used.contains(item); a++) {
        item = r.pick(pool);
      }
      used.add(item);
      final qty = kRecipes.containsKey(item) ? 1 + (d >= 7 && r.chance(0.3) ? 1 : 0) : 1 + r.nextInt(d >= 5 ? 3 : 2);
      req.add(VilRequest(r.nextInt(6), item, qty));
    }
    final probe = VillagePuzzle(season, req, fishSeq, forestSeq, 0);
    final par = villageBot(probe);
    if (par < 0 || par > kDayEnd - kDayStart) return null;
    return VillagePuzzle(season, req, fishSeq, forestSeq, par);
  }

  @override
  bool check(SPuzzle p) =>
      p is VillagePuzzle && p.requests.isNotEmpty && p.par > 0 && p.par <= kDayEnd - kDayStart && villageBot(p) == p.par;

  @override
  Widget build(SimPlay play) => _VillageView(play: play);

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('crafted', 'Yapılan eşya', 'Items crafted', scale: 20),
        const GameStat('harvested', 'Toplanan hasat', 'Harvests', scale: 20),
      ];

  @override
  List<MissionTemplate> get missions => [
        ...super.missions,
        const MissionTemplate('crafted', 'crafted', [5, 25, 80]),
        const MissionTemplate('harvested', 'harvested', [5, 25, 80]),
      ];
}

const List<String> kNeighbors = ['👵', '👴', '👩‍🌾', '🧑‍🍳', '👧', '🧔'];

class _VillageView extends StatefulWidget {
  final SimPlay play;
  const _VillageView({required this.play});

  @override
  State<_VillageView> createState() => _VillageViewState();
}

class _VillageViewState extends State<_VillageView> {
  late final VillagePuzzle z = widget.play.puzzle as VillagePuzzle;
  late VillageSim s = VillageSim(z);
  int seed = 0; // ekilecek tohum
  bool calm = false;
  bool ended = false;
  final Stopwatch watch = Stopwatch()..start();

  SimPlay get play => widget.play;
  String get lang => play.lang;

  @override
  void initState() {
    super.initState();
    calm = play.zenMode || SimPrefs.calm;
    SimPrefs.init().then((_) {
      if (mounted) setState(() => calm = play.zenMode || SimPrefs.calm);
    });
  }

  void _did(bool ok, [Sfx good = Sfx.place]) {
    setState(() {});
    play.sfx(ok ? good : Sfx.error);
    _checkEnd();
  }

  void _checkEnd() {
    if (ended) return;
    final secs = watch.elapsed.inSeconds;
    if (s.allDone) {
      ended = true;
      play.sfx(Sfx.win);
      final stars = s.used <= z.par ? 3 : (s.used <= z.par + 2 ? 2 : 1);
      play.win(stars: stars, calm: calm, score: 100 * z.requests.length + 10 * (kDayEnd - s.hour), seconds: secs,
          stats: {'crafted': s.crafted, 'harvested': s.harvested});
    } else if (s.outOfTime && !calm) {
      ended = true;
      play.sfx(Sfx.lose);
      play.lose(score: 100 * s.done.where((x) => x).length, seconds: secs, stats: {'crafted': s.crafted, 'harvested': s.harvested});
    } else if (s.outOfTime && calm) {
      // Sakin mod: yeni gün başlar, eşyalar ve teslimler korunur.
      s.hour = kDayStart;
    }
  }

  void _plot(int i) {
    if (ended) return;
    final p = s.plots[i];
    if (p.crop < 0) {
      _did(s.plant(i, seed));
    } else if (!p.watered) {
      _did(s.water(i));
    } else if (p.ripe) {
      _did(s.harvest(i), Sfx.coin);
    } else {
      play.sfx(Sfx.tap);
    }
  }

  void _deliver(int r) {
    if (ended) return;
    _did(s.deliver(r), Sfx.combo);
  }

  @override
  Widget build(BuildContext context) {
    final scene = SceneCanvas(
      semantics: st(lang, 'vVillage'),
      paint: (c, size) => _paintVillage(c, size),
      onTap: (pos, size) {
        if (ended) return;
        final x = pos.dx / size.width, y = pos.dy / size.height;
        if (y > 0.55 && x < 0.62) {
          _plot(clampI((x / 0.62 * kPlots).floor(), 0, kPlots - 1));
        } else if (x >= 0.62 && y > 0.5) {
          _did(s.fish());
        } else if (x >= 0.62 && y <= 0.5) {
          _did(s.forest());
        } else {
          play.sfx(Sfx.tap);
        }
      },
    );
    final open = [for (var r = 0; r < z.requests.length; r++) if (!s.done[r]) r];
    return SimFrame(
      play: play,
      moneyIcon: Icons.schedule,
      money: '${s.hour.toString().padLeft(2, '0')}:00',
      sub: '${st(lang, 'vRequests')} ${z.requests.length - open.length}/${z.requests.length}',
      goalText: '${st(lang, 'vUntil')} ${kDayEnd.toString()}:00',
      progress: (z.requests.length - open.length) / z.requests.length,
      season: z.season,
      calm: calm,
      onCalm: (v) => setState(() {
        calm = v;
        SimPrefs.calm = v;
      }),
      sceneFlex: 5,
      panelFlex: 5,
      scene: scene,
      panel: _panel(open),
    );
  }

  Widget _panel(List<int> open) {
    final items = [for (var i = 0; i < kVilItem.length; i++) if (s.inv[i] > 0) i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var c = 0; c < 3; c++)
            SChip(
              selected: seed == c,
              onTap: () => setState(() => seed = c),
              tooltip: st(lang, 'vPlant'),
              child: Text('🌱${kVilItem[c]} ${kCropHours[c]}h', style: const TextStyle(fontSize: 14)),
            ),
        ]),
        const SizedBox(height: 6),
        for (final r in open)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SNote(
              '${kNeighbors[z.requests[r].who]} ${z.requests[r].qty}× ${kVilItem[z.requests[r].item]} ${st(lang, kVilKeys[z.requests[r].item])}',
              icon: s.inv[z.requests[r].item] >= z.requests[r].qty ? Icons.card_giftcard : Icons.hourglass_empty,
              onTap: () => _deliver(r),
            ),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in kRecipes.entries)
            SChip(
              selected: s.canCraft(e.key),
              onTap: ended ? null : () => _did(s.craft(e.key)),
              tooltip: st(lang, 'vCraft'),
              child: Text('${e.value.map((x) => kVilItem[x]).join('+')}→${kVilItem[e.key]}', style: const TextStyle(fontSize: 14)),
            ),
        ]),
        const SizedBox(height: 6),
        Text(items.isEmpty ? '—' : items.map((i) => '${kVilItem[i]}${s.inv[i]}').join('  '), style: const TextStyle(fontSize: 18)),
      ]),
    );
  }

  void _paintVillage(Canvas c, Size size) {
    paintSky(c, size, z.season, groundAt: 0.5);
    final w = size.width, h = size.height;
    // ev
    final hx = w * 0.08, hy = h * 0.18;
    c.drawRect(Rect.fromLTWH(hx, hy + h * 0.1, w * 0.22, h * 0.22), fill(const Color(0xFFF6E3C6)));
    c.drawPath(
        Path()
          ..moveTo(hx - 6, hy + h * 0.1)
          ..lineTo(hx + w * 0.11, hy - h * 0.02)
          ..lineTo(hx + w * 0.22 + 6, hy + h * 0.1)
          ..close(),
        fill(const Color(0xFFC8553D)));
    c.drawRect(Rect.fromLTWH(hx + w * 0.085, hy + h * 0.2, w * 0.05, h * 0.12), fill(const Color(0xFF8A5A36)));
    // orman
    for (var i = 0; i < 4; i++) {
      final x = w * (0.68 + i * 0.08), y = h * (0.3 + (i % 2) * 0.06);
      c.drawRect(Rect.fromLTWH(x - 2, y, 4, h * 0.12), fill(const Color(0xFF7A4E2D)));
      c.drawCircle(Offset(x, y), h * 0.07, fill(const Color(0xFF3F7D3A)));
    }
    drawLabel(c, '🪓', Offset(w * 0.81, h * 0.12), 18, Colors.black);
    // gölet
    c.drawOval(Rect.fromLTWH(w * 0.66, h * 0.62, w * 0.3, h * 0.26), fill(const Color(0xFF4FA3D9)));
    drawLabel(c, '🎣', Offset(w * 0.81, h * 0.75), 20, Colors.black);
    // tarlalar
    final pw = w * 0.62 / kPlots;
    for (var i = 0; i < kPlots; i++) {
      final r = Rect.fromLTWH(6 + i * pw, h * 0.6, pw - 10, h * 0.32);
      final p = s.plots[i];
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)),
          fill(p.watered ? const Color(0xFF6B4A2E) : const Color(0xFF9C7350)));
      if (p.crop >= 0) {
        final g = clampD(p.growth / kCropHours[p.crop], 0, 1);
        if (p.ripe) {
          drawLabel(c, kVilItem[p.crop], r.center, 24, Colors.black);
        } else {
          c.drawCircle(r.center, 4 + 8 * g, fill(const Color(0xFF6FBF4A)));
          if (!p.watered) drawLabel(c, '💧', r.center + const Offset(0, -18), 14, Colors.black);
        }
      } else {
        drawLabel(c, '＋', r.center, 18, const Color(0xCCFFFFFF));
      }
    }
    // güneşin yeri saate göre
    final f = clampD((s.hour - kDayStart) / (kDayEnd - kDayStart), 0, 1);
    c.drawCircle(Offset(w * (0.05 + 0.9 * f), h * (0.12 - 0.08 * math.sin(f * math.pi))), 10,
        fill(f > 0.8 ? const Color(0xFFF08A4B) : const Color(0xFFFFD54A)));
  }
}
