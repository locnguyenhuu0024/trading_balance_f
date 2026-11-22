import assert from 'node:assert/strict';
import test from 'node:test';
import {createClassifier} from '../src/gesture.js';

function fixture() {
  let clock = 0;
  const classifier = createClassifier({now: () => clock});
  return {
    sample(phase, x, y, t, region = 'head') {
      clock = t;
      return classifier.sample({phase, x, y, t, region});
    },
    tick(t) {
      clock = t;
      return classifier.tick();
    },
  };
}

test('a 300 ms head hold emits no pat', () => {
  const {sample} = fixture();
  sample('down', 0, 0, 0);
  assert.equal(sample('up', 0, 0, 300), undefined);
});

test('a 15 px head drag emits no pat even when it returns to the start', () => {
  const {sample} = fixture();
  sample('down', 0, 0, 0);
  assert.equal(sample('move', 15, 0, 100), undefined);
  assert.equal(sample('up', 0, 0, 200), undefined);
});

test('a 120 ms, 3 px head tap pats, and a body tap pokes', () => {
  const {sample} = fixture();
  sample('down', 0, 0, 0);
  assert.equal(sample('up', 3, 0, 120), 'pat');
  sample('down', 0, 0, 300, 'body');
  assert.equal(sample('up', 3, 0, 420, 'body'), 'poke');
});

test('three 20 px reversals start petting and the last leg sets the end time', () => {
  const {sample, tick} = fixture();
  sample('down', 0, 0, 0);
  assert.equal(sample('move', 20, 0, 200), undefined);
  assert.equal(sample('move', 0, 0, 400), undefined);
  assert.equal(sample('move', 20, 0, 600), 'pettingStart');
  assert.equal(sample('move', 0, 0, 900), undefined);
  sample('up', 0, 0, 920);
  assert.equal(tick(1499), undefined);
  assert.equal(tick(1500), 'pettingEnd');
  assert.equal(tick(1501), undefined);
});

test('a 60 px horizontal swipe outside the head emits once', () => {
  const {sample} = fixture();
  sample('down', 0, 0, 0, 'outside');
  assert.equal(sample('move', 40, 5, 100, 'outside'), undefined);
  assert.equal(sample('up', 60, 10, 200, 'outside'), 'swipe');
  assert.equal(sample('up', 60, 10, 201, 'outside'), undefined);
});

test('cancel discards a tap and interactions are debounced for 150 ms', () => {
  const {sample} = fixture();
  sample('down', 0, 0, 0);
  sample('cancel', 0, 0, 10);
  assert.equal(sample('up', 0, 0, 20), undefined);
  sample('down', 0, 0, 30);
  assert.equal(sample('up', 0, 0, 40), 'pat');
  sample('down', 0, 0, 150);
  assert.equal(sample('up', 0, 0, 189), undefined);
  sample('down', 0, 0, 189);
  assert.equal(sample('up', 0, 0, 190), 'pat');
});
