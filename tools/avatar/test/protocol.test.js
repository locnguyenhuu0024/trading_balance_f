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
    {v: 1, type: 'setColors', colors: {eyes: '#AAbbCc'}},
    {v: 1, type: 'setColors', colors: {
      dress: '#123456', bows: '#234567', socks: '#345678', plasters: '#456789',
    }},
    {v: 1, type: 'setColors', colors: {}},
    {v: 1, type: 'setPaused', paused: false},
    {v: 1, type: 'setReducedMotion', on: true},
    {v: 1, type: 'pointer', phase: 'down', x: 3, y: 4, t: 0},
    {v: 1, type: 'loadModelChunk', i: 1, n: 2, b64: 'YQ=='},
  ]) {
    assert.deepEqual(parse(msg), {ok: true, msg});
    assert.deepEqual(parse(JSON.stringify(msg)), {ok: true, msg});
  }
});

test('rejects invalid setColors payloads', () => {
  for (const fields of [
    {colors: {skin: '#123456'}},
    {colors: {['__proto__']: '#123456'}},
    {colors: {hair: '#fff'}},
    {colors: {hair: 'red'}},
    {colors: {hair: '#GGGGGG'}},
    {colors: {hair: 123456}},
    {colors: []},
    {colors: null},
    {colors: {}, extra: true},
    {},
  ]) {
    const msg = {v: 1, type: 'setColors', ...fields};
    assert.equal(parse(msg).ok, false);
    assert.equal(parse(JSON.stringify(msg)).ok, false);
  }
});

const outfit = 'donut-chan:outfit';
const shoes = 'donut-chan:shoes';
const plasters = 'donut-chan:plasters';

test('accepts empty, single-item, and full outfits through native and web', () => {
  for (const items of [[], [outfit], [outfit, shoes, plasters]]) {
    const msg = {v: 1, type: 'setOutfit', items};
    assert.deepEqual(parse(msg), {ok: true, msg});
    assert.deepEqual(parse(JSON.stringify(msg)), {ok: true, msg});
  }
});

test('rejects unknown, repeated, malformed, and extra outfit fields', () => {
  for (const fields of [
    {items: ['unknown']}, {items: ['constructor']}, {items: [outfit, outfit]},
    {items: outfit}, {items: [42]}, {items: [outfit, shoes, plasters, outfit]},
    {items: [outfit], extra: true}, {items: Array(1)},
  ]) {
    const msg = {v: 1, type: 'setOutfit', ...fields};
    assert.equal(parse(msg).ok, false);
    assert.equal(parse(JSON.stringify(msg)).ok, false);
  }
});

test('accepts donor chunks with the same chunk fields as the base transfer', () => {
  const msg = {v: 1, type: 'loadDonorChunk', model: 'donut-chan', i: 0, n: 1, b64: 'YQ=='};
  assert.deepEqual(parse(msg), {ok: true, msg});
  assert.deepEqual(parse(JSON.stringify(msg)), {ok: true, msg});
});

test('rejects invalid donor model ids, base64 fields, and chunk indices', () => {
  const valid = {v: 1, type: 'loadDonorChunk', model: 'donut-chan', i: 0, n: 1, b64: 'YQ=='};
  for (const fields of [{model: 'pixiv-sample'}, {b64: 'YQ%='}, {i: 1}, {extra: true}]) {
    const msg = {...valid, ...fields};
    assert.equal(parse(msg).ok, false);
    assert.equal(parse(JSON.stringify(msg)).ok, false);
  }
});

test('RED-157 / GREEN-157 accepts setFraming in native JSON and web objects', () => {
  for (const mode of ['half', 'full']) {
    const msg = {v: 1, type: 'setFraming', mode};
    assert.deepEqual(parse(msg), {ok: true, msg});
    assert.deepEqual(parse(JSON.stringify(msg)), {ok: true, msg});
  }
});

test('RED-157 / GREEN-157 rejects invalid setFraming payloads', () => {
  for (const fields of [{mode: 'FULL'}, {mode: 1}, {}, {mode: 'half', extra: true}]) {
    const msg = {v: 1, type: 'setFraming', ...fields};
    assert.equal(parse(msg).ok, false);
    assert.equal(parse(JSON.stringify(msg)).ok, false);
  }
});
