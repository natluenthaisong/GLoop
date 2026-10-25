const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Loop, parseTime, formatTime } = require('../core.js');
const { makeHandoff } = require('../core.js');

test('Mac export contains just the canonical video and portable settings', () => {
  const input = { url: 'https://www.youtube.com/watch?v=abcdefghijk&list=private-list&t=1', title: 'Phrase\nTest', a: 10, b: 12, speed: 75, increment: 1, duration: 60 };
  assert.deepEqual(makeHandoff(input), { version: 1, url: 'https://www.youtube.com/watch?v=abcdefghijk', title: 'Phrase Test', a: 10, b: 12, speed: 75, increment: 1 });
  assert.equal(makeHandoff({ ...input, a: 0, b: null }).b, null);
  for (const fields of [{ a: NaN }, { b: NaN }, { b: 9 }, { b: 100 }, { speed: 500 }, { increment: 10 }, { url: 'https://evil.test/watch?v=abcdefghijk' }]) assert.throws(() => makeHandoff({ ...input, ...fields }));
});

test('time fields accept seconds, minutes and hours without ambiguous seconds', () => {
  assert.equal(parseTime('1:23.500'), 83.5);
  assert.equal(parseTime('1:02:03'), 3723);
  assert.equal(parseTime(' 12.25 '), 12.25);
  for (const value of ['', '-1', '1:99', '1:2', 'Infinity', '1x']) assert.ok(Number.isNaN(parseTime(value)), value);
  assert.equal(formatTime(59.9999), '1:00.000');
});

function phrase(speed = 75, increment = 1) {
  const loop = new Loop();
  Object.assign(loop, { a: 10, b: 12, speed, increment });
  return loop;
}
const boundary = { time: 12, duration: 100, paused: false, seeking: false, ended: false, blocked: false };

test('only a valid, finite phrase can start', () => {
  const loop = phrase();
  assert.equal(loop.start(Infinity), null);
  assert.equal(loop.start(11), null);
  loop.b = 10.1;
  assert.equal(loop.start(100), null);
  loop.a = -1;
  assert.equal(loop.start(100), null);
});

test('each completed loop increases speed once even while seek is pending', () => {
  const loop = phrase();
  assert.deepEqual(loop.start(100), { time: 10, speed: 75 });
  assert.equal(loop.count, 1);
  assert.equal(loop.tick(boundary), null);
  loop.seeked();
  assert.equal(loop.tick({ ...boundary, time: 11.999 }), null);
  assert.deepEqual(loop.tick(boundary), { time: 10, speed: 76 });
  assert.equal(loop.tick(boundary), null);
  assert.equal(loop.count, 2);
  loop.seeked();
  assert.deepEqual(loop.tick(boundary), { time: 10, speed: 77 });
});

test('five-point progression caps at 100 without reducing manual higher speeds', () => {
  for (const [initial, expected] of [[98, 100], [100, 100], [125, 125]]) {
    const loop = phrase(initial, 5);
    loop.start(100); loop.seeked();
    assert.equal(loop.tick(boundary).speed, expected);
  }
  const loop = phrase(75, 0);
  loop.start(100); loop.seeked();
  assert.equal(loop.tick(boundary).speed, 75);
});

test('pauses, seeking and ads do not advance loops; ended media can repeat', () => {
  const loop = phrase();
  loop.start(100); loop.seeked();
  for (const reason of ['paused', 'seeking', 'blocked']) assert.equal(loop.tick({ ...boundary, [reason]: true }), null);
  assert.equal(loop.count, 1);
  assert.deepEqual(loop.tick({ ...boundary, paused: true, ended: true }), { time: 10, speed: 76 });
  loop.stop(); loop.seeked();
  assert.equal(loop.tick(boundary), null);
});
