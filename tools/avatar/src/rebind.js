import {Matrix4, Quaternion} from 'three';

export function primaryMaterial(material) {
  return [].concat(material)[0];
}

export function flipFor(donorMetaVersion, targetMetaVersion) {
  const flip = new Matrix4();
  if (donorMetaVersion !== targetMetaVersion) flip.makeRotationY(Math.PI);
  return flip;
}

export function boneKey(name) {
  return name.startsWith('J_Bip') ? name : `donor:${name}`;
}

export function flipLocal(position, quaternion, flip) {
  const {x, y, z, w} = quaternion;
  const sign = flip.elements[0];
  return {
    position: position.clone().applyMatrix4(flip),
    quaternion: new Quaternion(sign * x, y, sign * z, w),
  };
}

export function rebindInverse(flip, inverse) {
  return new Matrix4().multiplyMatrices(flip, inverse);
}

export function planChain(bone, hasKey) {
  const chain = [];
  for (let current = bone; current && !hasKey(boneKey(current.name)); current = current.parent) {
    chain.push(current);
  }
  return chain.reverse();
}

export function bindMatrix() {
  return new Matrix4();
}
