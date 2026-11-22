export const MOODS = Object.freeze({
  strongHappy: Object.freeze({happy: 1}),
  mildHappy: Object.freeze({happy: 0.5}),
  neutral: Object.freeze({relaxed: 0.15}),
  mildSad: Object.freeze({sad: 0.5}),
  strongSad: Object.freeze({sad: 1}),
});

export function targets(mood) {
  return Object.prototype.hasOwnProperty.call(MOODS, mood) ? MOODS[mood] : MOODS.neutral;
}

export function step(current, target, dt, rate) {
  const blend = -Math.expm1(-Math.max(0, dt) * Math.max(0, rate));
  return Math.min(1, Math.max(0, current + (target - current) * blend));
}

export function motion(mood) {
  return {
    bounce: mood === 'strongHappy' ? 0.025 : 0,
    headPitch: mood === 'strongSad' ? -0.18 : 0,
  };
}
