import assert from 'node:assert/strict';
import test from 'node:test';
import {colorize, luminance, parseHex, partForMaterial, PARTS} from '../src/recolor.js';

test('classifies only recolorable material names', () => {
  assert.deepEqual(PARTS, ['hair', 'eyes', 'top', 'bottom', 'shoes', 'accessory']);
  for (const [name, part] of [
    ['HairBack_00_HAIR', 'hair'],
    ['N00_000_Hair_00_HAIR (Instance) (Outline)', 'hair'],
    ['N00_000_00_EyeIris_00_EYE (Outline)', 'eyes'],
    ['N00_007_01_Tops_01_CLOTH_01 (Instance)', 'top'],
    ['Bottoms_01_CLOTH', 'bottom'],
    ['N00_010_01_Onepiece_00_CLOTH_01', 'bottom'],
    ['N00_008_01_Shoes_01_CLOTH_01', 'shoes'],
    ['Accessory_FoxTail_01_CLOTH (Instance)', 'accessory'],
    ['N00_Accessory_FoxTail', null],
    ['EyeWhite_00_EYE', null],
    ['EyeHighlight_00_EYE (Outline)', null],
    ['N00_000_00_Face_00_SKIN', null],
    ['Body_00_SKIN', null],
    ['FaceMouth_00_FACE', null],
  ]) {
    assert.equal(partForMaterial(name), part, name);
  }
});

test('parses hex colors in either case', () => {
  assert.deepEqual(parseHex('#00aaff'), [0, 170, 255]);
  assert.deepEqual(parseHex('#00AAFF'), [0, 170, 255]);
});

test('colorizes relative to the visible mean and leaves alpha untouched', () => {
  const pixels = Uint8ClampedArray.of(100, 100, 100, 9, 255, 255, 255, 8, 0, 0, 0, 0);
  const {lum, mean} = luminance(pixels);
  assert.deepEqual(lum, Uint8Array.of(100, 255, 0));
  assert.equal(mean, 100);
  colorize(pixels, lum, mean, [200, 100, 31]);
  assert.deepEqual(pixels, Uint8ClampedArray.of(200, 100, 31, 9, 255, 160, 50, 8, 0, 0, 0, 0));
});

test('computes weighted luminance and averages the visible pixels', () => {
  const {lum, mean} = luminance(Uint8ClampedArray.of(200, 0, 0, 255, 0, 200, 0, 255));
  assert.ok(Math.abs(lum[0] - 42.52) < 1);
  assert.ok(Math.abs(lum[1] - 143.04) < 1);
  assert.ok(Math.abs(mean - 92.78) < 1);
});

test('uses 128 for all-transparent pixels and keeps an all-black texture black', () => {
  const transparent = Uint8ClampedArray.of(128, 128, 128, 0);
  const {lum, mean} = luminance(transparent);
  assert.equal(mean, 128);
  colorize(transparent, lum, mean, [1, 2, 3]);
  assert.deepEqual(transparent, Uint8ClampedArray.of(1, 2, 3, 0));

  const black = [0, 0, 0, 255];
  const blackLuminance = luminance(black);
  assert.equal(blackLuminance.mean, 0);
  colorize(black, blackLuminance.lum, blackLuminance.mean, [1, 2, 3]);
  assert.deepEqual(black, [0, 0, 0, 255]);
});
