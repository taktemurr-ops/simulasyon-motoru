import 'dart:math' as math;

import 'package:studio_core/core/rng.dart';

import 'core.dart';

/// Boşta oyunların temaları.
class IdleTheme {
  static const lantern = 0;
  static const mine = 1;
  static const factory = 2;
  static const farm = 3;
  static const aquarium = 4;
  static const zen = 5;
  static const bee = 6;
  static const tea = 7;
}

/// Geliştirme: hedef >= 0 tek üretici, -1 hepsi, -2 dokunuş, -3 otomatik
/// (hasat makinesi ya da su filtresi).
class Upg {
  final double cost;
  final int target;
  final double mult;
  const Upg(this.cost, this.target, this.mult);
}

/// Hedef türleri: toplam kazanç, saniyelik gelir, bir üreticiden sahip olma.
class GoalType {
  static const earn = 0;
  static const income = 1;
  static const own = 2;
}

class IdlePuzzle extends SPuzzle {
  final int theme;
  final int p;
  final double growth;
  final List<double> cost0;
  final List<double> rate0;
  final List<Upg> upg;
  final List<List<double>> seas;
  final double pt;
  final int season0;
  final int goalType;
  final double goal;
  final int goalK;
  final int par;
  final int limit;
  final List<int> events;
  const IdlePuzzle({
    required this.theme,
    required this.p,
    required this.growth,
    required this.cost0,
    required this.rate0,
    required this.upg,
    required this.seas,
    required this.pt,
    required this.season0,
    required this.goalType,
    required this.goal,
    required this.goalK,
    required this.par,
    required this.limit,
    required this.events,
  });

  bool get bottle => theme == IdleTheme.mine || theme == IdleTheme.factory;
  bool get harvest => theme == IdleTheme.farm;
  bool get cleaning => theme == IdleTheme.aquarium;

  /// Taşıyıcı (asansör / konveyör) dışındaki üretici sayısı.
  int get producers => bottle ? p - 1 : p;

  IdlePuzzle withGoal(int type, double goal, int k, int par) => IdlePuzzle(
        theme: theme,
        p: p,
        growth: growth,
        cost0: cost0,
        rate0: rate0,
        upg: upg,
        seas: seas,
        pt: pt,
        season0: season0,
        goalType: type,
        goal: goal,
        goalK: k,
        par: par,
        limit: limit,
        events: events,
      );
}

/// Boşta ekonomi: üreticiler, kilometre taşları, geliştirmeler, mevsim
/// çarpanları, yeniden kurma (prestij) ve temaya özel kurallar.
class Econ {
  final IdlePuzzle z;
  late List<int> n;
  late List<bool> bought;
  late List<double> _up;
  double _all = 1;
  double _tap = 1;
  bool auto = false;
  double coins = 15;
  double runEarned = 0;
  double levelEarned = 0;
  double store = 0;
  double clean = 1;
  double t = 0;
  int points = 0;
  int prestiges = 0;
  int upgrades = 0;
  double peakIncome = 0;
  late List<int> peakOwn;

  /// Geçici çarpan (bereket olayı, tırmık) ve kalıcı ün çarpanı.
  double boost = 1;
  double extra = 1;

  Econ(this.z) {
    peakOwn = List<int>.filled(z.p, 0);
    reset();
  }

  void reset() {
    n = List<int>.filled(z.p, 0);
    bought = List<bool>.filled(z.upg.length, false);
    coins = 15;
    runEarned = 0;
    store = 0;
    clean = 1;
    _recalc();
  }

  /// Kayıttan dönünce çarpanları yeniden hesaplar.
  void refresh() => _recalc();

  void _recalc() {
    _up = List<double>.filled(z.p, 1);
    _all = 1;
    _tap = 1;
    auto = false;
    for (var i = 0; i < z.upg.length; i++) {
      if (!bought[i]) continue;
      final u = z.upg[i];
      if (u.target >= 0) {
        _up[u.target] *= u.mult;
      } else if (u.target == -1) {
        _all *= u.mult;
      } else if (u.target == -2) {
        _tap *= u.mult;
      } else {
        auto = true;
      }
    }
  }

  int get season => (z.season0 + t ~/ kSeasonLen) % 4;

  static double mile(int c) {
    var m = 1.0;
    for (final x in const [10, 25, 50, 100, 200]) {
      if (c >= x) m *= 2;
    }
    return m;
  }

  double mult(int k, int count) => mile(count) * _up[k] * _all * z.seas[k][season] * (1 + 0.6 * points);

  double prodOf(List<int> nn) {
    var v = 0.0;
    for (var k = 0; k < z.producers; k++) {
      v += nn[k] * z.rate0[k] * mult(k, nn[k]);
    }
    return v;
  }

  double capOf(int c) {
    final k = z.p - 1;
    return (c + 1) * math.pow(1.25, c).toDouble() * z.rate0[k] * mult(k, c);
  }

  double rawOf(List<int> nn) {
    var v = z.bottle ? math.min(prodOf(nn), capOf(nn[z.p - 1])) : prodOf(nn);
    if (z.cleaning) v *= 0.4 + 0.6 * clean;
    return v;
  }

  /// Saniyelik gelir (geçici ve kalıcı çarpanlar dahil).
  double get income => rawOf(n) * boost * extra;

  double get tapValue => (1 + 0.05 * rawOf(n)) * _tap * extra;

  double cost(int k) => z.cost0[k] * math.pow(z.growth, n[k]).toDouble();

  /// [count] adet almanın toplam fiyatı.
  double costMany(int k, int count) {
    final g = z.growth;
    final first = cost(k);
    if ((g - 1).abs() < 1e-9) return first * count;
    return first * (math.pow(g, count).toDouble() - 1) / (g - 1);
  }

  /// Parasının yettiği en çok adet.
  int affordable(int k) {
    var lo = 0, hi = 1;
    while (hi < 1000 && costMany(k, hi) <= coins) {
      lo = hi;
      hi *= 2;
    }
    hi = math.min<int>(hi, 1000);
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (costMany(k, mid) <= coins) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  bool buyProducer(int k, [int count = 1]) {
    if (count < 1) return false;
    final c = costMany(k, count);
    if (c > coins) return false;
    coins -= c;
    n[k] += count;
    if (n[k] > peakOwn[k]) peakOwn[k] = n[k];
    return true;
  }

  bool buyUpgrade(int i) {
    if (bought[i] || z.upg[i].cost > coins) return false;
    coins -= z.upg[i].cost;
    bought[i] = true;
    upgrades++;
    _recalc();
    return true;
  }

  void earn(double v) {
    coins += v;
    runEarned += v;
    levelEarned += v;
  }

  double get storeCap => math.max(30.0, 40 * income);

  void collect() {
    earn(store);
    store = 0;
  }

  void step(double dt) {
    final inc = income;
    final v = inc * dt;
    if (z.harvest && !auto) {
      store = math.min(store + v, storeCap);
    } else {
      earn(v);
    }
    if (z.cleaning) clean = math.max(0.0, clean - 0.012 * dt * (auto ? 0.4 : 1));
    t += dt;
    final raw = rawOf(n);
    if (raw > peakIncome) peakIncome = raw;
  }

  int get prestigeGain => runEarned >= z.pt ? math.sqrt(runEarned / z.pt).floor() : 0;

  void prestige() {
    final g = prestigeGain;
    if (g <= 0) return;
    points += g;
    prestiges++;
    reset();
  }

  double metric() => switch (z.goalType) {
        GoalType.income => peakIncome,
        GoalType.own => peakOwn[z.goalK].toDouble(),
        _ => levelEarned,
      };

  double progress() {
    final cur = switch (z.goalType) {
      GoalType.income => rawOf(n),
      GoalType.own => n[z.goalK].toDouble(),
      _ => levelEarned,
    };
    return z.goal <= 0 ? 1 : clampD(cur / z.goal, 0, 1);
  }

  bool get reached => metric() >= z.goal;

  // ------------------------------------------------------------ bot

  /// Alınabilecek şeyler: (fiyat, gelire katkı, tür, sıra).
  List<(double, double, int, int)> options() {
    final base = rawOf(n);
    final out = <(double, double, int, int)>[];
    final pr = z.bottle ? prodOf(n) : 0.0;
    final cp = z.bottle ? capOf(n[z.p - 1]) : 0.0;
    for (var k = 0; k < z.p; k++) {
      double dv;
      if (z.bottle) {
        if (k == z.p - 1) {
          dv = math.max(0.0, math.min(pr * 1.3 + 1, capOf(n[k] + 1)) - math.min(pr, cp));
        } else {
          final pd = z.rate0[k] * mult(k, n[k] + 1);
          final room = math.max(0.0, cp - pr);
          dv = math.min(pd, room) + 0.35 * math.max(0.0, pd - room);
        }
      } else {
        n[k]++;
        dv = rawOf(n) - base;
        n[k]--;
      }
      out.add((cost(k), dv, 0, k));
    }
    for (var i = 0; i < z.upg.length; i++) {
      if (bought[i]) continue;
      final u = z.upg[i];
      double dv;
      if (u.target == -3) {
        dv = base * 0.3;
      } else if (u.target == -2) {
        dv = 2 * (1 + 0.05 * base) * _tap * (u.mult - 1);
      } else {
        bought[i] = true;
        _recalc();
        dv = rawOf(n) - base;
        bought[i] = false;
        _recalc();
      }
      out.add((u.cost, dv, 1, i));
    }
    return out;
  }

  /// Bir saniyelik bot hamlesi: dokun, topla, en iyi geri dönüşlü şeyi al.
  void botSecond() {
    earn(2 * tapValue);
    final ti = t.round();
    if (z.harvest && ti % 8 == 0) collect();
    if (z.cleaning && ti % 25 == 0) clean = 1;
    for (var guard = 0; guard < 20; guard++) {
      final opts = options().where((o) => o.$2 > 0).toList();
      if (opts.isEmpty) break;
      var best = opts.first;
      for (final o in opts) {
        if (o.$1 / o.$2 < best.$1 / best.$2) best = o;
      }
      (double, double, int, int)? ab;
      for (final o in opts) {
        if (o.$1 > coins) continue;
        if (ab == null || o.$1 / o.$2 < ab.$1 / ab.$2) ab = o;
      }
      if (ab == null) break;
      if ((ab.$3 == best.$3 && ab.$4 == best.$4) || ab.$1 / ab.$2 <= 1.5 * best.$1 / best.$2) {
        if (ab.$3 == 0) {
          buyProducer(ab.$4);
        } else {
          buyUpgrade(ab.$4);
        }
      } else {
        break;
      }
    }
    final g = prestigeGain;
    if (g >= math.max(2, points)) prestige();
    step(1);
  }
}

/// Botu [seconds] boyunca oynatır; her saniyenin hedef ölçüsünü döndürür.
List<double> botTrace(IdlePuzzle z, int seconds) {
  final e = Econ(z);
  final out = <double>[];
  for (var s = 0; s < seconds; s++) {
    e.botSecond();
    out.add(e.metric());
  }
  return out;
}

/// Botun hedefe ulaştığı saniye (ulaşamazsa -1).
int botReach(IdlePuzzle z, int limit) {
  final e = Econ(z);
  for (var s = 1; s <= limit; s++) {
    e.botSecond();
    if (e.reached) return s;
  }
  return -1;
}

List<List<double>> _seasonTable(int theme, int p) {
  const farm = [
    [1.2, 1.5, 1.0, 0.2],
    [0.8, 1.6, 0.8, 0.1],
    [0.6, 1.0, 1.6, 0.2],
    [1.0, 1.8, 0.6, 0.05],
    [1.0, 1.0, 1.0, 1.4],
    [1.1, 1.1, 1.2, 0.6],
  ];
  const mild = {
    IdleTheme.lantern: [0.9, 0.9, 1.1, 1.25],
    IdleTheme.mine: [1.0, 1.0, 1.0, 1.0],
    IdleTheme.factory: [1.0, 0.95, 1.05, 1.15],
    IdleTheme.aquarium: [1.05, 1.1, 1.0, 0.9],
    IdleTheme.zen: [1.2, 1.0, 1.1, 0.9],
    IdleTheme.bee: [1.3, 1.25, 0.9, 0.55],
    IdleTheme.tea: [1.15, 1.0, 1.05, 1.2],
  };
  return [
    for (var k = 0; k < p; k++)
      if (theme == IdleTheme.farm)
        List<double>.of(farm[k % farm.length])
      else
        [for (var s = 0; s < 4; s++) mild[theme]![(s + k) % 4]],
  ];
}

/// Bir boşta bölümü kurar: ekonomi + botla ayarlanmış hedef.
IdlePuzzle? makeIdle(int theme, int d, SeededRandom r) {
  final bottle = theme == IdleTheme.mine || theme == IdleTheme.factory;
  final p = 4 + d ~/ 4 + (bottle ? 1 : 0);
  final growth = 1.13 + 0.004 * d;
  final cost0 = [for (var k = 0; k < p; k++) 10 * math.pow(11, k).toDouble() * (0.8 + 0.4 * r.nextDouble())];
  final rate0 = [for (var k = 0; k < p; k++) 0.6 * math.pow(7, k).toDouble() * (0.85 + 0.3 * r.nextDouble())];
  if (bottle) {
    rate0[p - 1] = rate0[0] * 6;
    cost0[p - 1] = cost0[1] * 0.6;
  }
  final upg = <Upg>[];
  for (var k = 0; k < p; k++) {
    for (final fm in const [(25.0, 2.0), (400.0, 3.0), (9000.0, 2.0)]) {
      upg.add(Upg(cost0[k] * fm.$1 * (0.8 + 0.4 * r.nextDouble()), k, fm.$2));
    }
  }
  for (final f in const [3000.0, 300000.0, 30000000.0]) {
    upg.add(Upg(f * (0.8 + 0.4 * r.nextDouble()), -1, 1.5));
  }
  upg.add(Upg(cost0[0] * 30, -2, 2));
  upg.add(Upg(cost0[2] * 60, -2, 3));
  if (theme == IdleTheme.farm || theme == IdleTheme.aquarium) upg.add(Upg(cost0[1] * 40, -3, 1));
  upg.sort((a, b) => a.cost.compareTo(b.cost));
  final seconds = 150 + 45 * d;
  final events = <int>[];
  for (var e = 35 + r.nextInt(20); e < seconds * 3; e += 50 + r.nextInt(35)) {
    events.add(e);
  }
  final base = IdlePuzzle(
    theme: theme,
    p: p,
    growth: growth,
    cost0: cost0,
    rate0: rate0,
    upg: upg,
    seas: _seasonTable(theme, p),
    pt: cost0[math.min<int>(3, p - 1)] * 20,
    season0: r.nextInt(4),
    goalType: GoalType.earn,
    goal: 1,
    goalK: 0,
    par: seconds,
    limit: seconds + seconds ~/ 4,
    events: events,
  );
  final type = d <= 3 ? r.weighted(const [6, 2, 2]) : r.weighted(const [4, 3, 3]);
  // Bot oynar; hedef onun [seconds] saniyede vardığı yere göre seçilir.
  final e = Econ(base);
  final trace = <double>[];
  for (var s = 0; s < seconds; s++) {
    e.botSecond();
    trace.add(switch (type) {
      GoalType.income => e.peakIncome,
      GoalType.own => 0.0,
      _ => e.levelEarned,
    });
  }
  var goalK = 0;
  double goal;
  if (type == GoalType.own) {
    goalK = -1;
    for (var k = base.producers - 1; k >= 0; k--) {
      if (e.peakOwn[k] >= 3) {
        goalK = k;
        break;
      }
    }
    if (goalK < 0) return null;
    goal = e.peakOwn[goalK].toDouble();
  } else {
    goal = niceFloor(trace.last);
  }
  if (goal < 1) return null;
  final z = base.withGoal(type, goal, goalK, seconds);
  final reach = botReach(z, z.limit);
  if (reach < 0) return null;
  return z.withGoal(type, goal, goalK, reach);
}

bool checkIdle(IdlePuzzle z) {
  if (z.goal < 1 || z.p < 4 || z.cost0.length != z.p || z.rate0.length != z.p) return false;
  final reach = botReach(z, z.limit);
  return reach > 0 && reach == z.par;
}
