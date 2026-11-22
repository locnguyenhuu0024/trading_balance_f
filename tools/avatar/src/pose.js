export function axisSign(isVrm0) {
  return isVrm0 ? -1 : 1;
}

export function restPose(isVrm0) {
  const sign = axisSign(isVrm0);
  return {
    leftUpperArmZ: -1.2 * sign,
    rightUpperArmZ: 1.2 * sign,
    leftLowerArmZ: -0.15 * sign,
    rightLowerArmZ: 0.15 * sign,
  };
}
