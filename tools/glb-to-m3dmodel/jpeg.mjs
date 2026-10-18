// Baseline JPEG block averages. A triangle needs a flat colour, so the DC
// coefficient of each 8x8 block is enough; AC coefficients are consumed but
// do not need an inverse DCT. No image library or external process is used.

export function decodeJpegAverages(bytes) {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) throw new Error('JPEG: missing SOI');
  let at = 2;
  const quant = new Map(), huffman = new Map();
  let frame, restartInterval = 0;
  while (at < bytes.length) {
    if (bytes[at++] !== 0xff) throw new Error('JPEG: expected marker');
    while (bytes[at] === 0xff) at++;
    const marker = bytes[at++];
    if (marker === 0xd9) break;
    if (marker === 0xd8) continue;
    const length = bytes.readUInt16BE(at);
    if (length < 2 || at + length > bytes.length) throw new Error('JPEG: bad segment length');
    const end = at + length;
    at += 2;
    if (marker === 0xdb) {
      while (at < end) {
        const info = bytes[at++], precision = info >> 4, id = info & 15;
        if (precision !== 0) throw new Error('JPEG: only 8-bit quantization is supported');
        quant.set(id, [...bytes.subarray(at, at + 64)]);
        at += 64;
      }
    } else if (marker === 0xc4) {
      while (at < end) {
        const info = bytes[at++];
        const counts = [...bytes.subarray(at, at + 16)];
        at += 16;
        const total = counts.reduce((a, b) => a + b, 0);
        const symbols = bytes.subarray(at, at + total);
        at += total;
        const table = new Map();
        let code = 0, index = 0;
        for (let bits = 1; bits <= 16; bits++) {
          for (let n = 0; n < counts[bits - 1]; n++) table.set(`${bits}:${code++}`, symbols[index++]);
          code <<= 1;
        }
        huffman.set(info, table);
      }
    } else if (marker === 0xc0) {
      if (bytes[at++] !== 8) throw new Error('JPEG: only 8-bit samples are supported');
      const height = bytes.readUInt16BE(at), width = bytes.readUInt16BE(at + 2);
      at += 4;
      const count = bytes[at++], components = new Map();
      for (let i = 0; i < count; i++) {
        const id = bytes[at++], factors = bytes[at++], q = bytes[at++];
        components.set(id, { id, h: factors >> 4, v: factors & 15, q, previous: 0 });
      }
      frame = { width, height, components };
    } else if (marker === 0xdd) {
      restartInterval = bytes.readUInt16BE(at);
    } else if (marker === 0xda) {
      if (!frame) throw new Error('JPEG: scan before frame');
      const count = bytes[at++], scan = [];
      for (let i = 0; i < count; i++) {
        const component = frame.components.get(bytes[at++]);
        const tables = bytes[at++];
        if (!component) throw new Error('JPEG: unknown scan component');
        component.dc = huffman.get(tables >> 4);
        component.ac = huffman.get(0x10 | (tables & 15));
        component.quant = quant.get(component.q);
        if (!component.dc || !component.ac || !component.quant) throw new Error('JPEG: missing table');
        scan.push(component);
      }
      if (count !== frame.components.size || bytes[at++] !== 0 || bytes[at++] !== 63 || bytes[at++] !== 0) {
        throw new Error('JPEG: only interleaved baseline scans are supported');
      }
      return decodeScan(bytes, end, frame, scan, restartInterval);
    } else if ((marker >= 0xc0 && marker <= 0xcf) && marker !== 0xc4) {
      throw new Error('JPEG: progressive and other non-baseline frames are unsupported');
    }
    at = end;
  }
  throw new Error('JPEG: no image scan');
}

function decodeScan(bytes, start, frame, scan, restartInterval) {
  const { width, height } = frame;
  const maxH = Math.max(...scan.map(c => c.h)), maxV = Math.max(...scan.map(c => c.v));
  const mcuWidth = maxH * 8, mcuHeight = maxV * 8;
  const cols = Math.ceil(width / mcuWidth), rows = Math.ceil(height / mcuHeight);
  for (const component of scan) {
    component.blockCols = cols * component.h;
    component.blocks = new Uint8Array(component.blockCols * rows * component.v);
  }
  let at = start, bits = 0, bitCount = 0, restart = 0;
  function readBit() {
    if (!bitCount) {
      if (at >= bytes.length) throw new Error('JPEG: truncated scan');
      bits = bytes[at++];
      if (bits === 0xff) {
        const next = bytes[at++];
        if (next !== 0) throw new Error(`JPEG: unexpected marker ${next?.toString(16)}`);
      }
      bitCount = 8;
    }
    bitCount--;
    return (bits >> bitCount) & 1;
  }
  function readBits(count) {
    let value = 0;
    for (let i = 0; i < count; i++) value = (value << 1) | readBit();
    return value;
  }
  function symbol(table) {
    let code = 0;
    for (let length = 1; length <= 16; length++) {
      code = (code << 1) | readBit();
      const value = table.get(`${length}:${code}`);
      if (value !== undefined) return value;
    }
    throw new Error('JPEG: invalid Huffman code');
  }
  function signed(size) {
    if (!size) return 0;
    const value = readBits(size);
    return value < (1 << (size - 1)) ? value - (1 << size) + 1 : value;
  }
  for (let my = 0; my < rows; my++) {
    for (let mx = 0; mx < cols; mx++) {
      const index = my * cols + mx;
      if (restartInterval && index && index % restartInterval === 0) {
        bitCount = 0;
        if (bytes[at++] !== 0xff || bytes[at++] !== 0xd0 + (restart++ & 7)) throw new Error('JPEG: bad restart marker');
        for (const component of scan) component.previous = 0;
      }
      for (const component of scan) {
        for (let by = 0; by < component.v; by++) {
          for (let bx = 0; bx < component.h; bx++) {
            component.previous += signed(symbol(component.dc));
            const mean = 128 + component.previous * component.quant[0] / 8;
            const blockAt = (my * component.v + by) * component.blockCols + mx * component.h + bx;
            component.blocks[blockAt] = Math.max(0, Math.min(255, Math.round(mean)));
            let coefficient = 1;
            while (coefficient < 64) {
              const rs = symbol(component.ac);
              if (rs === 0) break;
              if (rs === 0xf0) { coefficient += 16; continue; }
              coefficient += (rs >> 4) + 1;
              readBits(rs & 15);
            }
            if (coefficient > 64) throw new Error('JPEG: invalid AC run');
          }
        }
      }
    }
  }
  const components = [...frame.components.values()];
  function sample(x, y) {
    x = Math.max(0, Math.min(width - 1, Math.floor(x)));
    y = Math.max(0, Math.min(height - 1, Math.floor(y)));
    const values = components.map(c => {
      const bx = Math.floor(x * c.h / maxH / 8), by = Math.floor(y * c.v / maxV / 8);
      return c.blocks[by * c.blockCols + bx];
    });
    if (values.length === 1) return [values[0], values[0], values[0], 255];
    if (values.length !== 3) throw new Error('JPEG: only grayscale and YCbCr are supported');
    const [luma, cb, cr] = values;
    const clamp = n => Math.max(0, Math.min(255, Math.round(n)));
    return [clamp(luma + 1.402 * (cr - 128)),
      clamp(luma - 0.344136 * (cb - 128) - 0.714136 * (cr - 128)),
      clamp(luma + 1.772 * (cb - 128)), 255];
  }
  return { width, height, sample };
}
