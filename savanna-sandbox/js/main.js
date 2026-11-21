// Boot and main loop. The simulation runs in fixed 1/30 s steps so a run with the
// same seed and the same inputs always plays out the same way.
import * as THREE from '../vendor/three/three.module.js';
import { makeRng } from './util.js';
import { createStage } from './stage.js';
import { createTerrain, N, K } from './terrain.js';
import { createFlora } from './flora.js';
import { modelLineup, assetLineup } from './debug.js';
import { createFx } from './fx.js';
import { createAnimals } from './animals.js';
import { createTribes } from './tribes.js';
import { createEnv } from './env.js';
import { createUI } from './ui.js';
import { createPost } from './post.js';
import { createDirector } from './director.js';
import { createRoom } from './room.js';
import { loadAssets } from './assets.js';
import { createAudio } from './audio.js';
import { CreatureKind } from './creatures.js';

const params = new URLSearchParams(location.search);
const seed = +(params.get('seed') || 7);
const STEP = 1 / 30;
const DAY = 120;              // seconds of simulation per day

const stage = createStage(document.getElementById('view'));
const rng = makeRng(seed);
const villages = [{ x: 33 * K, z: 50 * K }, { x: 64 * K, z: 71 * K }];
const terrain = createTerrain(stage.scene, seed, villages);
const room = params.get('room') === '1' ? createRoom(stage) : null;
if (room) stage.room = room;
terrain.setFramed(!!room);

const G = window.G = {
  DAY,
  ready: false, stage, terrain, rng, villages,
  time: DAY * 0.36, speed: 1, paused: false, events: [], systems: [],
  setSpeed(s) { G.speed = s; },
  get day() { return Math.floor(G.time / DAY) + 1; },
  log(type, data = {}) { G.events.push({ t: +G.time.toFixed(2), type, ...data }); },
  stats() { return { time: G.time, day: G.day, fps: G.fps }; },
  // Player settings (kept in the browser between visits).
  opts: { dayMode: 'cycle', sound: true, volume: 0.7, predators: true, nature: true, colonies: true, haze: true, labels: true },
  setOpt(k, v) {
    G.opts[k] = v;
    try { localStorage.setItem('savanna-opts', JSON.stringify(G.opts)); } catch (e) { /* private window: settings just do not persist */ }
    G.applyOpts();
  },
  applyOpts() {
    const o = G.opts;
    G.dayOverride = o.dayMode === 'day' ? 0.46 : o.dayMode === 'night' ? 0.04 : undefined;
    stage.haze = o.haze;
    if (G.audio) { G.audio.setOn(o.sound); G.audio.setVolume(o.volume); }
  },
  // People keep the day-and-night routine only when the sun actually moves.
  isNight() { return G.opts.dayMode === 'cycle' && G.dayOverride === undefined && stage.night > 0.6; },
  sfx(name, x, z) { if (G.audio) G.audio.play(name, x, z); },
};
try { Object.assign(G.opts, JSON.parse(localStorage.getItem('savanna-opts') || '{}')); } catch (e) { /* keep defaults */ }
for (const k of ['dayMode', 'predators', 'nature', 'colonies']) if (params.has(k)) G.opts[k] = k === 'dayMode' ? params.get(k) : params.get(k) !== '0';
CreatureKind.view = stage.view;

G.assets = params.get('assets') === '0' ? {} : await loadAssets();
G.flora = createFlora(G);
G.fx = createFx(G);
if (params.get('debug') === 'models') modelLineup(G);
else if (params.get('debug') === 'assets') assetLineup(G);
else {
  G.animals = createAnimals(G);
  G.tribes = createTribes(G);
  G.env = createEnv(G);
  const lang = params.get('lang') || G.opts.lang || ((navigator.language || 'en').startsWith('zh') ? 'zh' : 'en');
  document.title = lang === 'zh' ? '草原沙盘' : 'Savanna Sandbox';
  document.documentElement.lang = lang;
  G.ui = createUI(G, lang);
  if (params.get('ui') === '0') document.body.classList.add('bare');
  G.audio = createAudio(G);
  G.applyOpts();
  G.systems.push(G.env, G.flora, G.animals, G.tribes, G.ui, G.audio);
  // start by the red people's camp
  Object.assign(stage.cam, { tx: villages[0].x, tz: villages[0].z + 6, dist: 120 });
  G.power = (name, x, z) => G.env.powers[name](x, z);
  G.stats = () => ({ t: Math.round(G.time), day: G.day, fps: G.fps, animals: G.animals.all.length, tribes: G.tribes.summary(), villages: G.tribes.tribes.length, trees: G.flora.count(), fire: G.env.burning.size, particles: G.fx.lit.items.length + G.fx.glow.items.length });
}
G.systems.push(G.fx);
const post = params.get('post') === '0' ? null : createPost(stage);
G.post = post;
if (post) stage.bgBoost = 1.55;
if (params.get('demo') === '1' && G.tribes) { G.director = createDirector(G); G.systems.push(G.director); }
// The show reel drives the camera. The first click, drag or scroll hands control back to
// the player (not while recording: `hold=1` keeps the reel running).
if (G.director && params.get('hold') !== '1') {
  const take = () => {
    if (!G.director.on) return;
    G.director.on = false;
    G.applyOpts();
    G.setSpeed(1);
    document.body.classList.remove('bare');
  };
  const view = document.getElementById('view');
  view.addEventListener('pointerdown', take, { capture: true });
  view.addEventListener('wheel', take, { capture: true, passive: true });
}

// A head count every 30 simulated seconds, for charts and for the video's counters.
let censusAt = 0;
function simulate(dt) {
  G.time += dt;
  if (G.tribes && G.time >= censusAt) {
    censusAt = G.time + 30;
    const s = G.tribes.summary();
    G.log('census', { day: +(G.time / DAY + 1).toFixed(2), people: s[0].pop + s[1].pop, towns: s[0].villages + s[1].villages, era: Math.max(s[0].era, s[1].era), animals: G.animals.all.length + G.animals.crocs.length, trees: G.flora.count() });
  }
  for (const s of G.systems) s.update && s.update(dt);
}

let last = performance.now(), acc = 0, frames = 0, fpsT = 0;
function frame(now) {
  requestAnimationFrame(frame);
  const real = Math.min(0.1, (now - last) / 1000);
  last = now;
  frames++; fpsT += real;
  if (fpsT >= 1) { G.fps = Math.round(frames / fpsT); frames = 0; fpsT = 0; }
  if (!G.paused) {
    acc += real * G.speed;
    let n = 0;
    while (acc >= STEP && n < 160) { simulate(STEP); acc -= STEP; n++; }
    if (n === 160) acc = 0;
  }
  stage.setTime(G.dayOverride ?? G.time / DAY);
  if (room) room.update(now / 1000, stage.night);
  terrain.flush();
  if (terrain.colorsDirty && now - (terrain.colorStamp || 0) > 350) terrain.updateColors();
  for (const s of G.systems) s.render && s.render(real, now / 1000);
  stage.keyPan(real);
  stage.shake *= Math.pow(0.02, real);
  stage.flash *= Math.pow(0.001, real);
  stage.applyCamera(now / 1000);
  if (post) post.render(); else stage.renderer.render(stage.scene, stage.camera);
}

G.ready = true;
requestAnimationFrame(frame);
