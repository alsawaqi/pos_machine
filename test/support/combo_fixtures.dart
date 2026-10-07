// LAUNCH combo add-on — shared till fixtures for the combo fix-order tests
// (the same menu as launch_combo_till_test.dart).
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import 'package:pos_machine/models/pos_models.dart';

const size = AddonGroup(
  id: 5,
  name: 'Size',
  nameAr: 'الحجم',
  multiSelect: false,
  minSelections: 1,
  maxSelections: 1,
  options: [
    AddonOption(id: 51, label: 'Regular', priceDelta: 0, isDefault: true),
    AddonOption(id: 52, label: 'Large', priceDelta: 0.200),
  ],
);
const remove = AddonGroup(
  id: 6,
  name: 'Remove',
  multiSelect: true,
  options: [
    AddonOption(id: 61, label: 'No cheese', priceDelta: -0.100),
    AddonOption(id: 62, label: 'No onion', priceDelta: 0),
  ],
);
const ice = AddonGroup(
  id: 7,
  name: 'Ice',
  multiSelect: false,
  minSelections: 1,
  maxSelections: 1,
  options: [
    AddonOption(id: 71, label: 'Less ice', priceDelta: 0),
    AddonOption(id: 72, label: 'No ice', priceDelta: -0.500),
  ],
);
const regular = CartItemModifier(
  id: '51',
  group: 'Size',
  label: 'Regular',
  price: 0,
);
const noCheese = CartItemModifier(
  id: '61',
  group: 'Remove',
  label: 'No cheese',
  price: -0.100,
);
const noIce = CartItemModifier(
  id: '72',
  group: 'Ice',
  label: 'No ice',
  price: -0.500,
);

const burger = Product(
  id: '30',
  name: 'Beef burger',
  nameAr: 'برجر لحم',
  category: 'Menu',
  categoryId: 1,
  price: 2.000,
  deliveryPrice: 2.500,
  addonGroupIds: [6],
);
const chicken = Product(
  id: '33',
  name: 'Chicken burger',
  category: 'Menu',
  categoryId: 1,
  price: 1.800,
);
const fries = Product(
  id: '31',
  name: 'Fries',
  nameAr: 'بطاطس',
  category: 'Menu',
  categoryId: 2,
  price: 1.000,
);
const loaded = Product(
  id: '35',
  name: 'Loaded fries',
  nameAr: 'بطاطس محملة',
  category: 'Menu',
  categoryId: 2,
  price: 1.500,
);
const cola = Product(
  id: '32',
  name: 'Cola',
  category: 'Menu',
  categoryId: 3,
  price: 1.000,
  addonGroupIds: [5],
);
const juice = Product(
  id: '34',
  name: 'Fresh juice',
  category: 'Menu',
  categoryId: 3,
  price: 1.200,
);
const water = Product(
  id: '36',
  name: 'Water',
  category: 'Menu',
  categoryId: 3,
  price: 0.300,
  addonGroupIds: [7],
);
const familyBox = Product(
  id: '40',
  name: 'Family box',
  nameAr: 'صندوق العائلة',
  category: 'Menu',
  categoryId: 9,
  price: 5.000,
  deliveryPrice: 5.500,
  deliveryUnlistedProviderIds: {8},
  productType: 'combo',
  comboLines: [
    pricing.ComboLineDef.fixed(id: 1, productId: 30, quantity: 2),
    pricing.ComboLineDef.fixed(
      id: 2,
      productId: 31,
      sortOrder: 1,
      upgrades: [
        pricing.ComboUpgradeDef(productId: 35, upgradePriceBaisas: 800),
      ],
    ),
    pricing.ComboLineDef.choice(
      id: 3,
      name: 'Drink',
      nameAr: 'مشروب',
      sortOrder: 2,
      items: [
        pricing.ComboChoiceItemDef(productId: 32),
        pricing.ComboChoiceItemDef(productId: 34, extraPriceBaisas: 300),
      ],
    ),
  ],
);
const fixedBox = Product(
  id: '41',
  name: 'Fixed box',
  category: 'Menu',
  price: 3.000,
  productType: 'combo',
  comboLines: [
    pricing.ComboLineDef.fixed(id: 11, productId: 30),
    pricing.ComboLineDef.fixed(id: 12, productId: 31, sortOrder: 1),
  ],
);
const drinksBox = Product(
  id: '42',
  name: 'Drinks box',
  category: 'Menu',
  price: 2.000,
  productType: 'combo',
  comboLines: [
    pricing.ComboLineDef.choice(
      id: 21,
      name: 'Drinks',
      nameAr: 'مشروبات',
      pickCount: 4,
      items: [
        pricing.ComboChoiceItemDef(productId: 32),
        pricing.ComboChoiceItemDef(productId: 34, extraPriceBaisas: 300),
        pricing.ComboChoiceItemDef(productId: 36),
      ],
    ),
  ],
);
const meal = MealSetup(
  id: 5,
  name: 'meal',
  nameAr: 'وجبة',
  mealPriceBaisas: 1200,
  mains: {30, 33},
  lines: [
    pricing.ComboLineDef.fixed(
      id: 51,
      productId: 31,
      upgrades: [
        pricing.ComboUpgradeDef(productId: 35, upgradePriceBaisas: 800),
      ],
    ),
    pricing.ComboLineDef.choice(
      id: 52,
      name: 'Drink',
      sortOrder: 1,
      items: [
        pricing.ComboChoiceItemDef(productId: 32),
        pricing.ComboChoiceItemDef(productId: 34, extraPriceBaisas: 300),
      ],
    ),
  ],
);
const products = [
  familyBox,
  fixedBox,
  drinksBox,
  burger,
  chicken,
  fries,
  loaded,
  cola,
  juice,
  water,
];
