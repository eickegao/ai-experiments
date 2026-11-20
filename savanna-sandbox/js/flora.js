// Trees, bushes, rocks and grass tufts. Trees can burn; bushes carry berries that people pick.
import * as THREE from '../vendor/three/three.module.js';
import { toyMaterial, makeNoise, clamp } from './util.js';
import { N, KOPJES } from './terrain.js';
import { acaciaGeo, baobabGeo, burntTreeGeo, bushGeo, berriesGeo, rockGeo, tuftGeo } from './models.js';

const M = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), p = new THREE.Vector3(), s = new THREE.Vector3();
const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);
const col = new THREE.Color(), DRY = new THREE.Color('#e9c766'), GREEN = new THREE.Color('#8fb04a');

export function createFlora(G) {
  const { stage, terrain: T, rng, villages } = G;
  const scene = stage.scene;
  const mat = toyMaterial();
  const inst = (geo, max, shadow = true, material = mat) => {
    const m = new THREE.InstancedMesh(geo, material, max);
    m.castShadow = shadow; m.receiveShadow = true; m.frustumCulled = false; m.count = 0;
    scene.add(m);
    return m;
  };
  const meshes = {
    acacia: [0, 1, 2].map(v => inst(acaciaGeo(v), 320)),
    baobab: inst(baobabGeo(), 60),
    burnt: inst(burntTreeGeo(), 800),
    bush: inst(bushGeo(), 640),
    berries: inst(berriesGeo(), 640, false),
    rock: [0, 1, 2].map(v => inst(rockGeo(v), 320)),
    tuft: inst(tuftGeo(), 16500, false, new THREE.MeshStandardMaterial({ roughness: 1, flatShading: true })),
  };

  const F = { trees: [], bushes: [], rocks: [], tufts: [] };
  const { fbm } = makeNoise(G.rng.int(1, 9999));
  const nearVillage = (x, z, r) => villages.some(v => Math.hypot(x - v.x, z - v.z) < r);
  const free = (x, z, vr = 30) => T.inside(x, z, 2.5) && T.depth(x, z) < -0.25 && !nearVillage(x, z, vr);

  const setM = (mesh, i, x, y, z, yaw, sc, sy = sc) => {
    q.setFromEuler(e.set(0, yaw, 0));
    mesh.setMatrixAt(i, M.compose(p.set(x, y, z), q, s.set(sc, sy, sc)));
    mesh.instanceMatrix.needsUpdate = true;
  };

  // ---- place things
  let tries = 0, nBaobab = 0;
  while (F.trees.length < 560 && tries++ < 60000) {
    const x = rng.range(3, N - 3), z = rng.range(3, N - 3);
    if (!free(x, z) || T.slope(x, z) > 0.5) continue;
    if (fbm(x * 0.06, z * 0.06, 2) < 0.42 && rng() < 0.8) continue;      // clumps, with open plains between
    if (F.trees.some(t => Math.hypot(t.x - x, t.z - z) < 4.2)) continue;
    const baobab = nBaobab < 44 && rng() < 0.09;
    if (baobab) nBaobab++;
    F.trees.push({ kind: baobab ? 'baobab' : 'acacia', v: rng.int(0, 2), x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.85, 1.25), state: 'alive', burn: 0 });
  }
  tries = 0;
  while (F.bushes.length < 560 && tries++ < 60000) {
    // Two thirds of the bushes sit in a belt around the villages so foragers have work nearby.
    let x, z;
    if (rng() < 0.66) {
      const v = rng.pick(villages), a = rng.range(0, 6.28), r = rng.range(28, 70);
      x = v.x + Math.cos(a) * r; z = v.z + Math.sin(a) * r;
    } else { x = rng.range(3, N - 3); z = rng.range(3, N - 3); }
    if (!free(x, z, 27)) continue;
    if (F.bushes.some(t => Math.hypot(t.x - x, t.z - z) < 2.2) || F.trees.some(t => Math.hypot(t.x - x, t.z - z) < 1.8)) continue;
    F.bushes.push({ x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.8, 1.3), berries: rng() < 0.85, regrow: 0, taken: null, alive: true });
  }
  for (const k of KOPJES) {
    for (let i = 0; i < 26; i++) {
      const a = rng.range(0, 6.28), r = rng.range(0, 10);
      const x = k.x + Math.cos(a) * r, z = k.z + Math.sin(a) * r;
      if (!T.inside(x, z, 2)) continue;
      F.rocks.push({ v: rng.int(0, 2), x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.9, 2.8) * (1 - r / 16) });
    }
  }
  for (let i = 0; i < 300; i++) {
    const x = rng.range(3, N - 3), z = rng.range(3, N - 3);
    if (!free(x, z, 26) && T.depth(x, z) < 0.1) continue;
    F.rocks.push({ v: rng.int(0, 2), x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.35, 1.0) });
  }
  tries = 0;
  while (F.tufts.length < 16000 && tries++ < 120000) {
    const x = rng.range(1.5, N - 1.5), z = rng.range(1.5, N - 1.5);
    if (T.depth(x, z) > -0.12 || nearVillage(x, z, 10)) continue;
    if (T.grass[T.cell(x, z)] < rng.range(0.2, 0.6)) continue;
    F.tufts.push({ x, z, yaw: rng.range(0, 6.28), sc: rng.range(0.7, 1.5), tint: rng.range(0.85, 1.1) });
  }

  // ---- write instance matrices
  const counts = { a0: 0, a1: 0, a2: 0, baobab: 0, burnt: 0 };
  const placeTree = (t) => {
    const y = T.height(t.x, t.z) - 0.1;
    if (t.state === 'burnt') {
      if (t.bi === undefined) t.bi = counts.burnt++;
      setM(meshes.burnt, t.bi, t.x, y, t.z, t.yaw, t.sc * (t.kind === 'baobab' ? 1.25 : 1));
      meshes.burnt.count = counts.burnt;
    }
    const mesh = t.kind === 'baobab' ? meshes.baobab : meshes.acacia[t.v];
    const key = t.kind === 'baobab' ? 'baobab' : 'a' + t.v;
    if (t.i === undefined) t.i = counts[key]++;
    if (t.state === 'burnt' || t.state === 'gone') mesh.setMatrixAt(t.i, ZERO), mesh.instanceMatrix.needsUpdate = true;
    else setM(mesh, t.i, t.x, y, t.z, t.yaw, t.sc);
    mesh.count = counts[key];
  };
  const placeBush = (b, i) => {
    const y = T.height(b.x, b.z) - 0.05;
    if (!b.alive) { meshes.bush.setMatrixAt(i, ZERO); meshes.berries.setMatrixAt(i, ZERO); meshes.bush.instanceMatrix.needsUpdate = meshes.berries.instanceMatrix.needsUpdate = true; return; }
    setM(meshes.bush, i, b.x, y, b.z, b.yaw, b.sc);
    if (b.berries) setM(meshes.berries, i, b.x, y, b.z, b.yaw, b.sc);
    else { meshes.berries.setMatrixAt(i, ZERO); meshes.berries.instanceMatrix.needsUpdate = true; }
  };
  const rockCount = [0, 0, 0];
  const placeRock = (r) => {
    if (r.i === undefined) r.i = rockCount[r.v]++;
    setM(meshes.rock[r.v], r.i, r.x, T.height(r.x, r.z) - 0.12 * r.sc, r.z, r.yaw, r.sc);
    meshes.rock[r.v].count = rockCount[r.v];
  };
  const placeTuft = (t, i) => {
    const c = T.cell(t.x, t.z), g = T.grass[c];
    const dead = T.burnt[c] > 0.25 || T.fire[c] > 0 || T.depth(t.x, t.z) > 0.02 || g < 0.12;
    if (dead) { meshes.tuft.setMatrixAt(i, ZERO); return; }
    const k = clamp((g - 0.1) / 0.5, 0.25, 1.25);
    setM(meshes.tuft, i, t.x, T.height(t.x, t.z) - 0.04, t.z, t.yaw, t.sc * (0.7 + 0.3 * k), t.sc * k);
    col.copy(DRY).lerp(GREEN, clamp((g - 0.45) * 2.2, 0, 1)).multiplyScalar(t.tint);
    meshes.tuft.setColorAt(i, col);
  };

  F.placeAll = () => {
    F.trees.forEach(placeTree);
    F.bushes.forEach(placeBush);
    meshes.bush.count = meshes.berries.count = F.bushes.length;
    F.rocks.forEach(placeRock);
    F.refreshTufts();
  };
  F.refreshTufts = () => {
    F.tufts.forEach(placeTuft);
    meshes.tuft.count = F.tufts.length;
    meshes.tuft.instanceMatrix.needsUpdate = true;
    if (meshes.tuft.instanceColor) meshes.tuft.instanceColor.needsUpdate = true;
  };
  F.placeAll();
  F.placeBush = (b) => placeBush(b, F.bushes.indexOf(b));
  F.placeTree = placeTree;

  // ---- behaviour
  let tuftTimer = 0, seenVersion = T.version;
  F.update = (dt) => {
    for (const b of F.bushes) {
      if (!b.alive) { b.regrow -= dt; if (b.regrow <= 0 && T.burnt[T.cell(b.x, b.z)] < 0.2) { b.alive = true; b.berries = false; b.regrow = 30; F.placeBush(b); } continue; }
      if (!b.berries) {
        b.regrow -= dt * (0.4 + T.grass[T.cell(b.x, b.z)]);
        if (b.regrow <= 0) { b.berries = true; F.placeBush(b); }
      }
      if (T.fire[T.cell(b.x, b.z)] > 0) { b.alive = false; b.berries = false; b.regrow = 120; b.taken = null; F.placeBush(b); }
    }
    for (const t of F.trees) {
      if (t.state === 'alive' && T.fire[T.cell(t.x, t.z)] > 0) { t.state = 'burning'; t.burn = G.rng.range(5, 9); }
      else if (t.state === 'burning') {
        t.burn -= dt;
        if (t.burn <= 0) { t.state = 'burnt'; placeTree(t); }
      }
    }
    tuftTimer -= dt;
    if (tuftTimer <= 0) { tuftTimer = 0.5; F.refreshTufts(); }
    if (seenVersion !== T.version) { seenVersion = T.version; F.placeAll(); }
  };

  // Things inside a blast radius are destroyed.
  F.clear = (x, z, r) => {
    for (const t of F.trees) if (t.state !== 'gone' && Math.hypot(t.x - x, t.z - z) < r) { t.state = 'gone'; placeTree(t); if (t.bi !== undefined) meshes.burnt.setMatrixAt(t.bi, ZERO); }
    for (const b of F.bushes) if (b.alive && Math.hypot(b.x - x, b.z - z) < r) { b.alive = false; b.berries = false; b.regrow = 200; F.placeBush(b); }
    meshes.burnt.instanceMatrix.needsUpdate = true;
  };

  return F;
}
