const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = (name) => fs.readFileSync(path.join(__dirname, '..', name), 'utf8');
const flush = () => new Promise(setImmediate);

function page(t) {
  const dom = new JSDOM('<div id="movie_player"><video class="html5-main-video"></video></div>', {
    url: 'https://www.youtube.com/watch?v=example', runScripts: 'outside-only', pretendToBeVisual: true
  });
  const { window } = dom;
  const video = window.document.querySelector('video');
  const state = { time: 0, paused: true, seeking: false, ended: false, rate: 1, pitch: false };
  const event = (type) => video.dispatchEvent(new window.Event(type));
  Object.defineProperties(video, {
    duration: { get: () => 120 }, readyState: { get: () => 4 },
    currentTime: { get: () => state.time, set: (value) => {
      state.time = value; state.seeking = true;
      queueMicrotask(() => { event('seeking'); state.seeking = false; event('seeked'); });
    } },
    paused: { get: () => state.paused }, ended: { get: () => state.ended }, seeking: { get: () => state.seeking },
    playbackRate: { get: () => state.rate, set: (value) => { state.rate = value; queueMicrotask(() => event('ratechange')); } },
    preservesPitch: { get: () => state.pitch, set: (value) => { state.pitch = value; } }
  });
  video.play = () => { state.paused = false; state.ended = false; return Promise.resolve(); };
  video.pause = () => { state.paused = true; };
  window.eval(source('core.js')); window.eval(source('content.js'));
  const root = window.document.querySelector('#gloop-panel').shadowRoot;
  const get = (id) => root.getElementById(id);
  const change = (id, value) => { get(id).value = value; get(id).dispatchEvent(new window.Event('change')); };
  const navigate = (id) => { window.history.pushState({}, '', '/watch?v=' + id); window.document.dispatchEvent(new window.Event('yt-navigate-finish')); };
  const advance = (time) => { state.time = time; event('timeupdate'); };
  t.after(() => { window.__gloop?.close(); window.close(); });
  return { window, video, state, root, get, change, advance, navigate };
}

test('panel repeats media and raises playback rate once per boundary', async (t) => {
  const p = page(t);
  p.change('a', '0:10.000'); p.change('b', '0:12.000');
  p.root.querySelector('[data-speed="75"]').click(); p.change('increment', '1');
  p.get('repeat').click(); await flush();
  assert.equal(p.state.time, 10); assert.equal(p.state.rate, .75); assert.equal(p.state.pitch, true);
  p.advance(12); p.advance(12); await flush();
  assert.equal(p.state.rate, .76);
  assert.match(p.get('status').textContent, /Loop 2/);
  p.advance(12); await flush();
  assert.equal(p.state.rate, .77);
  p.get('close').click();
  assert.equal(p.state.rate, 1); assert.equal(p.state.pitch, false);
  assert.equal(p.window.document.querySelector('#gloop-panel'), null);
});

test('invalid field edits cannot reuse old markers', (t) => {
  const p = page(t);
  p.change('a', '10'); p.change('b', '12'); p.change('b', 'invalid');
  p.get('repeat').click();
  assert.equal(p.get('repeat').getAttribute('aria-pressed'), 'false');
  assert.equal(p.state.paused, true);
});

test('manual seeking stops repetition; a new video clears settings', async (t) => {
  const p = page(t);
  p.change('a', '10'); p.change('b', '12'); p.change('increment', '5');
  p.get('repeat').click(); await flush();
  p.video.currentTime = 50; await flush();
  assert.equal(p.get('repeat').textContent, 'Start loop');
  p.navigate('another-video');
  assert.equal(p.get('b').value, ''); assert.equal(p.get('increment').value, '0');
});

test('ad playback does not get looped or sped up', async (t) => {
  const p = page(t);
  p.change('a', '10'); p.change('b', '12'); p.change('increment', '5');
  p.get('repeat').click(); await flush();
  p.window.document.querySelector('#movie_player').classList.add('ad-showing');
  p.advance(12); await flush();
  assert.equal(p.state.time, 12); assert.equal(p.state.rate, 1);
  p.window.document.dispatchEvent(new p.window.Event('yt-navigate-finish'));
  assert.equal(p.get('repeat').disabled, true);
  assert.equal(p.get('repeat').textContent, 'Start loop');
  p.window.document.querySelector('#movie_player').classList.remove('ad-showing');
  p.window.document.dispatchEvent(new p.window.Event('yt-navigate-finish'));
  assert.equal(p.get('repeat').disabled, false);
});

test('repeated toolbar injection closes the panel and removes event handlers', (t) => {
  const p = page(t);
  p.window.eval(source('core.js')); p.window.eval(source('content.js'));
  assert.equal(p.window.document.querySelectorAll('#gloop-panel').length, 0);
  p.window.eval(source('core.js')); p.window.eval(source('content.js'));
  assert.equal(p.window.document.querySelectorAll('#gloop-panel').length, 1);
});
