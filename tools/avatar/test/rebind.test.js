import assert from 'node:assert/strict';
import {register} from 'node:module';
import {resolve} from 'node:path';
import test from 'node:test';
import {pathToFileURL} from 'node:url';

// Resolve Three from the offline build staging area when DEPS is supplied.
if (process.env.DEPS) {
  const hook = `export function resolve(specifier, context, next) {
    return next(specifier, specifier === 'three' ? {...context, parentURL: ${
      JSON.stringify(pathToFileURL(resolve(process.env.DEPS, 'avatar-tests.js')).href)
    }} : context);
  }`;
  register(`data:text/javascript,${encodeURIComponent(hook)}`, import.meta.url);
}

const {bindMatrix, boneKey, flipFor, flipLocal, planChain, rebindInverse} =
  await import('../src/rebind.js');
const {Matrix4, Quaternion, Vector3} = await import('three');

test('flips about Y only for different VRM meta versions', () => {
  assert.ok(flipFor('0', '0').equals(new Matrix4()));
  assert.ok(flipFor('1', '1').equals(new Matrix4()));
  const flipped = new Vector3(1, 2, 3).applyMatrix4(flipFor('0', '1'));
  assert.ok(flipped.distanceTo(new Vector3(-1, 2, -3)) < 1e-6);
});

test('local quaternion conjugation matches the flipped rotation and round-trips', () => {
  const position = new Vector3(1, 2, 3);
  const quaternion = new Quaternion().setFromAxisAngle(new Vector3(1, 2, 3).normalize(), 0.71);
  const flip = flipFor('0', '1');
  const local = flipLocal(position, quaternion, flip);
  assert.ok(local.position.distanceTo(new Vector3(-1, 2, -3)) < 1e-6);
  const direction = new Vector3(3, 1, 2);
  const expected = direction.clone().applyMatrix4(flip.clone().invert())
    .applyQuaternion(quaternion).applyMatrix4(flip);
  assert.ok(direction.applyQuaternion(local.quaternion).distanceTo(expected) < 1e-6);
  const roundTrip = flipLocal(local.position, local.quaternion, flip);
  assert.ok(roundTrip.position.distanceTo(position) < 1e-6);
  assert.ok(roundTrip.quaternion.angleTo(quaternion) < 1e-6);
  assert.deepEqual(flipLocal(position, quaternion, flipFor('1', '1')), {position, quaternion});
});

test('the rebound inverse maps donor bind-space vertices into flipped target space', () => {
  const flip = flipFor('0', '1');
  const donorWorld = new Matrix4().makeRotationX(0.43).setPosition(2, 4, 8);
  const targetWorld = flip.clone().multiply(donorWorld).multiply(flip.clone().invert());
  const inverse = rebindInverse(flip, donorWorld.clone().invert());
  const vertex = new Vector3(4, 3, 5);
  const actual = vertex.clone().applyMatrix4(inverse).applyMatrix4(targetWorld);
  assert.ok(actual.distanceTo(vertex.clone().applyMatrix4(flip)) < 1e-6);
  assert.ok(bindMatrix().equals(new Matrix4()));
});

test('plans the missing donor chain from the nearest mapped ancestor', () => {
  const hips = {name: 'J_Bip_C_Hips'};
  const skirt = {name: 'J_Sec_Skirt', parent: hips};
  const hem = {name: 'J_Sec_Hem', parent: skirt};
  assert.equal(boneKey(hips.name), hips.name);
  assert.equal(boneKey(skirt.name), 'donor:J_Sec_Skirt');
  assert.deepEqual(planChain(hem, (key) => key === hips.name), [skirt, hem]);
  assert.deepEqual(planChain(hem, (key) => key === boneKey(skirt.name)), [hem]);
  assert.deepEqual(planChain(hips, (key) => key === hips.name), []);
  assert.deepEqual(planChain(hem, () => false), [hips, skirt, hem]);
});
