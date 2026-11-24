import assert from 'node:assert/strict';
import test from 'node:test';
import {createAssembler} from '../src/chunks.js';

for (const order of [[0, 1, 2], [2, 0, 1]]) {
  test(`assembles independently padded chunks in order ${order.join(', ')}`, () => {
    const {add} = createAssembler();
    const chunks = ['YQ==', 'YmM=', 'AP8='];
    assert.equal(add(order[0], 3, chunks[order[0]]), undefined);
    assert.equal(add(order[1], 3, chunks[order[1]]), undefined);
    assert.deepEqual(add(order[2], 3, chunks[order[2]]), Uint8Array.of(97, 98, 99, 0, 255));
  });
}

test('ignores duplicates without replacing previously received bytes', () => {
  const {add} = createAssembler();
  assert.equal(add(0, 2, 'YQ=='), undefined);
  assert.equal(add(0, 2, 'eA=='), undefined);
  assert.deepEqual(add(1, 2, 'Yg=='), Uint8Array.of(97, 98));
  assert.equal(add(1, 2, 'Yg=='), undefined);
});

test('rejects inconsistent chunk counts and invalid base64', () => {
  const {add} = createAssembler();
  add(0, 2, 'YQ==');
  assert.throws(() => add(0, 3, 'YQ=='), /Inconsistent/);
  assert.throws(() => add(1, 2, '===='));
});
