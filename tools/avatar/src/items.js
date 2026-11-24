const target = 'pixiv-sample';
const donor = 'donut-chan';

function item(prefixes, hide = {}) {
  return Object.freeze({donor, prefixes: Object.freeze(prefixes), hide: Object.freeze(hide)});
}

export const ITEMS = Object.freeze({
  'donut-chan:outfit': item([
    'N00_002_03_Tops_01_CLOTH_01',
    'N00_002_03_Tops_01_CLOTH_02',
    'N00_002_03_Tops_01_CLOTH_03',
    'N00_007_01_Tops_01_CLOTH_01',
    'N00_007_01_Tops_01_CLOTH_02',
  ], {[target]: /^(Tops_01|Bottoms_01)_CLOTH/}),
  'donut-chan:shoes': item([
    'N00_008_01_Shoes_01_CLOTH_01',
    'N00_008_01_Shoes_01_CLOTH_02',
  ], {[target]: /^Shoes_01_CLOTH/}),
  'donut-chan:plasters': item(['N00_010_01_Onepiece_00_CLOTH_03']),
});

export const DONORS = Object.freeze([donor]);
const entries = Object.entries(ITEMS);

export function itemForMaterial(name) {
  if (typeof name !== 'string') return null;
  return entries.find(([, {prefixes}]) => prefixes.some((prefix) => name.startsWith(prefix)))?.[0] ?? null;
}

export function resolveOutfit(items, targetId) {
  const show = new Set();
  const hide = [];
  if (targetId === target) {
    for (const id of new Set(items)) {
      if (!Object.prototype.hasOwnProperty.call(ITEMS, id)) continue;
      show.add(id);
      const rule = ITEMS[id].hide[targetId];
      if (rule) hide.push(rule);
    }
  }
  return {show, hide};
}
