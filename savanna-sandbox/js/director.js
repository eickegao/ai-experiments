// ?demo=1 : a scripted show reel. Camera keyframes and god actions on a real-time
// timeline; the simulation itself keeps running by its own rules.
import { lerp, smooth } from './util.js';

export function createDirector(G) {
  const { stage } = G;
  const cam = stage.cam;
  const D = { t: 0, on: true, done: false, length: 50 };
  const A = G.villages[0], B = G.villages[1];

  // camera keyframes: t, tx, tz, dist, yaw, pitch (ty stays 0 unless given)
  const keys = [
    { t: 0, tx: 48, tz: 50, dist: 250, yaw: 0.45, pitch: 0.7 },
    { t: 4.5, tx: 48, tz: 48, dist: 200, yaw: 0.85, pitch: 0.6 },
    { t: 8, tx: A.x, tz: A.z, dist: 46, yaw: 1.0, pitch: 0.5 },
    { t: 15.5, tx: A.x, tz: A.z, dist: 60, yaw: 1.85, pitch: 0.56 },
    { t: 18.5, tx: A.x, tz: A.z, dist: 50, yaw: 2.0, pitch: 0.5 },
    { t: 20.5, tx: 63, tz: 40, dist: 92, yaw: 0.6, pitch: 0.55 },
    { t: 28.5, tx: 63, tz: 40, dist: 80, yaw: 0.78, pitch: 0.52 },
    { t: 30.5, tx: 34, tz: 33, dist: 44, yaw: 0.95, pitch: 0.45 },
    { t: 32.5, tx: 34, tz: 33, dist: 44, yaw: 1.05, pitch: 0.45 },
    { t: 35.5, tx: 47, tz: 45, dist: 62, yaw: 0.5, pitch: 0.48, battle: true },
    { t: 41, tx: 47, tz: 45, dist: 52, yaw: 0.7, pitch: 0.46, battle: true },
    { t: 42.5, tx: 47, tz: 45, dist: 96, yaw: 0.8, pitch: 0.56, battle: true },
    { t: 45, tx: 47, tz: 45, dist: 96, yaw: 0.86, pitch: 0.56, battle: true },
    { t: 50, tx: 48, tz: 48, dist: 240, yaw: 1.25, pitch: 0.62 },
  ];
  const battle = { x: 47, z: 45 };
  const battleCentre = () => {
    const w = G.tribes.people.filter(p => p.role === 'warrior');
    if (w.length) { battle.x = w.reduce((s, p) => s + p.x, 0) / w.length; battle.z = w.reduce((s, p) => s + p.z, 0) / w.length; }
    return battle;
  };

  const acts = [
    [0, () => { G.dayOverride = 0.4; G.setSpeed(2); }],
    [8, () => G.setSpeed(60)],
    [9, () => G.setSpeed(130)],
    [15, () => G.setSpeed(30)],
    [15.5, () => G.setSpeed(2)],
    [21.5, () => { G.power('lightning', 66, 45); }],
    [22.1, () => { G.power('lightning', 59, 33); G.setSpeed(3); }],
    [26.5, () => G.power('rain', 64, 39)],
    [29.5, () => { G.power('war'); G.setSpeed(3); }],
    [36.5, () => G.setSpeed(1.5)],
    [41, () => { const c = battleCentre(); G.power('meteor', c.x, c.z); G.setSpeed(1); }],
    [45, () => G.setSpeed(2)],
  ];
  let next = 0;

  D.render = (real) => {
    if (!D.on || D.done) return;
    D.t += real;
    while (next < acts.length && acts[next][0] <= D.t) acts[next++][1]();
    if (D.t > 34 && D.t < 41) battleCentre();
    // dusk falls over the last few seconds
    if (D.t > 44) G.dayOverride = lerp(0.62, 0.86, smooth(44, 49.5, D.t));
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
