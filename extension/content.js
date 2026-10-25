(() => {
  if (globalThis.__gloop) { globalThis.__gloop.close(); return; }
  const { Loop, parseTime, formatTime, clampSpeed, makeHandoff } = globalThis.GLoopCore;
  const loop = new Loop();
  const host = document.createElement("div");
  host.id = "gloop-panel";
  host.setAttribute("translate", "no");
  const root = host.attachShadow({ mode: "open" });
  root.innerHTML = `
    <style>
      :host { all: initial; position: fixed; right: 16px; bottom: 16px; z-index: 2147483647; width: min(336px, calc(100vw - 32px)); color-scheme: dark; }
      * { box-sizing: border-box; }
      section { --bg: #242424; --text: #f2f2f2; --muted: #bdbdbd; --control: #363636; --border: #666; background: var(--bg); color: var(--text); border: 1px solid var(--border); border-radius: 8px; padding: 16px; font: 14px/1.4 system-ui, sans-serif; max-height: calc(100dvh - 32px); overflow: auto; }
      header, .row { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
      header { margin-bottom: 12px; }
      h2 { font: 600 15px/1.4 system-ui, sans-serif; margin: 0; }
      button, input, select { font: inherit; color: var(--text); border: 1px solid var(--border); border-radius: 4px; }
      button, select { background: var(--control); cursor: pointer; min-height: 36px; padding: 6px 10px; }
      button:hover:not(:disabled) { background: #484848; }
      button:active:not(:disabled) { background: #555; }
      :focus-visible { outline: 2px solid #b8d7ff; outline-offset: 3px; }
      button:disabled, input:disabled, select:disabled { opacity: .45; cursor: default; }
      #close { border: 0; background: transparent; min-height: 28px; padding: 2px 6px; color: var(--muted); }
      .markers { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
      label { display: block; }
      .markers .row { margin-bottom: 6px; }
      .markers input { width: 100%; background: #191919; padding: 8px; font-variant-numeric: tabular-nums; }
      #repeat { flex: 1; background: #e4e4e4; color: #171717; border-color: #e4e4e4; font-weight: 600; }
      #repeat:hover:not(:disabled) { background: white; }
      .actions { margin-top: 12px; }
      .speed { border-top: 1px solid #484848; margin-top: 16px; padding-top: 12px; }
      output { font-variant-numeric: tabular-nums; }
      #speed { width: 100%; margin: 12px 0; accent-color: #ddd; }
      .presets button { flex: 1; }
      .auto { margin-top: 12px; }
      #handoff { width: 100%; margin-top: 16px; }
      #status { font-size: 12px; color: var(--muted); margin: 12px 0 0; min-height: 17px; }
      @media (prefers-color-scheme: light) {
        :host { color-scheme: light; }
        section { --bg: #fafafa; --text: #222; --muted: #555; --control: #eee; --border: #aaa; }
        button:hover:not(:disabled) { background: #ddd; }
        button:active:not(:disabled) { background: #ccc; }
        .markers input { background: white; }
        .speed { border-color: #ddd; }
        #repeat { background: #333; color: white; border-color: #333; }
        #repeat:hover:not(:disabled) { background: #111; }
        #speed { accent-color: #444; }
        :focus-visible { outline-color: #2457a6; }
      }
    </style>
    <section aria-label="GLoop practice controls">
      <header><h2>GLoop</h2><button id="close" title="Stop looping and restore the previous speed">Close</button></header>
      <div class="markers">
        <div><div class="row"><label for="a">A · Start</label><button id="set-a">Set here</button></div><input id="a" value="0:00.000" aria-label="Loop start A" spellcheck="false"></div>
        <div><div class="row"><label for="b">B · End</label><button id="set-b">Set here</button></div><input id="b" placeholder="Set end" aria-label="Loop end B" spellcheck="false"></div>
      </div>
      <div class="row actions"><button id="repeat" aria-pressed="false">Start loop</button><button id="clear">Clear</button></div>
      <div class="speed">
        <div class="row"><label for="speed">Speed</label><output id="rate" for="speed">100%</output></div>
        <input id="speed" type="range" min="25" max="125" step="1" value="100" aria-label="Playback speed percent">
        <div class="row presets"><button data-speed="50">50%</button><button data-speed="75">75%</button><button data-speed="100">100%</button></div>
        <div class="row auto"><label for="increment">Increase each loop</label><select id="increment"><option value="0">Off</option><option value="1">+1%</option><option value="5">+5%</option></select></div>
      </div>
      <button id="handoff" title="Save the link and settings. Open the file in GLoop Mac to download the video.">Save for Mac…</button>
      <p id="status" role="status" aria-live="polite">Set A and B to loop a phrase.</p>
    </section>`;
  (document.fullscreenElement || document.body).append(host);
  const $ = (id) => root.getElementById(id);
  const listeners = [];
  let video = null, originalRate = 1, originalPitch = true, id = "", blocked = false, closed = false, frame = 0;
  const videoId = () => location.pathname === "/watch" ? new URL(location.href).searchParams.get("v") || "" : "";
  const adShowing = () => !!document.querySelector("#movie_player.ad-showing, #movie_player.ad-interrupting");
  function on(target, event, handler) { target.addEventListener(event, handler); listeners.push(() => target.removeEventListener(event, handler)); }
  function message(text) { if ($("status").textContent !== text) $("status").textContent = text; }
  function render() {
    $("repeat").textContent = loop.active ? "Stop loop" : "Start loop";
    $("repeat").setAttribute("aria-pressed", String(loop.active));
    $("rate").textContent = `${loop.speed}%`;
    $("speed").value = loop.speed;
    $("increment").value = loop.increment;
    if (loop.active) message(`Loop ${loop.count}${loop.increment ? " · Speed increases up to 100%" : ""}`);
  }
  function available() { return video && id && !blocked && !adShowing() && Number.isFinite(video.duration) && video.duration > 0; }
  function setSpeed(value) {
    if (!available()) return;
    loop.speed = clampSpeed(value);
    video.preservesPitch = true;
    video.playbackRate = loop.speed / 100;
    render();
  }
  function stop(text) { loop.stop(); render(); if (text) message(text); }
  function seek(action) {
    if (!action || !video) return;
    video.preservesPitch = true;
    video.playbackRate = action.speed / 100;
    // Setting the same currentTime may not dispatch seeked in every browser.
    if (Math.abs(video.currentTime - action.time) < .001) loop.seeked();
    else video.currentTime = action.time;
    const playingVideo = video, playingId = id;
    video.play().catch(() => { if (!closed && video === playingVideo && id === playingId && loop.active) stop("Press Play on YouTube, then start the loop."); });
    render();
  }
  function tick() {
    if (available()) seek(loop.tick({ time: video.currentTime, duration: video.duration, paused: video.paused, seeking: video.seeking, ended: video.ended, blocked: adShowing() }));
  }
  function animate() { tick(); if (!closed) frame = requestAnimationFrame(animate); }
  function reset() {
    loop.stop(); loop.a = 0; loop.b = null; loop.count = 0; loop.increment = 0;
    $("a").value = "0:00.000"; $("b").value = "";
    $("a").removeAttribute("aria-invalid"); $("b").removeAttribute("aria-invalid");
    render(); message("Set A and B to loop a phrase.");
  }
  function restore() {
    if (video && !adShowing()) { video.playbackRate = originalRate; video.preservesPitch = originalPitch; }
  }
  function detach() {
    if (!video) return;
    for (const [event, handler] of Object.entries(mediaEvents)) video.removeEventListener(event, handler);
  }
  const mediaEvents = {
    timeupdate: tick,
    ended: tick,
    seeked: () => { loop.seeked(); },
    seeking: () => { if (loop.active && !loop.pendingSeek && !adShowing()) stop("Loop stopped after seeking. Start loop to repeat again."); },
    ratechange: () => { if (available() && !adShowing()) { loop.speed = clampSpeed(video.playbackRate * 100); render(); } }
  };
  function sync() {
    const nextId = videoId();
    const nextVideo = document.querySelector("#movie_player video.html5-main-video");
    if (nextId !== id || nextVideo !== video) {
      restore(); detach(); reset(); id = nextId; video = nextVideo;
      if (video) {
        originalRate = video.playbackRate; originalPitch = video.preservesPitch;
        loop.speed = clampSpeed(originalRate * 100);
        for (const [event, handler] of Object.entries(mediaEvents)) video.addEventListener(event, handler);
        render();
      }
    }
    const wasBlocked = blocked;
    blocked = adShowing();
    if (blocked && !wasBlocked) { loop.stop(); render(); }
    const ready = available();
    for (const control of root.querySelectorAll("button:not(#close), input, select")) control.disabled = !ready;
    if (blocked) message("Controls paused during ads. Start the loop again afterward.");
    else if (!id) message("Open a regular YouTube video to practice.");
    else if (!video || video.readyState === 0) message("Waiting for the video…");
    else if (!Number.isFinite(video.duration)) message("Live streams are not supported.");
    else if (wasBlocked) message("Set A and B, or start your loop again.");
    else if (!loop.active && $("status").textContent === "Waiting for the video…") message("Set A and B to loop a phrase.");
  }
  function updateMarker(which, value) {
    if (!available()) return;
    if (!Number.isFinite(value) || value < 0 || value > video.duration) {
      $(which).setAttribute("aria-invalid", "true");
      stop("Enter a time within the video, such as 1:23.500."); return;
    }
    $(which).removeAttribute("aria-invalid");
    stop(); loop[which] = value; loop.count = 0;
    $(which).value = formatTime(value);
    message(loop.valid(video.duration) ? "Ready to loop." : "Set B at least 0.25 seconds after A.");
  }
  for (const which of ["a", "b"]) {
    on($("set-" + which), "click", () => { if (available()) updateMarker(which, video.currentTime); });
    on($(which), "change", () => updateMarker(which, parseTime($(which).value)));
    on($(which), "keydown", (event) => { if (event.key === "Enter") { updateMarker(which, parseTime($(which).value)); $(which).blur(); } });
  }
  on($("repeat"), "click", () => {
    if (loop.active) { stop("Loop stopped."); return; }
    if (!available()) return;
    // Revalidate the visible fields so invalid edits cannot start stale markers.
    loop.a = parseTime($("a").value); loop.b = parseTime($("b").value);
    const action = loop.start(video.duration);
    if (!action) { message("Set B at least 0.25 seconds after A, within the video."); return; }
    seek(action);
  });
  on($("clear"), "click", reset);
  on($("speed"), "input", () => setSpeed(Number($("speed").value)));
  for (const button of root.querySelectorAll("[data-speed]")) on(button, "click", () => setSpeed(Number(button.dataset.speed)));
  on($("increment"), "change", () => { loop.increment = Number($("increment").value); render(); });
  on($("handoff"), "click", () => {
    if (!available()) return;
    try {
      const title = document.querySelector('ytd-watch-metadata h1')?.textContent?.trim() || document.title.replace(/ - YouTube$/, '');
      const handoff = makeHandoff({ url: location.href, title, a: parseTime($("a").value), b: $("b").value.trim() ? parseTime($("b").value) : null, speed: loop.speed, increment: loop.increment, duration: video.duration });
      const blob = new Blob([JSON.stringify(handoff, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob), link = document.createElement('a');
      link.href = url; link.download = `GLoop-${id}.gloop`; root.append(link); link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 10000);
      message('Open the .gloop file in GLoop Mac to download the video.');
    } catch (error) { message(error.message); }
  });
  // Keep typing and Space inside the panel from triggering YouTube shortcuts.
  on(root, "keydown", (event) => { event.stopPropagation(); if (event.key === "Escape") close(); });
  on(root, "keyup", (event) => event.stopPropagation());
  on(document, "yt-navigate-start", () => { stop(); });
  on(document, "yt-navigate-finish", sync);
  on(document, "fullscreenchange", () => { (document.fullscreenElement || document.body).append(host); });
  on($("close"), "click", close);
  function close() {
    if (closed) return;
    closed = true; loop.stop(); restore(); detach(); listeners.forEach((remove) => remove());
    clearInterval(interval); cancelAnimationFrame(frame); host.remove(); delete globalThis.__gloop;
  }
  globalThis.__gloop = { close };
  const interval = setInterval(sync, 400);
  sync(); animate(); $("set-a").focus();
})();
