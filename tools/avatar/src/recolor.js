const patterns = {
  hair: /_HAIR/,
  eyes: /EyeIris/,
  top: /Tops_/,
  bottom: /(Bottoms_|Onepiece_)/,
  shoes: /Shoes_/,
  accessory: /^Accessory_/,
};

export const PARTS = Object.keys(patterns);

export function partForMaterial(name) {
  return PARTS.find((part) => patterns[part].test(name)) ?? null;
}

export function parseHex(hex) {
  return [1, 3, 5].map((offset) => Number.parseInt(hex.slice(offset, offset + 2), 16));
}

export function luminance(pixels) {
  const lum = new Uint8Array(pixels.length / 4);
  let total = 0;
  let count = 0;
  for (let i = 0, offset = 0; i < lum.length; i += 1, offset += 4) {
    const value = 0.2126 * pixels[offset] + 0.7152 * pixels[offset + 1] +
      0.0722 * pixels[offset + 2];
    lum[i] = Math.round(value);
    if (pixels[offset + 3] > 8) {
      total += value;
      count += 1;
    }
  }
  return {lum, mean: count ? total / count : 128};
}

export function colorize(pixels, lum, mean, [r, g, b]) {
  for (let i = 0, offset = 0; i < lum.length; i += 1, offset += 4) {
    const k = lum[i] === 0 ? 0 : Math.min(1.6, lum[i] / mean);
    pixels[offset] = Math.min(255, Math.round(r * k));
    pixels[offset + 1] = Math.min(255, Math.round(g * k));
    pixels[offset + 2] = Math.min(255, Math.round(b * k));
  }
}
