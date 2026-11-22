import assert from 'node:assert/strict';
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
