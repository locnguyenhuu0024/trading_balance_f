import assert from 'node:assert/strict';
import test from 'node:test';
import {FRAMING_MODES, frame} from '../src/framing.js';

test('frames the pixiv sample at the approved camera bounds', () => {
  const {centerY, halfHeight} = frame({headY: 1.395, hipsY: 0.908});
  assert.ok(Math.abs(centerY - 1.28) < 1e-3);
  assert.ok(Math.abs(halfHeight - 0.47) < 1e-3);
});

test('keeps clearance above Donut-Chan’s head and below the hips', () => {
  const headY = 1.368;
  const hipsY = 0.887;
  const {centerY, halfHeight} = frame({headY, hipsY});
  assert.ok(Math.abs(centerY + halfHeight - 1.71913) < 1e-5);
  assert.ok(Math.abs(centerY - halfHeight - 0.7908) < 1e-5);
});

test('rejects invalid bone coordinates', () => {
  for (const [headY, hipsY] of [[1, 1], [0, 1], [NaN, 1], [1, -Infinity]]) {
    assert.throws(() => frame({headY, hipsY}));
  }
});

test('RED-157-R01 / GREEN-157-R01 frames the pixiv sample full-body', () => {
  const {centerY, halfHeight} = frame({headY: 1.395, hipsY: 0.908, footY: 0.100}, 'full');
  assert.ok(Math.abs(centerY - 0.8449) < 1e-4);
  assert.ok(Math.abs(halfHeight - 0.91535) < 1e-4);
});

test('RED-157-R01 / GREEN-157-R01 keeps full-body clearance for Donut-Chan', () => {
  const headY = 1.368;
  const footY = 0.116;
  const {centerY, halfHeight} = frame({headY, hipsY: 0.887, footY}, 'full');
  assert.ok(centerY + halfHeight >= headY + 0.36);
  assert.ok(centerY - halfHeight <= footY - 0.16);
});

test('RED-157 / GREEN-157 rejects invalid full-body foot positions', () => {
  const bounds = {headY: 1.395, hipsY: 0.908};
  assert.throws(() => frame(bounds, 'full'), RangeError);
  for (const footY of [NaN, bounds.hipsY, 1]) {
    assert.throws(() => frame({...bounds, footY}, 'full'), RangeError);
  }
});

test('RED-157 / GREEN-157 exposes exactly two frozen framing modes and rejects unknown modes', () => {
  assert.deepEqual(FRAMING_MODES, ['half', 'full']);
  assert.ok(Object.isFrozen(FRAMING_MODES));
  assert.throws(() => frame({headY: 1.395, hipsY: 0.908}, 'unknown'), RangeError);
});

test('RED-157 / GREEN-157 preserves half-body framing with or without footY', () => {
  for (const bounds of [{headY: 1.395, hipsY: 0.908}, {headY: 1.368, hipsY: 0.887}]) {
    assert.deepEqual(frame(bounds, 'half'), frame(bounds));
    for (const footY of [0.100, NaN]) {
      assert.deepEqual(frame({...bounds, footY}, 'half'), frame(bounds));
      assert.deepEqual(frame({...bounds, footY}), frame(bounds));
    }
  }
});
