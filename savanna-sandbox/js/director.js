// ?demo=1 : a scripted show reel. Camera keyframes and god actions on a real-time
// timeline; the simulation itself keeps running by its own rules.
import { lerp, smooth } from './util.js';
import { N } from './terrain.js';

export function createDirector(G) {
  const { stage } = G;
  const cam = stage.cam;
  const D = { t: 0, on: true, done: false, length: 54 };
  const A = G.villages[0], B = G.villages[1];

  // camera keyframes: t, tx, tz, dist, yaw, pitch (ty stays 0 unless given)
  const C = N / 2;
  const rally = G.tribes.tribes[0].rally;
  const keys = [
    { t: 0, tx: C, tz: C, dist: 660, yaw: 0.42, pitch: 0.52 },
    { t: 4.5, tx: 120, tz: 125, dist: 230, yaw: 0.52, pitch: 0.2 },
    { t: 8, tx: A.x, tz: A.z + 1, dist: 40, yaw: 0.2, pitch: 0.1 },
    { t: 15.5, tx: A.x, tz: A.z, dist: 86, yaw: 1.1, pitch: 0.34 },
    { t: 18.5, tx: A.x, tz: A.z, dist: 70, yaw: 1.32, pitch: 0.2 },
    { t: 20.5, tx: 168, tz: 107, dist: 170, yaw: 0.6, pitch: 0.34 },
    { t: 26.5, tx: 168, tz: 107, dist: 150, yaw: 0.78, pitch: 0.3 },
    { t: 28.5, tx: rally.x, tz: rally.z, dist: 62, yaw: 0.95, pitch: 0.15 },
    { t: 31, tx: rally.x, tz: rally.z, dist: 62, yaw: 1.05, pitch: 0.15 },
    { t: 35, tx: C, tz: C, dist: 84, yaw: 0.5, pitch: 0.5, battle: true },
    { t: 42.5, tx: C, tz: C, dist: 54, yaw: 0.75, pitch: 0.42, battle: true },
    { t: 44.5, tx: C, tz: C, dist: 190, yaw: 0.85, pitch: 0.4, battle: true },
    { t: 47.5, tx: C, tz: C, dist: 190, yaw: 0.92, pitch: 0.4, battle: true },
    { t: 54, tx: C, tz: C, dist: 640, yaw: 1.3, pitch: 0.5 },
  ];
  const battle = { x: C, z: C - 8 };
  const battleCentre = () => {
    const w = G.tribes.people.filter(p => p.role === 'warrior');
    if (w.length) { battle.x = w.reduce((s, p) => s + p.x, 0) / w.length; battle.z = w.reduce((s, p) => s + p.z, 0) / w.length; }
    return battle;
  };

  const acts = [
    [0, () => { G.dayOverride = 0.4; G.setSpeed(2); }],
    [8, () => G.setSpeed(60)],
    [9, () => G.setSpeed(150)],
    [15, () => G.setSpeed(30)],
    [15.5, () => G.setSpeed(2)],
    [21.5, () => { G.power('lightning', 176, 120); }],
    [22.1, () => { G.power('lightning', 157, 88); G.setSpeed(3); }],
    [22.6, () => { G.power('lightning', 190, 100); }],
    [25.5, () => G.power('rain', 172, 104)],
    [27, () => { G.power('war'); G.setSpeed(4); }],
    [36, () => G.setSpeed(1.5)],
    [43, () => { const c = battleCentre(); G.power('meteor', c.x, c.z); G.setSpeed(1); }],
    [47.5, () => G.setSpeed(2)],
  ];
  let next = 0;

  D.render = (real) => {
    if (!D.on || D.done) return;
    D.t += real;
    while (next < acts.length && acts[next][0] <= D.t) acts[next++][1]();
    if (D.t > 32 && D.t < 43) battleCentre();
    // dusk falls over the last few seconds
    if (D.t > 47.5) G.dayOverride = lerp(0.62, 0.86, smooth(47.5, 53.5, D.t));
    let i = 0;
    while (i < keys.length - 2 && keys[i + 1].t <= D.t) i++;
    const a = keys[i], b = keys[i + 1];
    const f = smooth(a.t, b.t, D.t);
    const ax = a.battle ? battle.x : a.tx, az = a.battle ? battle.z : a.tz, bx = b.battle ? battle.x : b.tx, bz = b.battle ? battle.z : b.tz;
    cam.tx = lerp(ax, bx, f); cam.tz = lerp(az, bz, f);
    cam.dist = Math.exp(lerp(Math.log(a.dist), Math.log(b.dist), f));
    cam.yaw = lerp(a.yaw, b.yaw, f); cam.pitch = lerp(a.pitch, b.pitch, f);
    cam.ty = 0;
    if (D.t >= D.length) { D.done = true; G.setSpeed(1); }
  };
  return D;
}
