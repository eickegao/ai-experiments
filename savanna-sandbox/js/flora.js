// Trees, bushes, rocks and grass tufts. Trees can burn or be felled for wood (a stump
// stays and a new tree grows back); bushes carry berries that people pick.
// Only what is near the camera is handed to the GPU: the lists hold the whole map,
// the instanced meshes hold the part in view and are refilled when the view moves.
import * as THREE from '../vendor/three/three.module.js';
import { toyMaterial, makeNoise, clamp, Builder } from './util.js';
import { N, KOPJES } from './terrain.js';
import { acaciaGeo, baobabGeo, burntTreeGeo, bushGeo, berriesGeo, rockGeo, tuftGeo } from './models.js';

const M = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), p = new THREE.Vector3(), s = new THREE.Vector3();
const col = new THREE.Color(), DRY = new THREE.Color('#e9c766'), GREEN = new THREE.Color('#8fb04a');

export function createFlora(G) {
  const { stage, terrain: T, rng, villages } = G;
  const scene = stage.scene;
  const mat = toyMaterial();
  const A = G.assets;
  const inst = (geo, max, shadow = true, material = mat) => {
    const m = new THREE.InstancedMesh(geo, material, max);
    m.castShadow = shadow; m.receiveShadow = true; m.frustumCulled = false; m.count = 0;
    scene.add(m);
    return m;
  };
  const gen = (name, make, max, shadow = true) => (A[name] ? inst(A[name].geo, max, shadow, A[name].mat) : inst(make(), max, shadow));
  const stumpGeo = () => new Builder().cyl(0.3, 0.38, 0.4, 0, 0.2, 0, '#8a6a48', 8).cyl(0.27, 0.27, 0.02, 0, 0.41, 0, '#d9c08a', 8).build();
  const meshes = {
    acacia: [0, 1, 2].map(v => gen(['acacia_a', 'acacia_b', 'acacia_a'][v], () => acaciaGeo(v), 900)),
    baobab: gen('baobab', baobabGeo, 160),
    burnt: inst(burntTreeGeo(), 700),
    stump: gen('stump', stumpGeo, 500),
    bush: gen('bush', bushGeo, 1200),
    berries: inst(berriesGeo(), 1200, false),
    rock: [0, 1, 2].map(v => gen(['rock_a', 'rock_b', 'rock_a'][v], () => rockGeo(v), 700)),
    tuft: inst(tuftGeo(), 14000, false, new THREE.MeshStandardMaterial({ roughness: 1, flatShading: true })),
  };
  meshes.tuft.setColorAt(0, col.set('#fff'));

  const F = { trees: [], bushes: [], rocks: [], tufts: [], dirty: true };
  const { fbm } = makeNoise(G.rng.int(1, 9999));
  const nearVillage = (x, z, r) => villages.some(v => Math.hypot(x - v.x, z - v.z) < r);
  const free = (x, z, vr = 30) => T.inside(x, z, 2.5) && T.depth(x, z) < -0.25 && !nearVillage(x, z, vr);

  // A coarse grid keeps "is anything close?" cheap while scattering thousands of things.
  const CELL = 8, GW = Math.ceil(N / CELL);
  const grid = Array.from({ length: GW * GW }, () => []);
  const cellOf = (x, z) => clamp(Math.floor(z / CELL), 0, GW - 1) * GW + clamp(Math.floor(x / CELL), 0, GW - 1);
  const crowded = (x, z, r) => {
    const cx = Math.floor(x / CELL), cz = Math.floor(z / CELL);
    for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) {
      const gx = cx + dx, gz = cz + dz;
      if (gx < 0 || gz < 0 || gx >= GW || gz >= GW) continue;
      for (const o of grid[gz * GW + gx]) if ((o.x - x) ** 2 + (o.z - z) ** 2 < r * r) return true;
    }
    return false;
  };

  // ---- place things
  const area = (N / 256) ** 2;
  let tries = 0, nBaobab = 0;
  while (F.trees.length < 560 * area && tries++ < 400000) {
    const x = rng.range(3, N - 3), z = rng.range(3, N - 3);
    if (!free(x, z) || T.slope(x, z) > 0.5) continue;
    if (fbm(x * 0.06, z * 0.06, 2) < 0.42 && rng() < 0.8) continue;      // clumps, with open plains between
    if (crowded(x, z, 4.2)) continue;
    const baobab = nBaobab < 44 * area && rng() < 0.09;
    if (baobab) nBaobab++;
    const t = { kind: baobab ? 'baobab' : 'acacia', v: rng.int(0, 2), x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.85, 1.25), state: 'alive', burn: 0, grow: 1 };
    F.trees.push(t); grid[cellOf(x, z)].push(t);
  }
  tries = 0;
  while (F.bushes.length < 520 * area && tries++ < 300000) {
    // A good share of the bushes sits in a belt around the first villages so foragers have work nearby.
    let x, z;
    if (rng() < 0.3) {
      const v = rng.pick(villages), a = rng.range(0, 6.28), r = rng.range(28, 75);
      x = v.x + Math.cos(a) * r; z = v.z + Math.sin(a) * r;
    } else { x = rng.range(3, N - 3); z = rng.range(3, N - 3); }
    if (!free(x, z, 27) || crowded(x, z, 2.1)) continue;
    const b = { x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.8, 1.3), berries: rng() < 0.85, regrow: 0, taken: null, alive: true };
    F.bushes.push(b); grid[cellOf(x, z)].push(b);
  }
  for (const k of KOPJES) {
    for (let i = 0; i < 26; i++) {
      const a = rng.range(0, 6.28), r = rng.range(0, 10);
      const x = k.x + Math.cos(a) * r, z = k.z + Math.sin(a) * r;
      if (!T.inside(x, z, 2)) continue;
      F.rocks.push({ v: rng.int(0, 2), x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.9, 2.8) * (1 - r / 16) });
    }
  }
  for (let i = 0; i < 300 * area; i++) {
    const x = rng.range(3, N - 3), z = rng.range(3, N - 3);
    if (!free(x, z, 26) && T.depth(x, z) < 0.1) continue;
    F.rocks.push({ v: rng.int(0, 2), x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.35, 1.0) });
  }
  tries = 0;
  while (F.tufts.length < 15000 * area && tries++ < 500000) {
    const x = rng.range(1.5, N - 1.5), z = rng.range(1.5, N - 1.5);
    if (T.depth(x, z) > -0.12 || nearVillage(x, z, 10)) continue;
    if (T.grass[T.cell(x, z)] < rng.range(0.2, 0.6)) continue;
    F.tufts.push({ x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.7, 1.5), tint: rng.range(0.85, 1.1) });
  }
  // tufts sorted into the same coarse grid so the visible ones are found without scanning all
  const tuftGrid = Array.from({ length: GW * GW }, () => []);
  for (const t of F.tufts) tuftGrid[cellOf(t.x, t.z)].push(t);

  const setM = (mesh, i, x, y, z, yaw, sc, sy = sc) => {
    q.setFromEuler(e.set(0, yaw, 0));
    mesh.setMatrixAt(i, M.compose(p.set(x, y, z), q, s.set(sc, sy, sc)));
  };
  const done = (mesh, n) => { mesh.count = n; mesh.instanceMatrix.needsUpdate = true; };

  // ---- refill the meshes with what is in view
  const view = stage.view;
  let last = { x: -999, z: -999, r: 0 };
  const rebuild = () => {
    const r2 = view.r * view.r;
    const n = { a: [0, 0, 0], baobab: 0, burnt: 0, stump: 0, rock: [0, 0, 0] };
    for (const t of F.trees) {
      if (t.state === 'gone' || (t.x - view.x) ** 2 + (t.z - view.z) ** 2 > r2) continue;
      const y = T.height(t.x, t.z) - 0.1;
      if (t.state === 'burnt') { if (n.burnt < 700) setM(meshes.burnt, n.burnt++, t.x, y, t.z, t.yaw, t.sc * (t.kind === 'baobab' ? 1.25 : 1)); continue; }
      if (t.state === 'stump') { if (n.stump < 500) setM(meshes.stump, n.stump++, t.x, y + 0.05, t.z, t.yaw, 1.5 * t.sc); continue; }
      if (t.kind === 'baobab') { if (n.baobab < 160) setM(meshes.baobab, n.baobab++, t.x, y, t.z, t.yaw, t.sc * t.grow); }
      else if (n.a[t.v] < 900) setM(meshes.acacia[t.v], n.a[t.v]++, t.x, y, t.z, t.yaw + (t.shake ? Math.sin(t.shake * 40) * 0.05 : 0), t.sc * t.grow);
    }
    meshes.acacia.forEach((m, v) => done(m, n.a[v]));
    done(meshes.baobab, n.baobab); done(meshes.burnt, n.burnt); done(meshes.stump, n.stump);
    let nb = 0;
    for (const b of F.bushes) {
      if (!b.alive || nb >= 1200 || (b.x - view.x) ** 2 + (b.z - view.z) ** 2 > r2) continue;
      const y = T.height(b.x, b.z) - 0.05;
      setM(meshes.bush, nb, b.x, y, b.z, b.yaw, b.sc);
      if (b.berries && !A.bush) setM(meshes.berries, nb, b.x, y, b.z, b.yaw, b.sc); else meshes.berries.setMatrixAt(nb, M.makeScale(0, 0, 0));
      nb++;
    }
    done(meshes.bush, nb); done(meshes.berries, nb);
    for (const r of F.rocks) {
      if (n.rock[r.v] >= 700 || (r.x - view.x) ** 2 + (r.z - view.z) ** 2 > r2) continue;
      setM(meshes.rock[r.v], n.rock[r.v]++, r.x, T.height(r.x, r.z) - 0.12 * r.sc, r.z, r.yaw, r.sc);
    }
    meshes.rock.forEach((m, v) => done(m, n.rock[v]));
    last = { x: view.x, z: view.z, r: view.r };
    F.dirty = false;
  };
  const refreshTufts = () => {
    const R = Math.min(view.r, 170), r2 = R * R;
    const x0 = clamp(Math.floor((view.x - R) / CELL), 0, GW - 1), x1 = clamp(Math.floor((view.x + R) / CELL), 0, GW - 1);
    const z0 = clamp(Math.floor((view.z - R) / CELL), 0, GW - 1), z1 = clamp(Math.floor((view.z + R) / CELL), 0, GW - 1);
    let i = 0;
    for (let gz = z0; gz <= z1; gz++) for (let gx = x0; gx <= x1; gx++) {
      for (const t of tuftGrid[gz * GW + gx]) {
        if (i >= 14000) break;
        if ((t.x - view.x) ** 2 + (t.z - view.z) ** 2 > r2) continue;
        const c = T.cell(t.x, t.z), g = T.grass[c];
        if (T.burnt[c] > 0.25 || T.fire[c] > 0 || T.depth(t.x, t.z) > 0.02 || g < 0.12) continue;
        const k = clamp((g - 0.1) / 0.5, 0.25, 1.25);
        setM(meshes.tuft, i, t.x, T.height(t.x, t.z) - 0.04, t.z, t.yaw, t.sc * (0.7 + 0.3 * k), t.sc * k);
        col.copy(DRY).lerp(GREEN, clamp((g - 0.45) * 2.2, 0, 1)).multiplyScalar(t.tint);
        meshes.tuft.setColorAt(i, col);
        i++;
      }
    }
    done(meshes.tuft, i);
    meshes.tuft.instanceColor.needsUpdate = true;
  };

  F.placeBush = () => { F.dirty = true; };
  F.placeTree = () => { F.dirty = true; };

  // ---- behaviour
  let tuftTimer = 0, seenVersion = T.version, slow = 0;
  F.update = (dt) => {
    slow -= dt;
    if (slow > 0) return;
    const step = 0.5; slow = step;
    for (const b of F.bushes) {
      if (!b.alive) { b.regrow -= step; if (b.regrow <= 0 && T.burnt[T.cell(b.x, b.z)] < 0.2) { b.alive = true; b.berries = false; b.regrow = 30; F.dirty = true; } continue; }
      if (!b.berries) {
        b.regrow -= step * (0.4 + T.grass[T.cell(b.x, b.z)]);
        if (b.regrow <= 0) { b.berries = true; F.dirty = true; }
      }
      if (T.fire[T.cell(b.x, b.z)] > 0) { b.alive = false; b.berries = false; b.regrow = 120; b.taken = null; F.dirty = true; }
    }
    for (const t of F.trees) {
      if (t.state === 'alive') {
        if (T.fire[T.cell(t.x, t.z)] > 0) { t.state = 'burning'; t.burn = G.rng.range(5, 9); t.taken = null; }
        else if (t.grow < 1) { t.grow = Math.min(1, t.grow + step / 120); F.dirty = true; }
      } else if (t.state === 'burning') {
        t.burn -= step;
        if (t.burn <= 0) { t.state = 'burnt'; F.dirty = true; }
      } else if (t.state === 'stump') {
        t.regrow -= step;
        // nothing grows back on land a city has taken
        if (t.regrow <= 0 && T.burnt[T.cell(t.x, t.z)] < 0.2 && !villages.some(v => (v.era || 1) >= 4 && Math.hypot(t.x - v.x, t.z - v.z) < 45 + ((v.era || 1) - 3) * 25)) { t.state = 'alive'; t.grow = 0.25; F.dirty = true; }
        else if (t.regrow <= 0) t.regrow = 60;
      }
    }
  };
  F.render = (real) => {
    tuftTimer -= real;
    if (seenVersion !== T.version) { seenVersion = T.version; F.dirty = true; tuftTimer = 0; }
    const moved = Math.hypot(view.x - last.x, view.z - last.z) > 10 || Math.abs(view.r - last.r) > last.r * 0.08;
    if (F.dirty || moved) { rebuild(); if (moved) tuftTimer = 0; }
    if (tuftTimer <= 0) { tuftTimer = 0.6; refreshTufts(); }
  };

  // Things inside a blast radius (or under a new building) are removed.
  F.clear = (x, z, r) => {
    for (const t of F.trees) if (t.state !== 'gone' && Math.hypot(t.x - x, t.z - z) < r) { t.state = 'gone'; t.taken = null; }
    for (const b of F.bushes) if (b.alive && Math.hypot(b.x - x, b.z - z) < r) { b.alive = false; b.berries = false; b.regrow = 200; }
    F.rocks = F.rocks.filter(k => Math.hypot(k.x - x, k.z - z) >= r * 0.8);
    F.dirty = true;
  };

  // ---- wood
  F.nearestTree = (x, z, maxR, hx = x, hz = z) => {
    let best = null, bd = maxR * maxR * 2;
    for (const t of F.trees) {
      if (t.state !== 'alive' || t.taken || t.kind === 'baobab' || t.grow < 0.8) continue;
      const d = (t.x - x) ** 2 + (t.z - z) ** 2 + (t.x - hx) ** 2 + (t.z - hz) ** 2;
      if (d < bd) { bd = d; best = t; }
    }
    return best;
  };
  // A city clears the land around it for good: the trees nearest to (x, z) within R go.
  F.clearNear = (x, z, R, n) => {
    const hits = [];
    for (const t of F.trees) {
      if (t.state !== 'alive' && t.state !== 'stump') continue;
      const d = Math.hypot(t.x - x, t.z - z);
      if (d < R) hits.push([d, t]);
    }
    hits.sort((a, b) => a[0] - b[0]);
    let cut = 0;
    for (const [, t] of hits.slice(0, n)) { if (t.state === 'alive') cut++; t.state = 'gone'; t.taken = null; }
    if (hits.length) F.dirty = true;
    return cut;
  };
  F.fell = (t) => { t.state = 'stump'; t.regrow = G.rng.range(160, 260); t.taken = null; t.shake = 0; F.dirty = true; };
  F.count = () => F.trees.reduce((n, t) => n + (t.state === 'alive' ? 1 : 0), 0);

  return F;
}
