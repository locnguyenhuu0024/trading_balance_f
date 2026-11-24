const patterns = {
  hair: /_HAIR/,
  eyes: /EyeIris/,
  top: /Tops_/,
  bottom: /(Bottoms_|Onepiece_)/,
  shoes: /Shoes_/,
  accessory: /^Accessory_/,
};

const materialPrefixes = [
  ['N00_002_03_Tops_01_CLOTH_02', 'dress'],
  ['N00_002_03_Tops_01_CLOTH_03', 'dress'],
  ['N00_002_03_Tops_01_CLOTH_01', 'bows'],
  ['N00_007_01_Tops_01_CLOTH_01', 'bows'],
  ['N00_007_01_Tops_01_CLOTH_02', 'bows'],
  ['N00_010_01_Onepiece_00_CLOTH_01', 'socks'],
  ['N00_010_01_Onepiece_00_CLOTH_02', 'socks'],
  ['N00_010_01_Onepiece_00_CLOTH_03', 'plasters'],
];

const genericParts = Object.keys(patterns);
export const PARTS = [...genericParts, 'dress', 'bows', 'socks', 'plasters'];

export function partForMaterial(name) {
  if (typeof name === 'string') {
    for (const [prefix, part] of materialPrefixes) {
      if (name.startsWith(prefix)) return part;
    }
  }
  return genericParts.find((part) => patterns[part].test(name)) ?? null;
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
