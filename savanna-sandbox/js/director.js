// ?demo=1 : a scripted show reel of the whole arc, from a campfire to a skyline.
// Camera keyframes and god actions sit on a real-time timeline; the simulation keeps
// running by its own rules, only its speed is driven (fast between the scenes).
import { lerp, smooth } from './util.js';

export function createDirector(G) {
  const { stage } = G;
  const cam = stage.cam;
  const D = { t: 0, on: true, done: false, length: 60 };
  const A = G.tribes.tribes[0];
  const gx = Math.cos(A.gate), gz = Math.sin(A.gate);
  const town = { x: A.x, z: A.z };
  const gate = { x: A.x + gx * 27, z: A.z + gz * 27 };
  const gateYaw = Math.atan2(gx, gz);                     // camera stands outside, looking in through the gate
  const rally = { x: A.rally.x, z: A.rally.z };
  const battle = { x: A.x + gx * 80, z: A.z + gz * 80 };
  const fire = { x: A.x - gz * 85, z: A.z + gx * 85 };

  // A stand of trees to set alight: the living tree nearest to a point off to the side of the town.
  const findFire = () => {
    const t = G.flora.nearestTree(fire.x, fire.z, 90);
    if (t) { fire.x = t.x; fire.z = t.z; }
  };
  // Where the fighting is: the people actually trading blows; before the lines meet,
  // the red town's own war band (bands from other settlements are still on the road).
  const battleCentre = () => {
    let w = G.tribes.people.filter(p => p.state === 'fight' && p.role === 'warrior');
    if (w.length < 6) w = G.tribes.people.filter(p => p.role === 'warrior' && p.tribe === A);
    if (!w.length) return;
    // There can be several clashes at once (every settlement sends a band). Follow one:
    // the knot of fighters around whoever is closest to the red town.
    let seed = w[0], bd = 1e12;
    for (const p of w) { const d = (p.x - A.x) ** 2 + (p.z - A.z) ** 2; if (d < bd) { bd = d; seed = p; } }
    if (D.seed && D.seed.alive && w.includes(D.seed)) seed = D.seed; else D.seed = seed;
    const knot = w.filter(p => Math.hypot(p.x - seed.x, p.z - seed.z) < 16);
    const x = knot.reduce((s, p) => s + p.x, 0) / knot.length, z = knot.reduce((s, p) => s + p.z, 0) / knot.length;
    // ease towards it so the camera does not jump when the first blows land
    battle.x += (x - battle.x) * 0.08; battle.z += (z - battle.z) * 0.08;
  };

  // tuned on a dry run of the recording: how fast to march and when the lines meet
  D.warSpeed = 6; D.fightAt = 34.6;

  // camera keyframes: time, target, distance, yaw, pitch
  const keys = [
    { t: 0, at: town, dist: 34, yaw: 0.3, pitch: 0.4 },
    { t: 5, at: town, dist: 44, yaw: 0.55, pitch: 0.48 },
    { t: 8, at: town, dist: 60, yaw: 0.8, pitch: 0.55 },
    { t: 10.5, at: town, dist: 62, yaw: 0.95, pitch: 0.55 },
    { t: 14.5, at: town, dist: 96, yaw: 1.3, pitch: 0.62 },
    { t: 15.6, at: gate, dist: 44, yaw: gateYaw - 0.25, pitch: 0.42 },
    { t: 17.2, at: gate, dist: 44, yaw: gateYaw + 0.1, pitch: 0.42 },
    { t: 20.2, at: town, dist: 100, yaw: 1.8, pitch: 0.62 },
    { t: 22.5, at: town, dist: 82, yaw: 2.0, pitch: 0.5 },
    { t: 23.6, at: fire, dist: 120, yaw: 0.6, pitch: 0.62 },
    { t: 29.3, at: fire, dist: 100, yaw: 0.85, pitch: 0.56 },
    { t: 30.6, at: rally, dist: 58, yaw: gateYaw + 0.5, pitch: 0.42 },
    { t: 32.6, at: rally, dist: 58, yaw: gateYaw + 0.65, pitch: 0.42 },
    { t: 34.6, at: battle, dist: 84, yaw: 0.5, pitch: 0.62 },
    { t: 39.8, at: battle, dist: 56, yaw: 0.75, pitch: 0.5 },
    { t: 41.2, at: battle, dist: 150, yaw: 0.85, pitch: 0.66 },
    { t: 44.5, at: battle, dist: 150, yaw: 0.9, pitch: 0.66 },
    { t: 46, at: town, dist: 125, yaw: 2.3, pitch: 0.62 },
    { t: 52.3, at: town, dist: 130, yaw: 3.0, pitch: 0.56 },
    { t: 55, at: town, dist: 100, yaw: 3.2, pitch: 0.4 },
    { t: 60, at: town, dist: 228, yaw: 3.55, pitch: 0.72 },
  ];

  const acts = [
    [0, () => { G.dayOverride = 0.42; G.setSpeed(2); }],
    [5, () => G.setSpeed(70)],
    [8, () => G.setSpeed(3)],
    [10.5, () => G.setSpeed(110)],
    [14.5, () => G.setSpeed(3)],
    [17.2, () => G.setSpeed(120)],
    [20.2, () => G.setSpeed(3)],
    [22.5, () => { findFire(); G.setSpeed(2.5); }],
    [24.2, () => G.power('lightning', fire.x, fire.z)],
    [24.8, () => G.power('lightning', fire.x + 9, fire.z - 6)],
    [25.3, () => G.power('lightning', fire.x - 8, fire.z + 7)],
    [27.8, () => G.power('rain', fire.x, fire.z)],
    [29.6, () => { G.power('war'); G.setSpeed(D.warSpeed); }],
    [D.fightAt, () => G.setSpeed(1.5)],
    [D.fightAt + 5.2, () => { G.power('meteor', battle.x, battle.z); G.setSpeed(1); }],
    [44.5, () => G.setSpeed(150)],
    [52, () => G.setSpeed(20)],
    [52.6, () => G.setSpeed(2)],
  ].sort((a, b) => a[0] - b[0]);
  let next = 0;

  D.render = (real) => {
    if (!D.on || D.done) return;
    D.t += real;
    while (next < acts.length && acts[next][0] <= D.t) acts[next++][1]();
    if (D.t > 32.6 && D.t < D.fightAt + 5.2) battleCentre();
    let i = 0;
    while (i < keys.length - 2 && keys[i + 1].t <= D.t) i++;
    const a = keys[i], b = keys[i + 1];
    const f = smooth(a.t, b.t, D.t);
    cam.tx = lerp(a.at.x, b.at.x, f); cam.tz = lerp(a.at.z, b.at.z, f);
    cam.dist = Math.exp(lerp(Math.log(a.dist), Math.log(b.dist), f));
    cam.yaw = lerp(a.yaw, b.yaw, f); cam.pitch = lerp(a.pitch, b.pitch, f);
    cam.ty = 0;
    if (D.t >= D.length) { D.done = true; G.setSpeed(1); }
  };
  // for tuning: what is going on right now
  D.status = () => ({ t: +D.t.toFixed(1), day: +(G.time / G.DAY + 1).toFixed(1), speed: G.speed, era: A.era, pop: A.people.length,
    fights: G.tribes.people.filter(p => p.state === 'fight').length, inShot: G.tribes.people.filter(p => p.role === 'warrior' && Math.hypot(p.x - battle.x, p.z - battle.z) < 14).length, water: +G.terrain.depth(battle.x, battle.z).toFixed(2), war: G.tribes.war ? G.tribes.war.phase : null, animals: G.animals.all.length, trees: G.flora.count() });
  return D;
}
