import 'core.dart';
import 'economy.dart';
import 'kinds/caravan.dart';
import 'kinds/colony.dart';
import 'kinds/diner.dart';
import 'kinds/grocer.dart';
import 'kinds/idle.dart';
import 'kinds/kitchen.dart';
import 'kinds/merge.dart';
import 'kinds/pet.dart';
import 'kinds/renovate.dart';
import 'kinds/shine.dart';
import 'kinds/style.dart';
import 'kinds/town.dart';
import 'kinds/tulip.dart';
import 'kinds/village.dart';

/// Boşta ve simülasyon oyun türleri.
const Map<String, SimKind> kSimKinds = {
  'fener': IdleKind('fener', IdleTheme.lantern),
  'birlestir': MergeKind(),
  'evcil': PetKind(),
  'maden': IdleKind('maden', IdleTheme.mine),
  'fabrika': IdleKind('fabrika', IdleTheme.factory),
  'lokanta': DinerKind(),
  'ciftlik': IdleKind('ciftlik', IdleTheme.farm),
  'akvaryum': IdleKind('akvaryum', IdleTheme.aquarium),
  'zen': IdleKind('zen', IdleTheme.zen),
  'karinca': ColonyKind(),
  'kasaba': TownKind(),
  'stil': StyleKind(),
  'mutfak': KitchenKind(),
  'kovan': IdleKind('kovan', IdleTheme.bee),
  'cay': IdleKind('cay', IdleTheme.tea),
  'lale': TulipKind(),
  'kervan': CaravanKind(),
  'uzay': IdleKind('uzay', IdleTheme.space),
  'hayvanat': IdleKind('hayvanat', IdleTheme.zoo),
  'bakkal': GrocerKind(),
  'hayat': VillageKind(),
  'parlat': ShineKind(),
  'yenile': RenovateKind(),
};

SimRules simRulesFor(String gameId, String kind) => simRules(gameId, kSimKinds[kind]!);
