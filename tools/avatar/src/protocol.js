import {MOODS} from './mood.js';

const moods = Object.keys(MOODS);
const phases = ['down', 'move', 'up', 'cancel'];

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
    case 'setPaused':
      valid = typeof msg.paused === 'boolean';
      fieldCount = 1;
      break;
    case 'setReducedMotion':
      valid = typeof msg.on === 'boolean';
      fieldCount = 1;
      break;
    case 'pointer':
      valid = phases.includes(msg.phase) && [msg.x, msg.y, msg.t].every(Number.isFinite);
      fieldCount = 4;
      break;
    case 'loadModelChunk':
      valid = Number.isSafeInteger(msg.i) && Number.isSafeInteger(msg.n) &&
        msg.i >= 0 && msg.i < msg.n && typeof msg.b64 === 'string' &&
        msg.b64.length > 0 && !/[^A-Za-z0-9+/=]/.test(msg.b64);
      fieldCount = 3;
      break;
    default:
      return {ok: false, error: 'Unknown avatar message type'};
  }
  return valid && Object.keys(msg).length === fieldCount + 2
    ? {ok: true, msg}
    : {ok: false, error: 'Invalid avatar message fields'};
}
