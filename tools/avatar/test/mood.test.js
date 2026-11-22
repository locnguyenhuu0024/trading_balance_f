import assert from 'node:assert/strict';
import test from 'node:test';
import {motion, step, targets} from '../src/mood.js';

test('unknown moods fall back to neutral', () => {
  assert.deepEqual(targets('bogus'), targets('neutral'));
  assert.deepEqual(targets('constructor'), targets('neutral'));
});

test('moods map to the specified expression weights', () => {
  assert.deepEqual(targets('strongHappy'), {happy: 1});
  assert.deepEqual(targets('mildHappy'), {happy: 0.5});
  assert.deepEqual(targets('neutral'), {relaxed: 0.15});
  assert.deepEqual(targets('mildSad'), {sad: 0.5});
  assert.deepEqual(targets('strongSad'), {sad: 1});
  assert.ok(motion('strongHappy').bounce > 0);
  assert.ok(motion('strongSad').headPitch < 0);
  for (const mood of ['mildHappy', 'neutral', 'mildSad']) {
    assert.deepEqual(motion(mood), {bounce: 0, headPitch: 0});
  }
});

test('crossfade is exponential, frame-rate independent and clamped', () => {
  const halfway = step(0, 1, 0.1, 5);
  assert.ok(Math.abs(halfway - (1 - Math.exp(-0.5))) < 1e-12);
  assert.ok(Math.abs(step(halfway, 1, 0.1, 5) - step(0, 1, 0.2, 5)) < 1e-12);
  assert.equal(step(0.5, 1, 0, 5), 0.5);
  assert.equal(step(2, 1, 0.1, 5), 1);
  assert.equal(step(-1, 0, 0.1, 5), 0);
});
