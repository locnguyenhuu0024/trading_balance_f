import {DONORS, ITEMS} from './items.js';
import {MOODS} from './mood.js';
import {PARTS} from './recolor.js';

const moods = Object.keys(MOODS);
const phases = ['down', 'move', 'up', 'cancel'];
const hexColor = /^#[0-9a-f]{6}$/i;

function validChunk({i, n, b64}) {
  return Number.isSafeInteger(i) && Number.isSafeInteger(n) && i >= 0 && i < n &&
    typeof b64 === 'string' && b64.length > 0 && !/[^A-Za-z0-9+/=]/.test(b64);
}

export function parse(raw) {
  let msg;
  try {
    msg = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch {
    return {ok: false, error: 'Invalid JSON'};
  }
  if (!msg || typeof msg !== 'object' || Array.isArray(msg) || msg.v !== 1) {
    return {ok: false, error: 'Invalid avatar message envelope'};
  }

  let valid;
  let fieldCount;
  switch (msg.type) {
    case 'setMood':
      valid = moods.includes(msg.mood);
      fieldCount = 1;
      break;
    case 'setColors': {
      const {colors} = msg;
      valid = Object.prototype.propertyIsEnumerable.call(msg, 'colors') &&
        colors !== null && typeof colors === 'object' && !Array.isArray(colors) &&
        Reflect.ownKeys(colors).every((part) =>
          PARTS.includes(part) && typeof colors[part] === 'string' && hexColor.test(colors[part]));
      fieldCount = 1;
      break;
    }
    case 'setPaused':
      valid = typeof msg.paused === 'boolean';
      fieldCount = 1;
      break;
    case 'setOutfit': {
      const {items} = msg;
      valid = Array.isArray(items) && items.length <= 3 &&
        [...items].every((id) => typeof id === 'string' && Object.hasOwn(ITEMS, id)) &&
        new Set(items).size === items.length;
      fieldCount = 1;
      break;
    }
    case 'setReducedMotion':
      valid = typeof msg.on === 'boolean';
      fieldCount = 1;
      break;
    case 'pointer':
      valid = phases.includes(msg.phase) && [msg.x, msg.y, msg.t].every(Number.isFinite);
      fieldCount = 4;
      break;
    case 'loadModelChunk':
      valid = validChunk(msg);
      fieldCount = 3;
      break;
    case 'loadDonorChunk':
      valid = DONORS.includes(msg.model) && validChunk(msg);
      fieldCount = 4;
      break;
    default:
      return {ok: false, error: 'Unknown avatar message type'};
  }
  return valid && Object.keys(msg).length === fieldCount + 2
    ? {ok: true, msg}
    : {ok: false, error: 'Invalid avatar message fields'};
}
