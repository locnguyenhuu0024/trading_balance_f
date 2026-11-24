import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {DONORS, ITEMS, itemForMaterial, resolveOutfit} from '../src/items.js';

const outfit = 'donut-chan:outfit';
const shoes = 'donut-chan:shoes';
const plasters = 'donut-chan:plasters';
const ids = [outfit, shoes, plasters];
const clothes = /^(Tops_01|Bottoms_01)_CLOTH/;
const footwear = /^Shoes_01_CLOTH/;

test('catalog exposes three frozen item ids and the single allowed donor', () => {
  assert.ok(Object.isFrozen(ITEMS));
  assert.deepEqual(Object.keys(ITEMS), ids);
  assert.deepEqual(DONORS, ['donut-chan']);
  assert.equal(itemForMaterial('N00_008_01_Shoes_01_CLOTH_01 (Outline)'), shoes);
  assert.equal(itemForMaterial('xN00_008_01_Shoes_01_CLOTH_01'), null);
});

test('resolves each item and combines visibility for Pixiv Sample', () => {
  for (const [items, show, hide] of [
    [[], [], []],
    [[outfit], [outfit], [clothes]],
    [[shoes], [shoes], [footwear]],
    [[plasters], [plasters], []],
    [ids, ids, [clothes, footwear]],
    [[outfit, outfit, shoes, 'unknown'], [outfit, shoes], [clothes, footwear]],
  ]) {
    assert.deepEqual(resolveOutfit(items, 'pixiv-sample'), {show: new Set(show), hide});
  }
  for (const target of ['donut-chan', 'unknown', 'constructor']) {
    assert.deepEqual(resolveOutfit(ids, target), {show: new Set(), hide: []});
  }
});

function materialNames(model) {
  const glb = readFileSync(new URL(`../../../assets/avatar/${model}.vrm`, import.meta.url));
  assert.equal(glb.toString('ascii', 0, 4), 'glTF');
  assert.equal(glb.toString('ascii', 16, 20), 'JSON');
  const json = JSON.parse(glb.toString('utf8', 20, 20 + glb.readUInt32LE(12)));
  return json.materials.map(({name}) => name);
}

test('every item prefix and hide rule matches the intended bundled materials', () => {
  const donor = materialNames('donut-chan');
  const target = materialNames('pixiv-sample');
  const borrowed = donor.filter(itemForMaterial);
  const prefixesByItem = [
    ['N00_002_03_Tops_01_CLOTH_01', 'N00_002_03_Tops_01_CLOTH_02',
      'N00_002_03_Tops_01_CLOTH_03', 'N00_007_01_Tops_01_CLOTH_01', 'N00_007_01_Tops_01_CLOTH_02'],
    ['N00_008_01_Shoes_01_CLOTH_01', 'N00_008_01_Shoes_01_CLOTH_02'],
    ['N00_010_01_Onepiece_00_CLOTH_03'],
  ];
  for (const [index, id] of ids.entries()) {
    assert.equal(ITEMS[id].donor, 'donut-chan');
    assert.deepEqual(ITEMS[id].prefixes, prefixesByItem[index]);
    for (const prefix of ITEMS[id].prefixes) {
      const matches = donor.filter((name) => name.startsWith(prefix));
      assert.ok(matches.length, prefix);
      for (const name of matches) assert.equal(itemForMaterial(name), id);
    }
  }
  for (const rule of resolveOutfit(ids, 'pixiv-sample').hide) {
    assert.ok(target.some((name) => rule.test(name)), String(rule));
    assert.ok(!borrowed.some((name) => rule.test(name)), String(rule));
  }
});
