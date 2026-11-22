const TAP_MS = 250;
const TAP_TRAVEL = 10;
const STROKE_MS = 1500;
const STROKE_LEG = 12;
const PETTING_IDLE_MS = 600;
const DEBOUNCE_MS = 150;

export function createClassifier({now = () => performance.now()} = {}) {
  let start;
  let travel;
  let direction;
  let extremeX;
  let reversals;
  let lastStroke;
  let petting = false;
  let lastEmission = -Infinity;

  function emit(kind, time) {
    if (time - lastEmission < DEBOUNCE_MS) return;
    lastEmission = time;
    return kind;
  }

  function tick() {
    const time = now();
    if (petting && time - lastStroke >= PETTING_IDLE_MS) {
      const event = emit('pettingEnd', time);
      if (event) petting = false;
      return event;
    }
  }

  function stroke(x, t, time) {
    const delta = x - extremeX;
    if (direction && delta * direction >= 0) {
      extremeX = x;
    } else if (Math.abs(delta) >= STROKE_LEG) {
      if (direction) reversals += 1;
      direction = Math.sign(delta);
      extremeX = x;
      if (petting || t - start.t <= STROKE_MS) {
        lastStroke = time;
        if (!petting && reversals >= 2) {
          const event = emit('pettingStart', time);
          if (event) petting = true;
          return event;
        }
      }
    }
  }

  function sample({phase, x, y, t = now(), region}) {
    const time = now();
    const expired = tick();
    if (phase === 'down') {
      start = {x, y, t, region};
      travel = 0;
      direction = 0;
      extremeX = x;
      reversals = 0;
      return expired;
    }
    if (phase === 'cancel' || !start) {
      start = undefined;
      return expired;
    }

    const dx = x - start.x;
    const dy = y - start.y;
    travel = Math.max(travel, Math.hypot(dx, dy));
    if (phase === 'move') {
      return start.region === 'head' ? stroke(x, t, time) ?? expired : expired;
    }
    if (phase !== 'up') return expired;

    const origin = start;
    const strokeEvent = origin.region === 'head' ? stroke(x, t, time) : undefined;
    start = undefined;
    if (expired || strokeEvent) return expired ?? strokeEvent;
    if (t - origin.t < TAP_MS && travel < TAP_TRAVEL) {
      if (origin.region === 'head') return emit('pat', time);
      if (origin.region === 'body') return emit('poke', time);
    }
    if (origin.region !== 'head' && Math.abs(dx) > 24 && Math.abs(dx) > 1.5 * Math.abs(dy)) {
      return emit('swipe', time);
    }
  }

  return {sample, tick};
}
