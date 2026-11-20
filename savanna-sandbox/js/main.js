// Boot and main loop. The simulation runs in fixed 1/30 s steps so a run with the
// same seed and the same inputs always plays out the same way.
import * as THREE from '../vendor/three/three.module.js';
import { makeRng } from './util.js';
import { createStage } from './stage.js';
import { createTerrain, N, K } from './terrain.js';
import { createFlora } from './flora.js';
import { modelLineup } from './debug.js';
import { createFx } from './fx.js';
import { createAnimals } from './animals.js';
import { createTribes } from './tribes.js';
import { createEnv } from './env.js';
import { createUI } from './ui.js';
import { createPost } from './post.js';
import { createDirector } from './director.js';
import { createRoom } from './room.js';

const params = new URLSearchParams(location.search);
const seed = +(params.get('seed') || 7);
const STEP = 1 / 30;
const DAY = 120;              // seconds of simulation per day

const stage = createStage(document.getElementById('view'));
const rng = makeRng(seed);
const villages = [{ x: 21 * K, z: 25 * K }, { x: 76 * K, z: 73 * K }];
const terrain = createTerrain(stage.scene, seed, villages);
const room = params.get('room') === '0' ? null : createRoom(stage);
if (room) { stage.room = room; terrain.tray.visible = true; }

const G = window.G = {
  DAY,
  ready: false, stage, terrain, rng, villages,
  time: DAY * 0.36, speed: 1, paused: false, events: [], systems: [],
  setSpeed(s) { G.speed = s; },
  get day() { return Math.floor(G.time / DAY) + 1; },
  log(type, data = {}) { G.events.push({ t: +G.time.toFixed(2), type, ...data }); },
  stats() { return { time: G.time, day: G.day, fps: G.fps }; },
};

G.flora = createFlora(G);
G.fx = createFx(G);
if (params.get('debug') === 'models') modelLineup(G);
else {
  G.animals = createAnimals(G);
  G.tribes = createTribes(G);
  G.env = createEnv(G);
  const lang = params.get('lang') || ((navigator.language || 'en').startsWith('zh') ? 'zh' : 'en');
  document.documentElement.lang = lang;
  G.ui = createUI(G, lang);
  if (params.get('ui') === '0') document.body.classList.add('bare');
  G.systems.push(G.env, G.flora, G.animals, G.tribes, G.ui);
  G.power = (name, x, z) => G.env.powers[name](x, z);
  G.stats = () => ({ t: Math.round(G.time), day: G.day, fps: G.fps, animals: G.animals.all.length, tribes: G.tribes.info(), fire: G.env.burning.size, particles: G.fx.lit.items.length + G.fx.glow.items.length });
}
G.systems.push(G.fx);
const post = params.get('post') === '0' ? null : createPost(stage);
G.post = post;
if (post) stage.bgBoost = 1.9;
if (params.get('demo') === '1' && G.tribes) { G.director = createDirector(G); G.systems.push(G.director); }

function simulate(dt) {
  G.time += dt;
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
  if (terrain.colorsDirty) terrain.updateColors();
  for (const s of G.systems) s.render && s.render(real, now / 1000);
  stage.shake *= Math.pow(0.02, real);
  stage.flash *= Math.pow(0.001, real);
  stage.applyCamera(now / 1000);
  if (post) post.render(); else stage.renderer.render(stage.scene, stage.camera);
}

G.ready = true;
requestAnimationFrame(frame);
