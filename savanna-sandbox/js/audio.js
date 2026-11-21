// Sound, all synthesised with WebAudio (no recordings): animal calls, work sounds,
// weather, fire, battle. Sounds are positional in a simple way: the further from the
// point the camera looks at, the quieter; out of earshot they are not played at all.
// Browsers only allow audio after a click, so the context starts on the first input.
export function createAudio(G) {
  const A = { volume: 0.7, on: true, ctx: null };
  let ctx = null, master = null, noiseBuf = null;
  const lastAt = {};
  const loops = {};

  const start = () => {
    if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    ctx = A.ctx = new AC();
    master = ctx.createGain();
    master.gain.value = A.on ? A.volume : 0;
    const comp = ctx.createDynamicsCompressor();
    master.connect(comp); comp.connect(ctx.destination);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    loops.wind = loop('lowpass', 420, 0.5);
    loops.rain = loop('bandpass', 3200, 0.6);
    loops.fire = loop('bandpass', 900, 1.2);
    loops.river = loop('bandpass', 1500, 0.8);
    loops.crickets = cricketLoop();
  };
  window.addEventListener('pointerdown', start, { capture: true });
  window.addEventListener('keydown', start, { capture: true });

  A.setVolume = (v) => { A.volume = v; if (master) master.gain.setTargetAtTime(A.on ? v : 0, ctx.currentTime, 0.05); };
  A.setOn = (on) => { A.on = on; A.setVolume(A.volume); };

  // ---- building blocks
  const env = (g, t, a, peak, d) => { g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + a); g.gain.exponentialRampToValueAtTime(0.0001, t + a + d); };
  const tone = (type, f0, f1, dur, peak, t = ctx.currentTime, attack = 0.01, out = master) => {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
    env(g, t, attack, peak, dur);
    o.connect(g); g.connect(out); o.start(t); o.stop(t + dur + attack + 0.05);
    return o;
  };
  const noise = (ftype, freq, qv, dur, peak, t = ctx.currentTime, attack = 0.005, out = master, f1 = freq) => {
    const src = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    src.buffer = noiseBuf; src.loop = true;
    f.type = ftype; f.frequency.setValueAtTime(freq, t); f.frequency.exponentialRampToValueAtTime(Math.max(30, f1), t + dur); f.Q.value = qv;
    env(g, t, attack, peak, dur);
    src.connect(f); f.connect(g); g.connect(out);
    src.start(t, Math.random()); src.stop(t + dur + attack + 0.05);
  };
  function loop(ftype, freq, qv) {
    const src = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    src.buffer = noiseBuf; src.loop = true; f.type = ftype; f.frequency.value = freq; f.Q.value = qv; g.gain.value = 0;
    src.connect(f); f.connect(g); g.connect(master); src.start();
    return g;
  }
  function cricketLoop() {
    const o = ctx.createOscillator(), lfo = ctx.createOscillator(), lg = ctx.createGain(), g = ctx.createGain(), out = ctx.createGain();
    o.type = 'sine'; o.frequency.value = 4300; lfo.type = 'square'; lfo.frequency.value = 17; lg.gain.value = 0.5; g.gain.value = 0.5; out.gain.value = 0;
    lfo.connect(lg); lg.connect(g.gain); o.connect(g); g.connect(out); out.connect(master); o.start(); lfo.start();
    return out;
  }
  const vib = (o, rate, depth, t, dur) => {
    const l = ctx.createOscillator(), g = ctx.createGain();
    l.frequency.value = rate; g.gain.value = depth; l.connect(g); g.connect(o.frequency); l.start(t); l.stop(t + dur + 0.1);
  };

  // ---- the sounds. v is the loudness after distance.
  const S = {
    roar: (v) => { const t = ctx.currentTime; const o = tone('sawtooth', 95, 48, 1.3, 0.5 * v, t, 0.12); vib(o, 22, 9, t, 1.3); noise('lowpass', 520, 0.7, 1.2, 0.35 * v, t, 0.1, master, 180); },
    trumpet: (v) => { const t = ctx.currentTime; const o = tone('sawtooth', 380, 560, 0.9, 0.22 * v, t, 0.06); vib(o, 28, 26, t, 0.9); tone('square', 760, 1040, 0.8, 0.07 * v, t + 0.03, 0.06); },
    zebra: (v) => { const t = ctx.currentTime; for (let i = 0; i < 4; i++) tone('sawtooth', 620 - i * 30, 300, 0.11, 0.16 * v, t + i * 0.13, 0.01); },
    grunt: (v) => { const t = ctx.currentTime; tone('sawtooth', 130, 85, 0.22, 0.26 * v, t, 0.02); tone('sawtooth', 120, 80, 0.2, 0.2 * v, t + 0.3, 0.02); },
    hyena: (v) => { const t = ctx.currentTime; for (let i = 0; i < 5; i++) tone('triangle', 500 + i * 70, 900 + i * 90, 0.12, 0.17 * v, t + i * 0.15, 0.015); },
    bird: (v) => { const t = ctx.currentTime; const n = 2 + Math.floor(Math.random() * 3); for (let i = 0; i < n; i++) tone('sine', 2300 + Math.random() * 900, 3200 + Math.random() * 900, 0.07, 0.07 * v, t + i * 0.1, 0.01); },
    vulture: (v) => { const t = ctx.currentTime; noise('bandpass', 1900, 5, 0.35, 0.16 * v, t, 0.03, master, 1300); },
    splash: (v) => { const t = ctx.currentTime; noise('bandpass', 900, 0.7, 0.5, 0.45 * v, t, 0.01, master, 300); noise('highpass', 3000, 0.5, 0.3, 0.14 * v, t + 0.04); },
    chop: (v) => { const t = ctx.currentTime; tone('triangle', 210, 120, 0.07, 0.4 * v, t, 0.002); noise('bandpass', 1400, 2, 0.05, 0.22 * v, t, 0.002); },
    timber: (v) => { const t = ctx.currentTime; noise('lowpass', 900, 0.6, 0.7, 0.4 * v, t, 0.05, master, 150); tone('sine', 70, 40, 0.3, 0.5 * v, t + 0.5, 0.01); },
    hammer: (v) => { const t = ctx.currentTime; tone('square', 420, 300, 0.04, 0.16 * v, t, 0.002); noise('bandpass', 2400, 3, 0.04, 0.16 * v, t, 0.002); },
    pick: (v) => { const t = ctx.currentTime; tone('sine', 1500, 1250, 0.14, 0.2 * v, t, 0.002); tone('sine', 2330, 2100, 0.09, 0.09 * v, t, 0.002); noise('highpass', 4000, 1, 0.03, 0.09 * v, t, 0.001); },
    spear: (v) => { noise('highpass', 2600, 1, 0.12, 0.13 * v, ctx.currentTime, 0.01, master, 800); },
    clash: (v) => { const t = ctx.currentTime; noise('bandpass', 3300, 6, 0.09, 0.2 * v, t, 0.002); tone('square', 1100 + Math.random() * 500, 700, 0.06, 0.05 * v, t, 0.002); },
    cry: (v) => { tone('sawtooth', 520, 240, 0.25, 0.12 * v, ctx.currentTime, 0.02); },
    drum: (v) => { const t = ctx.currentTime; [0, 0.28, 0.56, 0.7, 0.98, 1.26, 1.4].forEach((d, i) => { tone('sine', 110, 52, 0.22, 0.75 * v, t + d, 0.004); noise('lowpass', 300, 1, 0.08, 0.2 * v, t + d, 0.002); }); },
    horn: (v) => { const t = ctx.currentTime; const o = tone('sawtooth', 146, 150, 1.4, 0.24 * v, t, 0.15); vib(o, 5, 2, t, 1.4); tone('sawtooth', 219, 224, 1.3, 0.1 * v, t + 0.05, 0.15); },
    thunder: (v) => { const t = ctx.currentTime; noise('highpass', 2500, 0.5, 0.12, 0.5 * v, t, 0.002); noise('lowpass', 500, 0.6, 2.4, 0.9 * v, t + 0.05, 0.03, master, 70); tone('sine', 60, 32, 1.6, 0.5 * v, t + 0.1, 0.05); },
    boom: (v) => { const t = ctx.currentTime; tone('sine', 85, 24, 2.2, 1.0 * v, t, 0.005); noise('lowpass', 1400, 0.5, 2.6, 0.9 * v, t, 0.005, master, 60); noise('bandpass', 2600, 0.8, 0.5, 0.3 * v, t + 0.05); },
    whoosh: (v) => { noise('bandpass', 500, 1.2, 1.6, 0.45 * v, ctx.currentTime, 0.9, master, 2600); },
    build: (v) => { const t = ctx.currentTime; [523, 659, 784].forEach((f, i) => tone('triangle', f, f, 0.2, 0.12 * v, t + i * 0.09, 0.01)); },
    era: (v) => { const t = ctx.currentTime; [392, 523, 659, 784, 1047].forEach((f, i) => { tone('triangle', f, f, 0.5, 0.16 * v, t + i * 0.13, 0.02); tone('sine', f / 2, f / 2, 0.5, 0.1 * v, t + i * 0.13, 0.02); }); },
    cough: (v) => { const t = ctx.currentTime; noise('bandpass', 700, 2, 0.1, 0.25 * v, t, 0.01); noise('bandpass', 600, 2, 0.12, 0.2 * v, t + 0.16, 0.01); },
    bless: (v) => { const t = ctx.currentTime; [784, 988, 1175, 1568].forEach((f, i) => tone('sine', f, f, 0.6, 0.1 * v, t + i * 0.07, 0.03)); },
    click: () => { tone('sine', 880, 660, 0.05, 0.08, ctx.currentTime, 0.002); },
  };
  const GAP = { chop: 0.16, hammer: 0.13, pick: 0.2, clash: 0.07, spear: 0.2, bird: 0.5, cry: 0.25, splash: 0.3, cough: 0.5, build: 0.4, zebra: 1.5, grunt: 1.2, roar: 2.5, trumpet: 2.5, hyena: 2, vulture: 2, thunder: 0.3 };
  const REACH = { thunder: 3, boom: 5, drum: 3, horn: 3, roar: 1.6, trumpet: 1.6, whoosh: 2.5, era: 4, timber: 1.3 };

  // Play `name` at a place on the map (or everywhere if no place is given).
  A.play = (name, x, z) => {
    if (!ctx || !A.on || ctx.state !== 'running' || !S[name]) return;
    let v = 1;
    if (x !== undefined) {
      const cam = G.stage.cam;
      const d = Math.hypot(x - cam.tx, z - cam.tz);
      const reach = (cam.dist * 0.75 + 55) * (REACH[name] || 1);
      if (d > reach) return;
      v = Math.pow(1 - d / reach, 1.4) * Math.min(1, 95 / (cam.dist + 30)) * 1.6;
      v = Math.min(1, v * (REACH[name] ? 1.3 : 1));
    }
    const now = ctx.currentTime;
    if (now - (lastAt[name] || -9) < (GAP[name] || 0.05)) return;
    lastAt[name] = now;
    try { S[name](v); } catch (e) { /* never let a sound break the game */ }
  };

  // Steady background sounds follow what is happening near the camera.
  let slow = 0;
  A.render = (real) => {
    if (!ctx || ctx.state !== 'running') return;
    slow -= real;
    if (slow > 0) return;
    slow = 0.25;
    const cam = G.stage.cam, t = ctx.currentTime, T = G.terrain;
    const near = Math.min(1, 110 / (cam.dist + 30));
    let rain = 0;
    for (const r of G.env.rains) rain = Math.max(rain, Math.hypot(r.x - cam.tx, r.z - cam.tz) < r.r + cam.dist * 0.5 ? 1 : 0);
    let fire = 0;
    const fs = G.fx.fireSum;
    if (fs.n) fire = Math.min(1, fs.n / 60) * Math.max(0, 1 - Math.hypot(fs.x / fs.n - cam.tx, fs.z / fs.n - cam.tz) / (cam.dist + 120));
    let water = 0;
    for (const [dx, dz] of [[0, 0], [14, 0], [-14, 0], [0, 14], [0, -14]]) if (T.isWater(cam.tx + dx, cam.tz + dz)) water += 0.2;
    const night = G.stage.night;
    loops.wind.gain.setTargetAtTime(0.05 + 0.05 * (cam.dist / 230), t, 0.5);
    loops.rain.gain.setTargetAtTime(rain * 0.22, t, 0.4);
    loops.fire.gain.setTargetAtTime(fire * 0.3, t, 0.3);
    loops.river.gain.setTargetAtTime(water * 0.06 * near, t, 0.6);
    loops.crickets.gain.setTargetAtTime(night > 0.6 ? 0.012 * near + 0.004 : 0, t, 0.8);
    if (night < 0.5 && Math.random() < 0.1) A.play('bird', cam.tx + (Math.random() - 0.5) * 60, cam.tz + (Math.random() - 0.5) * 60);
  };
  return A;
}
