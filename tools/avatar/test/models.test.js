import assert from 'node:assert/strict';
import {readdirSync, readFileSync} from 'node:fs';
import test from 'node:test';
import {DEFAULT_MODEL, MODELS, resolveModel} from '../src/models.js';

test('resolves only bundled model IDs', () => {
  assert.equal(DEFAULT_MODEL, 'pixiv-sample');
  assert.deepEqual(MODELS, {
    'pixiv-sample': 'pixiv-sample.vrm',
    'donut-chan': 'donut-chan.vrm',
  });
  assert.equal(resolveModel('?model=pixiv-sample'), 'pixiv-sample.vrm');
  assert.equal(resolveModel('?model=donut-chan'), 'donut-chan.vrm');
});

test('defaults for missing, malformed and unknown model IDs', () => {
  for (const id of ['../x', 'avatar.vrm', 'DONUT-CHAN', '', 'unknown', 'constructor', 'a'.repeat(33)]) {
    assert.equal(resolveModel(`?model=${encodeURIComponent(id)}`), 'pixiv-sample.vrm');
  }
  assert.equal(resolveModel(''), 'pixiv-sample.vrm');
});

test('bundled GLB materials cover the supported recolor parts', async () => {
  const {partForMaterial} = await import('../src/recolor.js');
  const directory = new URL('../../../assets/avatar/', import.meta.url);
  const expected = {
    'pixiv-sample.vrm': ['hair', 'eyes', 'top', 'bottom', 'shoes'],
    'donut-chan.vrm': ['hair', 'eyes', 'dress', 'bows', 'socks', 'shoes', 'plasters', 'accessory'],
  };
  const files = readdirSync(directory).filter((name) => name.endsWith('.vrm'));
  assert.deepEqual(files.sort(), Object.keys(expected).sort());
  for (const file of files) {
    const glb = readFileSync(new URL(file, directory));
    assert.equal(glb.toString('ascii', 0, 4), 'glTF', file);
    assert.equal(glb.toString('ascii', 16, 20), 'JSON', file);
    const json = JSON.parse(glb.toString('utf8', 20, 20 + glb.readUInt32LE(12)));
    const parts = new Set(json.materials.map(({name}) => partForMaterial(name)).filter(Boolean));
    assert.deepEqual(parts, new Set(expected[file]), file);
  }
});
