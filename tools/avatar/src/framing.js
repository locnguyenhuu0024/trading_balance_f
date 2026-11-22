export function frame({headY, hipsY}) {
  const span = headY - hipsY;
  if (!Number.isFinite(span) || span <= 0) {
    throw new RangeError('Expected finite head and hip coordinates with the head above the hips');
  }
  const top = headY + 0.73 * span;
  const bottom = hipsY - 0.20 * span;
  return {centerY: top / 2 + bottom / 2, halfHeight: top / 2 - bottom / 2};
}
