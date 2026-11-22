import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from '../src/protocol.js';

test('rejects an unsupported version, unknown type, and non-JSON payload', () => {
  for (const raw of ['{"v":2,"type":"setMood"}', '{"v":1,"type":"unknown"}', 'invalid JSON']) {
    assert.equal(parse(raw).ok, false);
  }
});

test('rejects invalid fields, outbound types, and undeclared data', () => {
  for (const msg of [
    {type: 'setPaused', paused: 0},
    {type: 'setReducedMotion', on: null},
    {type: 'setMood', mood: 'bogus'},
    {type: 'setMood', mood: 'neutral', amount: 42},
    {type: 'pointer', phase: 'other', x: 0, y: 0, t: 0},
    {type: 'pointer', phase: 'move', x: Infinity, y: 0, t: 0},
    {type: 'loadModelChunk', i: 1, n: 1, b64: 'YQ=='},
    {type: 'loadModelChunk', i: 0, n: 1, b64: 'YQ%='},
    {type: 'ready', version: 1},
  ]) {
    assert.equal(parse({v: 1, ...msg}).ok, false);
  }
});

test('accepts each inbound message through native JSON and web objects', () => {
  for (const msg of [
    {v: 1, type: 'setMood', mood: 'mildSad'},
    {v: 1, type: 'setPaused', paused: false},
    {v: 1, type: 'setReducedMotion', on: true},
    {v: 1, type: 'pointer', phase: 'down', x: 3, y: 4, t: 0},
    {v: 1, type: 'loadModelChunk', i: 1, n: 2, b64: 'YQ=='},
  ]) {
    assert.deepEqual(parse(msg), {ok: true, msg});
    assert.deepEqual(parse(JSON.stringify(msg)), {ok: true, msg});
  }
});
