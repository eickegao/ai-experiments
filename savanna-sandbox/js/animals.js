// Wildlife: grazing herds, elephants, giraffes, a lion pride that hunts, and birds.
import * as THREE from '../vendor/three/three.module.js';
import { clamp, toyMaterial } from './util.js';
import { N, KOPJES } from './terrain.js';
import { CreatureKind } from './creatures.js';
import { moveToward, settle } from './agents.js';
import * as MD from './models.js';

export const SPEC = {
  zebra:      { walk: 1.25, run: 5.0, hp: 2, meat: 10, size: 1.2, cap: 16, prey: true, stride: 4.2, color: '#f1eee4' },
  wildebeest: { walk: 1.15, run: 4.6, hp: 2, meat: 12, size: 1.2, cap: 20, prey: true, stride: 4.2, color: '#4a443f' },
  gazelle:    { walk: 1.45, run: 5.9, hp: 1, meat: 6,  size: 1.15, cap: 16, prey: true, stride: 5.2, color: '#d6a45c' },
  elephant:   { walk: 0.85, run: 2.4, hp: 40, meat: 0, size: 1.25, cap: 7, prey: false, stride: 2.2, color: '#8f8b8e' },
  giraffe:    { walk: 1.0, run: 3.8, hp: 8, meat: 0,  size: 1.15, cap: 7, prey: false, stride: 2.0, color: '#e6b95c' },
  lion:       { walk: 1.2, run: 6.4, hp: 6, meat: 0,  size: 1.25, cap: 6, prey: false, stride: 4.4, color: '#d7a24f' },
};

export function createAnimals(G) {
  const { stage, terrain: T, rng, villages } = G;
  const scene = stage.scene;
  const kinds = {
    zebra: new CreatureKind(scene, MD.zebraParts(), 90),
    wildebeest: new CreatureKind(scene, MD.wildebeestParts(), 110),
    gazelle: new CreatureKind(scene, MD.gazelleParts(), 90),
    elephant: new CreatureKind(scene, MD.elephantParts(), 24, { swing: 0.45 }),
    giraffe: new CreatureKind(scene, MD.giraffeParts(), 24, { swing: 0.5 }),
    lion: new CreatureKind(scene, MD.lionParts(), 24),
    bird: new CreatureKind(scene, MD.birdParts(), 80),
  };
  const carcassMesh = new THREE.InstancedMesh(MD.carcassGeo(), toyMaterial(), 60);
  carcassMesh.castShadow = true; carcassMesh.count = 0; carcassMesh.frustumCulled = false;
  scene.add(carcassMesh);

  const A = { all: [], herds: [], carcasses: [], kinds, flocks: [] };
  let nextId = 1;

  const nearVillage = (x, z, r) => villages.some(v => Math.hypot(x - v.x, z - v.z) < r);
  const walkable = (x, z) => T.inside(x, z, 3) && !T.isWater(x, z);

  const spawn = (kind, herd, x, z, young = false) => {
    const sp = SPEC[kind];
    const a = {
      id: nextId++, kind, herd, x, z, y: T.ground(x, z), yaw: rng.range(0, 6.28), size: sp.size,
      scale: sp.size * (young ? 0.55 : rng.range(0.92, 1.06)), gait: rng.range(0, 6), amp: 0, stride: sp.stride,
      hp: sp.hp, alive: true, fed: 0.8, wait: rng.range(0, 4), ox: 0, oz: 0, pitch: 0, roll: 0, bob: 0,
    };
    herd.members.push(a);
    A.all.push(a);
    kinds[kind].list.push(a);
    return a;
  };

  A.spawnHerd = (kind, x, z, n) => {
    const herd = { kind, members: [], x, z, mode: 'graze', timer: rng.range(4, 16), thirst: rng.int(0, 2), breed: rng.range(30, 60), home: { x, z } };
    A.herds.push(herd);
    for (let i = 0; i < n; i++) {
      const a = rng.range(0, 6.28), r = rng.range(0, 1.2 + Math.sqrt(n) * 1.3);
      let px = x + Math.cos(a) * r, pz = z + Math.sin(a) * r;
      if (!walkable(px, pz)) { px = x; pz = z; }
      spawn(kind, herd, px, pz);
    }
    return herd;
  };

  // ---- initial population
  const spot = (minVillage = 18) => {
    for (let i = 0; i < 200; i++) {
      const x = rng.range(8, N - 8), z = rng.range(8, N - 8);
      if (walkable(x, z) && !nearVillage(x, z, minVillage) && T.slope(x, z) < 0.5) return { x, z };
    }
    return { x: N / 2, z: 20 };
  };
  for (const [kind, herds, size] of [['zebra', 3, 9], ['wildebeest', 3, 12], ['gazelle', 3, 9], ['elephant', 1, 5], ['giraffe', 2, 3]]) {
    for (let i = 0; i < herds; i++) { const s = spot(); A.spawnHerd(kind, s.x, s.z, size); }
  }
  const den = KOPJES[2];
  const pride = A.spawnHerd('lion', den.x + 3, den.z - 4, 4);
  pride.mode = 'rest'; pride.timer = 25; pride.home = { x: den.x + 3, z: den.z - 4 };

  for (let f = 0; f < 3; f++) {
    const flock = { x: rng.range(20, N - 20), z: rng.range(20, N - 20), r: rng.range(7, 13), h: rng.range(11, 16), w: rng.range(0.25, 0.4) * (f % 2 ? 1 : -1), birds: [], tx: 0, tz: 0, target: null };
    flock.tx = flock.x; flock.tz = flock.z;
    for (let i = 0; i < 7; i++) {
      const b = { x: 0, y: 0, z: 0, yaw: 0, scale: 1.5, gait: 0, amp: 0, flap: rng.range(0, 6), ph: (i / 7) * 6.28 + rng.range(-0.3, 0.3), dr: rng.range(-2, 2), dh: rng.range(-1, 1) };
      flock.birds.push(b); kinds.bird.list.push(b);
    }
    A.flocks.push(flock);
  }

  // ---- helpers used by other systems
  A.remove = (a) => {
    a.alive = false;
    let i = A.all.indexOf(a); if (i >= 0) A.all.splice(i, 1);
    i = a.herd.members.indexOf(a); if (i >= 0) a.herd.members.splice(i, 1);
    const l = kinds[a.kind].list; i = l.indexOf(a); if (i >= 0) l.splice(i, 1);
  };
  // cause: 'hunt' leaves a carcass; anything else bursts the toy into cubes.
  A.kill = (a, cause = 'hunt') => {
    if (!a.alive) return null;
    A.remove(a);
    G.log('animal_death', { kind: a.kind, cause });
    if (cause === 'hunt' && SPEC[a.kind].meat) {
      const c = { x: a.x, z: a.z, yaw: a.yaw, meat: SPEC[a.kind].meat, timer: 70, taken: null, scale: a.scale };
      A.carcasses.push(c);
      G.fx.puff(a.x, a.y + 0.4, a.z, '#d9c7a0', 6);
      return c;
    }
    G.fx.burst(a.x, a.y + 0.6 * a.scale, a.z, SPEC[a.kind].color, a.kind === 'elephant' ? 26 : 12);
    return null;
  };
  A.scare = (x, z, r) => {
    for (const h of A.herds) {
      if (!h.members.length) continue;
      const c = centre(h);
      if (Math.hypot(c.x - x, c.z - z) < r + 6) flee(h, x, z, 6);
    }
  };
  A.nearestPrey = (x, z, maxR, pred = null) => {
    let best = null, bd = maxR * maxR;
    for (const a of A.all) {
      if (!SPEC[a.kind].prey || (pred && !pred(a))) continue;
      const d = (a.x - x) ** 2 + (a.z - z) ** 2;
      if (d < bd) { bd = d; best = a; }
    }
    return best;
  };

  const centre = (h) => {
    let x = 0, z = 0;
    for (const m of h.members) { x += m.x; z += m.z; }
    const n = h.members.length || 1;
    return { x: x / n, z: z / n };
  };
  const flee = (h, fx, fz, time) => {
    const c = centre(h);
    let dx = c.x - fx, dz = c.z - fz;
    const d = Math.hypot(dx, dz) || 1;
    dx /= d; dz /= d;
    // Run away, but bend the path back onto the slab.
    let tx = clamp(c.x + dx * 24, 6, N - 6), tz = clamp(c.z + dz * 24, 6, N - 6);
    if (T.isDeep(tx, tz)) { tx = clamp(c.x - dz * 20, 6, N - 6); tz = clamp(c.z + dx * 20, 6, N - 6); }
    h.mode = 'flee'; h.timer = time; h.x = tx; h.z = tz;
    for (const m of h.members) { m.ox = rng.range(-4, 4); m.oz = rng.range(-4, 4); }
  };

  const grazeScore = (x, z) => {
    if (!walkable(x, z) || nearVillage(x, z, 17)) return -9;
    const c = T.cell(x, z);
    if (T.fire[c] > 0) return -9;
    return T.grass[c] * 2 - T.burnt[c] * 2 + rng() * 0.6 - T.slope(x, z);
  };
  const pickGraze = (h) => {
    const c = centre(h);
    let best = null, bs = -5;
    for (let i = 0; i < 12; i++) {
      const a = rng.range(0, 6.28), r = rng.range(9, 28);
      const x = c.x + Math.cos(a) * r, z = c.z + Math.sin(a) * r;
      const s = grazeScore(x, z);
      if (s > bs) { bs = s; best = { x, z }; }
    }
    return best || h.home;
  };
  const reoffset = (h, m) => {
    const r = 1.2 + Math.sqrt(h.members.length) * (h.kind === 'elephant' ? 2.2 : 1.5);
    const a = rng.range(0, 6.28), rr = Math.sqrt(rng()) * r;
    m.ox = Math.cos(a) * rr; m.oz = Math.sin(a) * rr;
  };

  // ---- herd brains
  const updateHerd = (h, dt) => {
    const sp = SPEC[h.kind];
    if (!h.members.length) return;
    h.timer -= dt;
    const c = centre(h);

    if (h.kind === 'lion') { updatePride(h, c, dt); return; }

    // threats: lions on the hunt, hunters, fire
    h.look = (h.look || 0) - dt;
    if (h.look <= 0 && h.mode !== 'flee') {
      h.look = 0.5;
      if (sp.prey) {
        for (const l of kinds.lion.list) if (l.herd.mode === 'chase' && Math.hypot(l.x - c.x, l.z - c.z) < 13) { flee(h, l.x, l.z, 5); break; }
        if (G.tribes) for (const p of G.tribes.people) if (p.role === 'hunter' && p.state === 'hunt' && Math.hypot(p.x - c.x, p.z - c.z) < 7.5) { flee(h, p.x, p.z, 4); break; }
      }
      const ci = T.cell(c.x, c.z);
      if (T.fire[ci] > 0 || T.fire[T.cell(c.x + 3, c.z)] > 0 || T.fire[T.cell(c.x - 3, c.z)] > 0 || T.fire[T.cell(c.x, c.z + 3)] > 0 || T.fire[T.cell(c.x, c.z - 3)] > 0) flee(h, c.x + rng.range(-2, 2), c.z + rng.range(-2, 2), 6);
    }

    if (h.mode === 'graze') {
      if (h.timer <= 0) {
        h.thirst++;
        if (h.thirst >= 3) {
          const s = T.findShore(c.x, c.z);
          if (s) { h.mode = 'toWater'; h.x = s.x; h.z = s.z; h.timer = 60; h.members.forEach(m => reoffset(h, m)); return; }
        }
        const g = pickGraze(h);
        h.mode = 'move'; h.x = g.x; h.z = g.z; h.timer = 60;
        h.members.forEach(m => reoffset(h, m));
      }
    } else if (h.mode === 'move' || h.mode === 'toWater') {
      if (Math.hypot(c.x - h.x, c.z - h.z) < 4.5 || h.timer <= 0) {
        if (h.mode === 'toWater') { h.mode = 'drink'; h.timer = rng.range(7, 11); h.thirst = 0; }
        else { h.mode = 'graze'; h.timer = rng.range(14, 30); }
      }
    } else if (h.mode === 'drink') {
      if (h.timer <= 0) { const g = pickGraze(h); h.mode = 'move'; h.x = g.x; h.z = g.z; h.timer = 60; }
    } else if (h.mode === 'flee') {
      if (h.timer <= 0) { h.mode = 'graze'; h.timer = rng.range(6, 12); h.x = c.x; h.z = c.z; h.members.forEach(m => reoffset(h, m)); }
    }

    h.breed -= dt;
    if (h.breed <= 0) {
      h.breed = rng.range(38, 70);
      const fed = h.members.reduce((s, m) => s + m.fed, 0) / h.members.length;
      if (h.members.length < sp.cap && fed > 0.45 && h.mode !== 'flee') {
        const m = rng.pick(h.members);
        spawn(h.kind, h, m.x + rng.range(-0.8, 0.8), m.z + rng.range(-0.8, 0.8), true);
      }
    }
  };

  const updatePride = (h, c, dt) => {
    h.hunger = (h.hunger ?? 30) - dt;
    if (h.mode === 'rest') {
      if (h.hunger <= 0 && G.stage.night < 0.8) {
        const prey = A.nearestPrey(c.x, c.z, 55);
        if (prey) { h.mode = 'stalk'; h.prey = prey; h.timer = 45; G.log('lion_hunt', { x: prey.x, z: prey.z }); }
        else h.hunger = 15;
      }
    } else if (h.mode === 'stalk') {
      if (!h.prey.alive) { h.mode = 'return'; return; }
      if (Math.hypot(c.x - h.prey.x, c.z - h.prey.z) < 11) { h.mode = 'chase'; h.timer = 8; }
      else if (h.timer <= 0) { h.mode = 'return'; h.hunger = 20; }
    } else if (h.mode === 'chase') {
      if (!h.prey.alive) { h.mode = 'return'; h.hunger = 10; return; }
      for (const l of h.members) {
        if (Math.hypot(l.x - h.prey.x, l.z - h.prey.z) < 1.3) {
          const car = A.kill(h.prey, 'hunt');
          G.log('lion_kill', { x: l.x, z: l.z });
          h.mode = 'eat'; h.timer = 16; h.x = car.x; h.z = car.z; h.carcass = car; car.taken = 'lion'; h.hunger = rng.range(70, 110);
          return;
        }
      }
      if (h.timer <= 0) {
        // Missed. Pick another target close by once, then give up.
        h.mode = 'return'; h.hunger = rng.range(18, 30);
      }
    } else if (h.mode === 'eat') {
      if (h.timer <= 0) { if (h.carcass) h.carcass.timer = Math.min(h.carcass.timer, 12), h.carcass.taken = null; h.mode = 'return'; }
    } else if (h.mode === 'return') {
      h.x = h.home.x; h.z = h.home.z;
      if (Math.hypot(c.x - h.x, c.z - h.z) < 5) { h.mode = 'rest'; h.members.forEach(m => reoffset(h, m)); }
    } else if (h.mode === 'flee') {
      if (h.timer <= 0) h.mode = 'return';
    }
  };

  // ---- one animal
  const updateAnimal = (a, dt) => {
    const h = a.herd, sp = SPEC[a.kind];
    a.pitch += (0 - a.pitch) * Math.min(1, dt * 5);
    if (a.scale < a.size * 0.95) a.scale += dt * 0.006 * a.size;

    if (a.kind === 'lion') {
      if (h.mode === 'rest') {
        const d = moveToward(T, a, h.home.x + a.ox, h.home.z + a.oz, sp.walk, dt);
        if (d < 0.4) { a.amp = 0; a.bob += (-0.22 * a.scale - a.bob) * Math.min(1, dt * 3); }   // lie down
        return;
      }
      a.bob += (0 - a.bob) * Math.min(1, dt * 6);
      if (h.mode === 'stalk') moveToward(T, a, h.prey.x + a.ox * 1.5, h.prey.z + a.oz * 1.5, sp.walk * 1.5, dt);
      else if (h.mode === 'chase') moveToward(T, a, h.prey.x, h.prey.z, sp.run * (0.9 + (a.id % 4) * 0.05), dt);
      else if (h.mode === 'eat') { const d = moveToward(T, a, h.x + a.ox * 0.4, h.z + a.oz * 0.4, sp.walk * 1.4, dt); if (d < 0.6) a.pitch = 0.25 + Math.sin(G.time * 5 + a.id) * 0.08; }
      else moveToward(T, a, h.x + a.ox, h.z + a.oz, h.mode === 'flee' ? sp.run : sp.walk * 1.2, dt);
      return;
    }

    if (h.mode === 'flee') {
      moveToward(T, a, h.x + a.ox, h.z + a.oz, sp.run * (0.88 + (a.id % 5) * 0.03), dt);
      return;
    }
    if (h.mode === 'move' || h.mode === 'toWater') {
      moveToward(T, a, h.x + a.ox, h.z + a.oz, sp.walk * (1.2 + (a.id % 3) * 0.12), dt);
      return;
    }
    // graze / drink: mill around the herd centre
    const tx = h.x + a.ox, tz = h.z + a.oz;
    const d = Math.hypot(tx - a.x, tz - a.z);
    if (d > 0.5 && walkable(tx, tz) || (h.mode === 'drink' && d > 0.5)) {
      moveToward(T, a, tx, tz, sp.walk, dt);
    } else {
      settle(T, a, dt);
      a.wait -= dt;
      const c = T.cell(a.x, a.z);
      if (h.mode === 'drink') a.pitch = 0.3;
      else if (a.kind !== 'giraffe') {
        a.pitch = 0.22 + Math.sin(G.time * 3 + a.id) * 0.05;
        if (T.grass[c] > 0.12) { T.grass[c] -= dt * 0.0035; a.fed = Math.min(1, a.fed + dt * 0.03); T.colorsDirty = true; }
      } else a.fed = 1;
      if (a.wait <= 0) { a.wait = rng.range(3, 9); reoffset(h, a); }
    }
    a.fed -= dt * 0.004;
    if (a.fed <= 0 && sp.prey) A.kill(a, 'starve');
  };

  // ---- birds
  const updateFlock = (f, dt, i) => {
    const car = A.carcasses.find(c => !c.claimedBy || c.claimedBy === f);
    if (car && i === 0) { car.claimedBy = f; f.tx = car.x; f.tz = car.z; f.low = true; }
    else if (!car || i !== 0) {
      f.low = false;
      f.wander = (f.wander || 0) - dt;
      if (f.wander <= 0) { f.wander = rng.range(20, 40); f.tx = rng.range(15, N - 15); f.tz = rng.range(15, N - 15); }
    }
    f.x += clamp(f.tx - f.x, -2.2 * dt, 2.2 * dt);
    f.z += clamp(f.tz - f.z, -2.2 * dt, 2.2 * dt);
    const hgt = f.low ? 5.5 : f.h;
    f.ch = (f.ch ?? hgt) + clamp(hgt - (f.ch ?? hgt), -1.5 * dt, 1.5 * dt);
    for (const b of f.birds) {
      b.ph += f.w * dt * (f.low ? 1.6 : 1);
      const r = (f.low ? 4.5 : f.r) + b.dr;
      b.x = f.x + Math.cos(b.ph) * r; b.z = f.z + Math.sin(b.ph) * r;
      b.y = Math.max(T.height(b.x, b.z), 0) + f.ch + b.dh + Math.sin(b.ph * 3) * 0.4;
      b.yaw = -b.ph + (f.w > 0 ? 0 : Math.PI);
      b.roll = f.w > 0 ? -0.35 : 0.35;
      b.flap += dt * 7;
    }
  };

  A.update = (dt) => {
    for (const h of A.herds) updateHerd(h, dt);
    for (let i = A.all.length - 1; i >= 0; i--) updateAnimal(A.all[i], dt);
    A.flocks.forEach((f, i) => updateFlock(f, dt, i));
    for (let i = A.carcasses.length - 1; i >= 0; i--) {
      const c = A.carcasses[i];
      c.timer -= dt;
      if (c.timer <= 0 || c.gone) A.carcasses.splice(i, 1);
    }
  };

  const M = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), p = new THREE.Vector3(), s = new THREE.Vector3();
  A.render = () => {
    for (const k in kinds) kinds[k].draw();
    let n = 0;
    for (const c of A.carcasses) {
      if (c.carried) continue;
      const sc = c.scale * Math.min(1, c.timer / 8);
      q.setFromEuler(e.set(0, c.yaw, 0));
      carcassMesh.setMatrixAt(n++, M.compose(p.set(c.x, T.ground(c.x, c.z), c.z), q, s.set(sc, sc, sc)));
    }
    carcassMesh.count = n;
    carcassMesh.instanceMatrix.needsUpdate = true;
  };

  A.count = (kind) => kinds[kind].list.length;
  return A;
}
