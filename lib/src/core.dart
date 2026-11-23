import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'texts.dart';

/// Bir simülasyon bölümünün kurulmuş hâli.
abstract class SPuzzle {
  const SPuzzle();
}

class SLevel {
  final String kind;
  final int d;

  /// Bölümün başladığı mevsim (0 ilkbahar, 1 yaz, 2 sonbahar, 3 kış).
  final int season;
  final SPuzzle puzzle;
  const SLevel(this.kind, this.d, this.season, this.puzzle);
}

/// Boşta ve simülasyon oyun türü: bölüm üretir, botla denetler, ekranı kurar.
abstract class SimKind {
  const SimKind();
  String get id;

  /// Zorluk 1..10 için deterministik bölüm (kurulamazsa null).
  SPuzzle? make(int d, SeededRandom r);

  /// Bölümün kurallara uyduğunu ve bir botun hedefe ulaşabildiğini denetler.
  bool check(SPuzzle p);

  Widget build(SimPlay play);

  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan bölüm', 'Levels completed', scale: 10),
        GameStat('perfect', 'Üç yıldızlı bölüm', 'Three-star levels', scale: 10),
        GameStat('calm_rounds', 'Sakin modda bölüm', 'Calm mode levels', scale: 5),
      ];

  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];
}

SPuzzle realizeSim(SimKind k, int d, int seed) {
  for (var dd = d; dd >= 1; dd--) {
    for (var a = 0; a < 12; a++) {
      SPuzzle? p;
      try {
        p = k.make(dd, SeededRandom(mixSeed([seed, a, dd, 5303])));
      } catch (_) {
        p = null;
      }
      if (p != null && k.check(p)) return p;
    }
  }
  throw StateError('simülasyon bölümü kurulamadı: ${k.id} $d');
}

class SimRules extends GameRules<SLevel> {
  @override
  final String gameId;
  final SimKind kind;
  final int levels;
  SimRules({required this.gameId, required this.kind, this.levels = 100000});

  @override
  int get levelCount => levels;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.zen];

  @override
  List<GameStat> get gameStats => kind.stats;

  @override
  List<MissionTemplate> get missionTemplates => kind.missions;

  @override
  SLevel generate(LevelSpec spec) {
    final d = clampI(spec.difficulty, 1, 10);
    final season = mixSeed([spec.seed, 4401]) % 4;
    return SLevel(kind.id, d, season, realizeSim(kind, d, spec.seed));
  }

  @override
  Validation validate(SLevel puzzle, LevelSpec spec) =>
      puzzle.kind == kind.id && kind.check(puzzle.puzzle) ? const Validation.ok() : const Validation.fail('invalid');
}

/// Oyun ekranının kabukla konuştuğu yüz.
class SimPlay {
  final PlayContext ctx;
  final SPuzzle puzzle;
  final int d;
  final int seed;
  final int season;
  final String gameId;
  const SimPlay({required this.ctx, required this.puzzle, required this.d, required this.seed, required this.season, required this.gameId});

  String get lang => ctx.lang;

  /// Kabuktaki "Zen" modu: her zaman sakin.
  bool get zenMode => ctx.spec.mode == GameModeId.zen;

  bool get reducedMotion => ctx.reducedMotion;

  void sfx(Sfx s) => ctx.sfx(s);

  String get _saveKey => '${ctx.spec.levelId}:${ctx.spec.seed}';

  /// Bölüm durumunu saklar (uygulama kapanırsa kaldığı yerden sürer).
  void save(Map<String, Object?> state) {
    ctx.saveResume({...state, 'sim_key': _saveKey, 'sim_ts': DateTime.now().millisecondsSinceEpoch});
  }

  /// Bu bölüme ait kayıt (başka bölümünse boş).
  Map<String, Object?> get restored {
    final r = ctx.resume;
    return r['sim_key'] == _saveKey ? r : const {};
  }

  /// Kayıttan bu yana geçen süre (saniye, en çok [cap]).
  int awaySeconds({int cap = 7200}) {
    final ts = restored['sim_ts'];
    if (ts is! int) return 0;
    final s = (DateTime.now().millisecondsSinceEpoch - ts) ~/ 1000;
    return clampI(s, 0, cap);
  }

  void win({required int stars, bool calm = false, int score = 0, int seconds = 0, Map<String, int> stats = const {}}) {
    final s = calm ? 3 : clampI(stars, 1, 3);
    SimPrefs.addRenown(gameId, s);
    ctx.finish(RoundResult(
      won: true,
      score: score < 0 ? 0 : score,
      stars: s,
      seconds: seconds,
      gameStats: {'rounds_won': 1, if (s == 3) 'perfect': 1, if (calm) 'calm_rounds': 1, ...stats},
    ));
  }

  void lose({int score = 0, int seconds = 0, String? headline, Map<String, int> stats = const {}}) {
    ctx.finish(RoundResult(won: false, score: score < 0 ? 0 : score, seconds: seconds, headline: headline, gameStats: stats));
  }
}

class SimStage extends StatelessWidget {
  final PlayContext ctx;
  final SimRules rules;
  const SimStage({super.key, required this.ctx, required this.rules});

  @override
  Widget build(BuildContext context) {
    final lv = ctx.generated.puzzle as SLevel;
    return rules.kind.build(SimPlay(ctx: ctx, puzzle: lv.puzzle, d: lv.d, seed: ctx.spec.seed, season: lv.season, gameId: rules.gameId));
  }
}

SimRules simRules(String gameId, SimKind kind) => SimRules(gameId: gameId, kind: kind);

// ---------------------------------------------------------------- kalıcı ayarlar

/// Oyunlar arası kalıcı küçük ayarlar (sakin mod, ün, süsler). Eklenti
/// yoksa (testler) bellekte tutulur.
class SimPrefs {
  static SharedPreferences? _p;
  static bool _tried = false;
  static final Map<String, Object> _mem = {};

  static Future<void> init() async {
    if (_tried) return;
    _tried = true;
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      _p = null;
    }
  }

  static bool getBool(String k, [bool def = false]) {
    final p = _p;
    if (p != null) {
      try {
        return p.getBool(k) ?? def;
      } catch (_) {}
    }
    final v = _mem[k];
    return v is bool ? v : def;
  }

  static int getInt(String k, [int def = 0]) {
    final p = _p;
    if (p != null) {
      try {
        return p.getInt(k) ?? def;
      } catch (_) {}
    }
    final v = _mem[k];
    return v is int ? v : def;
  }

  static String getString(String k, [String def = '']) {
    final p = _p;
    if (p != null) {
      try {
        return p.getString(k) ?? def;
      } catch (_) {}
    }
    final v = _mem[k];
    return v is String ? v : def;
  }

  static void setBool(String k, bool v) {
    _mem[k] = v;
    final p = _p;
    if (p != null) unawaited(p.setBool(k, v).then((_) => true, onError: (_) => false));
  }

  static void setInt(String k, int v) {
    _mem[k] = v;
    final p = _p;
    if (p != null) unawaited(p.setInt(k, v).then((_) => true, onError: (_) => false));
  }

  static void setString(String k, String v) {
    _mem[k] = v;
    final p = _p;
    if (p != null) unawaited(p.setString(k, v).then((_) => true, onError: (_) => false));
  }

  static bool get calm => getBool('sim_calm');
  static set calm(bool v) => setBool('sim_calm', v);

  /// Ün: kazanılan yıldızların toplamı. Gelire en çok %25 kalıcı katkı.
  static int renown(String gameId) => getInt('sim_renown_$gameId');
  static void addRenown(String gameId, int stars) => setInt('sim_renown_$gameId', renown(gameId) + stars);
  static double renownMul(String gameId) => 1 + math.min(25, renown(gameId)) / 100;

  static List<Sticker> decor(String gameId) {
    final s = getString('sim_decor_$gameId');
    final out = <Sticker>[];
    for (final part in s.split(';')) {
      final xs = part.split(',');
      if (xs.length != 3) continue;
      final x = double.tryParse(xs[0]), y = double.tryParse(xs[1]), i = int.tryParse(xs[2]);
      if (x == null || y == null || i == null) continue;
      out.add(Sticker(clampD(x, 0, 1), clampD(y, 0, 1), i % kStickers.length));
    }
    return out;
  }

  static void setDecor(String gameId, List<Sticker> list) => setString(
      'sim_decor_$gameId', list.map((s) => '${s.x.toStringAsFixed(3)},${s.y.toStringAsFixed(3)},${s.icon}').join(';'));
}

class Sticker {
  final double x;
  final double y;
  final int icon;
  const Sticker(this.x, this.y, this.icon);
}

const List<IconData> kStickers = [
  Icons.local_florist,
  Icons.park,
  Icons.eco,
  Icons.filter_vintage,
  Icons.emoji_nature,
  Icons.light,
  Icons.chair,
  Icons.flag,
  Icons.star_rounded,
  Icons.favorite,
  Icons.wb_sunny,
  Icons.ac_unit,
  Icons.cottage,
  Icons.water_drop,
];

const List<Color> kStickerColors = [
  Color(0xFFE07A5F),
  Color(0xFF4F7F52),
  Color(0xFF6A994E),
  Color(0xFFB56576),
  Color(0xFF3A8D8C),
  Color(0xFFD9A441),
  Color(0xFF7F5539),
  Color(0xFF2E5E8C),
  Color(0xFFE9C46A),
  Color(0xFFC8553D),
  Color(0xFFF4A261),
  Color(0xFF8EC5E8),
  Color(0xFF9C6644),
  Color(0xFF4A90C2),
];

// ---------------------------------------------------------------- mevsimler

const int kSeasonLen = 45;
const List<String> kSeasonKeys = ['spring', 'summer', 'autumn', 'winter'];
const List<IconData> kSeasonIcons = [Icons.local_florist, Icons.wb_sunny, Icons.eco, Icons.ac_unit];

class SeasonLook {
  final Color skyTop;
  final Color skyBottom;
  final Color ground;
  final Color accent;
  const SeasonLook(this.skyTop, this.skyBottom, this.ground, this.accent);
}

const List<SeasonLook> kSeasonLooks = [
  SeasonLook(Color(0xFFBFE3F2), Color(0xFFF3EBD8), Color(0xFF8DBF6A), Color(0xFFF2A7B8)),
  SeasonLook(Color(0xFF8CCBEB), Color(0xFFFFF1C9), Color(0xFF6FA84F), Color(0xFFF6C344)),
  SeasonLook(Color(0xFFE8C9A0), Color(0xFFF6E7D2), Color(0xFFB98A4E), Color(0xFFD9772F)),
  SeasonLook(Color(0xFFC9D6E3), Color(0xFFF1F4F7), Color(0xFFE6ECF1), Color(0xFF7FA6C9)),
];

String seasonName(String lang, int s) => st(lang, kSeasonKeys[s % 4]);

/// Mevsime göre süzülen küçük parçacıklar (çiçek yaprağı, ışık, yaprak, kar).
void paintSeasonParticles(Canvas c, Size size, int season, double t, {int count = 14}) {
  final s = season % 4;
  final col = [const Color(0xCCF6B5C6), const Color(0x88FFF3B0), const Color(0xCCD98C3A), const Color(0xEEFFFFFF)][s];
  final p = fill(col);
  for (var i = 0; i < count; i++) {
    final seed = i * 97.31;
    final speed = 12 + (i * 7) % 11;
    final x = (seed * 13.7 + math.sin(t * 0.7 + i) * 18) % size.width;
    final y = ((t * speed + seed * 31) % (size.height + 20)) - 10;
    final r = s == 3 ? 2.2 + (i % 3) : 2.5 + (i % 2);
    if (s == 2) {
      c.save();
      c.translate(x, y);
      c.rotate(t + i);
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 2.6, height: r * 1.4), p);
      c.restore();
    } else {
      c.drawCircle(Offset(x, y), r, p);
    }
  }
}

// ---------------------------------------------------------------- sayı biçimi

String fmtNum(num v) {
  final x = v.toDouble();
  if (x.isNaN || x.isInfinite) return '∞';
  final a = x.abs();
  if (a < 1000) {
    if (a < 10 && (x - x.roundToDouble()).abs() > 0.05) return x.toStringAsFixed(1);
    return x.round().toString();
  }
  const units = ['K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx', 'Sp', 'Oc', 'No', 'Dc'];
  var u = -1;
  var y = a;
  while (y >= 1000 && u < units.length - 1) {
    y /= 1000;
    u++;
  }
  final s = y >= 100 ? y.toStringAsFixed(0) : (y >= 10 ? y.toStringAsFixed(1) : y.toStringAsFixed(2));
  return '${x < 0 ? '-' : ''}$s${units[u]}';
}

/// Hedefi okunur hâle getirir: iki anlamlı basamağa aşağı yuvarlar.
double niceFloor(double v) {
  if (v <= 10) return v.floorToDouble();
  final e = (math.log(v) / math.ln10).floor() - 1;
  final p = math.pow(10, e).toDouble();
  return (v / p).floorToDouble() * p;
}

int clampI(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Süreye göre yıldız: botun süresinde ya da daha hızlı 3, biraz fazlasında 2.
int starsByTime(int seconds, int par) {
  if (seconds <= par) return 3;
  if (seconds <= par * 3 ~/ 2 + 20) return 2;
  return 1;
}

// ---------------------------------------------------------------- saat

/// Saniye sayacı, oyun döngüsü ve iptal edilebilen gecikmeler.
mixin SimClock<T extends StatefulWidget> on State<T> {
  int seconds = 0;
  bool ended = false;
  Timer? _sec;
  Timer? _loop;
  final List<Timer> _later = [];

  /// [onTick] her [ms] milisaniyede bir çağrılır (oyun döngüsü).
  void startLoop(int ms, void Function(double dt) onTick) {
    _sec?.cancel();
    _loop?.cancel();
    _sec = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ended && mounted) seconds++;
    });
    _loop = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!ended && mounted) setState(() => onTick(ms / 1000));
    });
  }

  void stopLoop() {
    _sec?.cancel();
    _loop?.cancel();
  }

  void later(int ms, VoidCallback f) {
    _later.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) f();
    }));
  }

  @override
  void dispose() {
    _sec?.cancel();
    _loop?.cancel();
    for (final t in _later) {
      t.cancel();
    }
    super.dispose();
  }

  String clock([int? s]) {
    final v = s ?? seconds;
    return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------- çizim yardımcıları

Paint fill(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

Paint stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

void drawLabel(Canvas c, String s, Offset center, double size, Color color, {FontWeight weight = FontWeight.w700}) {
  if (s.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.0)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

/// Simge yazı tipindeki bir simgeyi tuvale çizer.
void drawIcon(Canvas c, IconData icon, Offset center, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(fontSize: size, color: color, fontFamily: icon.fontFamily, package: icon.fontPackage, height: 1.0),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

void paintSky(Canvas c, Size s, int season, {double groundAt = 0.72}) {
  final look = kSeasonLooks[season % 4];
  final rect = Offset.zero & s;
  c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [look.skyTop, look.skyBottom])
            .createShader(rect));
  final gy = s.height * groundAt;
  c.drawRect(Rect.fromLTWH(0, gy, s.width, s.height - gy), fill(look.ground));
}

/// Kendi boyutuna çizen, dokunuşu yerel koordinatla bildiren tuval.
class SceneCanvas extends StatelessWidget {
  final void Function(Canvas c, Size s) paint;
  final void Function(Offset p, Size s)? onTap;
  final void Function(Offset p, Size s)? onPan;
  final VoidCallback? onPanEnd;
  final String? semantics;
  const SceneCanvas({super.key, required this.paint, this.onTap, this.onPan, this.onPanEnd, this.semantics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth.isFinite ? box.maxWidth : 360, box.maxHeight.isFinite ? box.maxHeight : 300);
      final t = onTap, pn = onPan, pe = onPanEnd;
      return Semantics(
        label: semantics,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: t == null ? null : (e) => t(e.localPosition, size),
          onPanStart: pn == null ? null : (e) => pn(e.localPosition, size),
          onPanUpdate: pn == null ? null : (e) => pn(e.localPosition, size),
          onPanEnd: pe == null ? null : (_) => pe(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CustomPaint(size: size, painter: _FnPainter(paint)),
          ),
        ),
      );
    });
  }
}

class _FnPainter extends CustomPainter {
  final void Function(Canvas c, Size s) fn;
  _FnPainter(this.fn);

  @override
  void paint(Canvas canvas, Size size) => fn(canvas, size);

  @override
  bool shouldRepaint(covariant _FnPainter old) => true;
}

// ---------------------------------------------------------------- arayüz parçaları

class SChip extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;
  const SChip({super.key, required this.child, this.selected = false, this.onTap, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.surface;
    final w = Material(
      color: selected ? Color.lerp(c, scheme.primary, 0.35) : c,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? scheme.primary : Colors.black12, width: selected ? 2.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), child: child),
      ),
    );
    final tt = tooltip;
    return tt == null ? w : Tooltip(message: tt, child: w);
  }
}

/// Küçük bilgi rozeti: simge + değer.
class SBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const SBadge(this.icon, this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: (color ?? scheme.surface).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

/// Bütün simülasyon oyunlarının ortak çerçevesi: üst bilgi, hedef çubuğu,
/// mevsim, sakin mod, fotoğraf/süsleme modu ve ön plandaki sahne.
class SimFrame extends StatefulWidget {
  final SimPlay play;
  final IconData moneyIcon;
  final String money;
  final String sub;
  final String goalText;
  final double progress;
  final int season;
  final bool calm;
  final ValueChanged<bool> onCalm;
  final Widget scene;
  final Widget? panel;
  final Widget? banner;
  final List<Widget> actions;
  final int sceneFlex;
  final int panelFlex;
  const SimFrame({
    super.key,
    required this.play,
    required this.moneyIcon,
    required this.money,
    this.sub = '',
    required this.goalText,
    required this.progress,
    required this.season,
    required this.calm,
    required this.onCalm,
    required this.scene,
    this.panel,
    this.banner,
    this.actions = const [],
    this.sceneFlex = 5,
    this.panelFlex = 5,
  });

  @override
  State<SimFrame> createState() => _SimFrameState();
}

class _SimFrameState extends State<SimFrame> {
  bool photo = false;
  int pick = 0;
  List<Sticker> decor = [];

  @override
  void initState() {
    super.initState();
    decor = SimPrefs.decor(widget.play.gameId);
    SimPrefs.init().then((_) {
      if (mounted) setState(() => decor = SimPrefs.decor(widget.play.gameId));
    });
  }

  void _addSticker(Offset p, Size s) {
    if (decor.length >= 30) {
      widget.play.sfx(Sfx.error);
      return;
    }
    setState(() => decor = [...decor, Sticker(clampD(p.dx / s.width, 0, 1), clampD(p.dy / s.height, 0, 1), pick)]);
    SimPrefs.setDecor(widget.play.gameId, decor);
    widget.play.sfx(Sfx.place);
  }

  void _removeNear(Offset p, Size s) {
    if (decor.isEmpty) return;
    var best = -1;
    var bd = 1e9;
    for (var i = 0; i < decor.length; i++) {
      final d = (Offset(decor[i].x * s.width, decor[i].y * s.height) - p).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (best >= 0 && bd < 48) {
      setState(() => decor = [...decor]..removeAt(best));
      SimPrefs.setDecor(widget.play.gameId, decor);
      widget.play.sfx(Sfx.clear);
    }
  }

  Widget _decorLayer({required bool editing}) {
    return LayoutBuilder(builder: (context, box) {
      final s = Size(box.maxWidth.isFinite ? box.maxWidth : 360, box.maxHeight.isFinite ? box.maxHeight : 300);
      final icons = Stack(children: [
        for (final sk in decor)
          Positioned(
            left: sk.x * s.width - 16,
            top: sk.y * s.height - 16,
            child: Icon(kStickers[sk.icon], size: 32, color: kStickerColors[sk.icon % kStickerColors.length]),
          ),
      ]);
      if (!editing) return IgnorePointer(child: SizedBox(width: s.width, height: s.height, child: icons));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (e) => _addSticker(e.localPosition, s),
        onLongPressStart: (e) => _removeNear(e.localPosition, s),
        child: SizedBox(width: s.width, height: s.height, child: icons),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final lang = w.play.lang;
    final scheme = Theme.of(context).colorScheme;
    final sceneStack = Stack(fit: StackFit.expand, children: [w.scene, _decorLayer(editing: false)]);
    if (photo) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(children: [
            IconButton(tooltip: st(lang, 'close'), onPressed: () => setState(() => photo = false), icon: const Icon(Icons.close)),
            Expanded(
              child: Text(st(lang, 'decorHelp'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFF7F3EA), width: 10),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  IgnorePointer(child: w.scene),
                  _decorLayer(editing: true),
                  Positioned(
                    right: 10,
                    bottom: 8,
                    child: SBadge(kSeasonIcons[w.season % 4], seasonName(lang, w.season)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              for (var i = 0; i < kStickers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SChip(
                    selected: pick == i,
                    onTap: () => setState(() => pick = i),
                    child: Icon(kStickers[i], color: kStickerColors[i % kStickerColors.length]),
                  ),
                ),
              SChip(
                tooltip: st(lang, 'clearAll'),
                onTap: () {
                  setState(() => decor = []);
                  SimPrefs.setDecor(w.play.gameId, decor);
                },
                child: const Icon(Icons.layers_clear),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ]);
    }
    final banner = w.banner;
    final panel = w.panel;
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        height: 50,
        decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(w.moneyIcon, size: 22, color: const Color(0xFFD9A441)),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(w.money, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ),
          ),
          if (w.sub.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(w.sub, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 13)),
              ),
            ),
          ],
          const Spacer(),
          Tooltip(
            message: seasonName(lang, w.season),
            child: Icon(kSeasonIcons[w.season % 4], color: kSeasonLooks[w.season % 4].accent),
          ),
          ...w.actions,
          IconButton(
            tooltip: st(lang, 'calm'),
            onPressed: w.play.zenMode ? null : () => w.onCalm(!w.calm),
            icon: Icon(w.calm ? Icons.spa : Icons.spa_outlined, color: w.calm ? const Color(0xFF2E9E78) : null),
          ),
          IconButton(tooltip: st(lang, 'photo'), onPressed: () => setState(() => photo = true), icon: const Icon(Icons.photo_camera_outlined)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: clampD(w.progress, 0, 1), minHeight: 9),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(w.goalText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        ]),
      ),
      if (banner != null) Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 0), child: banner),
      Expanded(flex: w.sceneFlex, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 4), child: sceneStack)),
      if (panel != null) Expanded(flex: w.panelFlex, child: panel),
    ]);
  }
}

/// Bilgi şeridi (ör. "Sen yokken: +1,2K").
class SNote extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  const SNote(this.text, {super.key, this.icon = Icons.info_outline, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          ]),
        ),
      ),
    );
  }
}
