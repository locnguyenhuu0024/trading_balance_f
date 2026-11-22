import assert from 'node:assert/strict';
import test from 'node:test';
import {frame} from '../src/framing.js';

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
