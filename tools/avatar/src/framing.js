export const FRAMING_MODES = Object.freeze(['half', 'full']);

export function frame({headY, hipsY, footY}, mode = 'half') {
  if (!FRAMING_MODES.includes(mode)) {
    throw new RangeError('Unknown framing mode');
  }
  const span = headY - hipsY;
  if (!Number.isFinite(span) || span <= 0) {
    throw new RangeError('Expected finite head and hip coordinates with the head above the hips');
  }
  const full = mode === 'full';
  if (full && (!Number.isFinite(footY) || footY >= hipsY)) {
    throw new RangeError('Expected a finite foot coordinate below the hips');
  }
  const top = headY + (full ? 0.75 : 0.73) * span;
  const bottom = full ? footY - 0.35 * span : hipsY - 0.20 * span;
  return {centerY: top / 2 + bottom / 2, halfHeight: top / 2 - bottom / 2};
}
