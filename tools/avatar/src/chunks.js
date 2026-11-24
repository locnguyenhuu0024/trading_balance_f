export function createAssembler() {
  const chunks = new Map();
  let count;
  let byteLength = 0;
  let complete = false;

  return {
    add(i, n, b64) {
      count ??= n;
      if (n !== count) throw new Error('Inconsistent chunk count');
      if (complete || chunks.has(i)) return;

      const decoded = atob(b64);
      const chunk = new Uint8Array(decoded.length);
      for (let byte = 0; byte < chunk.length; byte += 1) chunk[byte] = decoded.charCodeAt(byte);
      chunks.set(i, chunk);
      byteLength += chunk.length;
      if (chunks.size !== count) return;

      const bytes = new Uint8Array(byteLength);
      let offset = 0;
      for (let index = 0; index < count; index += 1) {
        const chunk = chunks.get(index);
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      chunks.clear();
      complete = true;
      return bytes;
    },
  };
}
