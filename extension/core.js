/* Shared by the content script and dependency-free Node tests. */
(() => {
  const clampSpeed = (value) => Math.min(125, Math.max(25, Math.round(value)));
  function parseTime(value) {
    if (!/^\d+(?::[0-5]\d){0,2}(?:\.\d{1,3})?$/.test(value.trim())) return NaN;
    return value.trim().split(":").reduce((total, part) => total * 60 + Number(part), 0);
  }
  function formatTime(value) {
    const ms = Math.round(Math.max(0, value) * 1000);
    return `${Math.floor(ms / 60000)}:${String(Math.floor(ms / 1000) % 60).padStart(2, "0")}.${String(ms % 1000).padStart(3, "0")}`;
  }
  class Loop {
    constructor() {
      this.a = 0;
      this.b = null;
      this.speed = 100;
      this.increment = 0;
      this.active = false;
      this.pendingSeek = false;
      this.count = 0;
    }
    valid(duration) {
      return Number.isFinite(duration) && duration > 0 && Number.isFinite(this.a) && Number.isFinite(this.b)
        && this.a >= 0 && this.b <= duration && this.b - this.a >= 0.25;
    }
    start(duration) {
      if (!this.valid(duration)) return null;
      this.active = true;
      this.pendingSeek = true;
      this.count = 1;
      return { time: this.a, speed: this.speed };
    }
    stop() { this.active = false; this.pendingSeek = false; }
    seeked() { this.pendingSeek = false; }
    tick({ time, duration, paused, seeking, ended, blocked }) {
      if (!this.active || this.pendingSeek || blocked || seeking || (paused && !ended) || !this.valid(duration)) return null;
      if (time < this.b && !ended) return null;
      if (this.speed < 100) this.speed = Math.min(100, this.speed + this.increment);
      this.count += 1;
      this.pendingSeek = true;
      return { time: this.a, speed: this.speed };
    }
  }
  function makeHandoff({ url, title, a, b, speed, increment, duration }) {
    const source = new URL(url), id = source.searchParams.get('v');
    if (source.protocol !== 'https:' || !['youtube.com', 'www.youtube.com'].includes(source.hostname) || source.pathname !== '/watch' || !/^[A-Za-z0-9_-]{11}$/.test(id || '')) throw new Error('Open a YouTube video first.');
    if (!Number.isFinite(a) || a < 0 || a >= duration || a > 86400 ||
        (b !== null && (!Number.isFinite(b) || b > duration || b > 86400 || b - a < .25))) throw new Error('Check the A and B times before saving.');
    if (!Number.isFinite(speed) || speed < 25 || speed > 125 || ![0, 1, 5].includes(increment)) throw new Error('Check the playback speed before saving.');
    return { version: 1, url: `https://www.youtube.com/watch?v=${id}`, title: title.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ').slice(0, 500), a, b, speed, increment };
  }
  const api = { Loop, parseTime, formatTime, clampSpeed, makeHandoff };
  if (typeof module !== "undefined") module.exports = api;
  else globalThis.GLoopCore = api;
})();
