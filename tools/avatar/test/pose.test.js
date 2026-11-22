import assert from 'node:assert/strict';
import test from 'node:test';
import {axisSign, restPose} from '../src/pose.js';

test('VRM 0 negates the VRM 1 bone rotations', () => {
  assert.equal(axisSign(false), 1);
  assert.equal(axisSign(true), -1);
  assert.deepEqual(restPose(false), {
    leftUpperArmZ: -1.2, rightUpperArmZ: 1.2, leftLowerArmZ: -0.15, rightLowerArmZ: 0.15,
  });
  assert.deepEqual(restPose(true), {
    leftUpperArmZ: 1.2, rightUpperArmZ: -1.2, leftLowerArmZ: 0.15, rightLowerArmZ: -0.15,
  });
});
