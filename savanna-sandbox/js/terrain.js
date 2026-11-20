// The slab of savanna: heightmap, grass / burn fields, water, earth sides and the wooden tray.
import * as THREE from '../vendor/three/three.module.js';
import { clamp, lerp, smooth, makeNoise } from './util.js';

export const N = 256;         // slab is N x N world units
export const GRID = N + 1;    // vertices per side
export const BASE_Y = -5;

export const K = N / 96;      // the first version was 96 wide; layout numbers are scaled from it
const RIVER = [[63, -2], [61, 9], [56, 18], [58, 27], [51, 35], [47, 48], [43, 57], [44, 66], [36, 74], [31, 84], [27, 98]].map(([x, z]) => [x * K, z * K]);
export const LAKE = { x: 47 * K, z: 48 * K, r: 17 };
export const PONDS = [{ x: 79 * K, z: 33 * K, r: 6.5 }, { x: 17 * K, z: 50 * K, r: 5.5 }, { x: 70 * K, z: 90 * K, r: 5 }, { x: 30 * K, z: 8 * K, r: 5 }];
export const KOPJES = [{ x: 81, z: 15, s: 5.5 }, { x: 13, z: 68, s: 4.6 }, { x: 60, z: 87, s: 4.2 }, { x: 40, z: 22, s: 3.4 }, { x: 88, z: 52, s: 4.8 }, { x: 8, z: 12, s: 3.2 }, { x: 66, z: 62, s: 3.0 }].map(k => ({ x: k.x * K, z: k.z * K, s: k.s }));

function distToRiver(x, z) {
  let best = 1e9;
  for (let i = 0; i < RIVER.length - 1; i++) {
    const [ax, az] = RIVER[i], [bx, bz] = RIVER[i + 1];
    const dx = bx - ax, dz = bz - az;
    const t = clamp(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0, 1);
    const px = ax + dx * t, pz = az + dz * t;
    best = Math.min(best, Math.hypot(x - px, z - pz));
  }
  return best;
}

const C = {
  soil: new THREE.Color('#b98852'),
  dry: new THREE.Color('#e0bb5c'),
  green: new THREE.Color('#84a843'),
  rock: new THREE.Color('#a39382'),
  sand: new THREE.Color('#d8c48c'),
  deep: new THREE.Color('#5f8f8c'),
  burnt: new THREE.Color('#2b2622'),
  ash: new THREE.Color('#6a625a'),
};

export function createTerrain(scene, seed, villages) {
  const { fbm, noise } = makeNoise(seed);
  const h = new Float32Array(GRID * GRID);
  const grass = new Float32Array(GRID * GRID);
  const burnt = new Float32Array(GRID * GRID);
  const fire = new Float32Array(GRID * GRID);     // seconds of burning left
  const jitter = new Float32Array(GRID * GRID);
  const T = { h, grass, burnt, fire, waterLevel: 0, colorsDirty: true };
  const idx = (ix, iz) => iz * GRID + ix;
  T.idx = idx;

  // ---- generate heights
  for (let iz = 0; iz < GRID; iz++) {
    for (let ix = 0; ix < GRID; ix++) {
      let y = 0.7 + fbm(ix * 0.035, iz * 0.035, 4) * 3.4 + fbm(ix * 0.12 + 40, iz * 0.12, 2) * 0.7;
      for (const k of KOPJES) {
        const d2 = (ix - k.x) ** 2 + (iz - k.z) ** 2;
        y += k.s * Math.exp(-d2 / 60) * (0.65 + 0.5 * noise(ix * 0.5, iz * 0.5));
      }
      for (const v of villages) {
        const d = Math.hypot(ix - v.x, iz - v.z);
        y = lerp(y, 1.5, 1 - smooth(24, 36, d));
      }
      const wob = (fbm(ix * 0.15 + 9, iz * 0.15 + 3, 2) - 0.5) * 3;
      const dr = distToRiver(ix, iz) + wob * 0.5;
      y = lerp(y, -0.58, 1 - smooth(2.2, 11, dr));
      const dl = Math.hypot(ix - LAKE.x, iz - LAKE.z) + wob * 1.6;
      y = lerp(y, -1.9, 1 - smooth(LAKE.r - 5, LAKE.r + 4, dl));
      let dp = 1e9;
      for (const pd of PONDS) {
        const d = Math.hypot(ix - pd.x, iz - pd.z) + wob * 0.8;
        y = lerp(y, -0.9, 1 - smooth(pd.r - 2.5, pd.r + 3, d));
        dp = Math.min(dp, d - pd.r * 0.5);
      }
      h[idx(ix, iz)] = y;
      jitter[idx(ix, iz)] = noise(ix * 1.7 + 5, iz * 1.7 + 11) - 0.5;
      const wet = 1 - smooth(2, 14, Math.min(dr, dl - LAKE.r * 0.6, dp));
      grass[idx(ix, iz)] = clamp(0.38 + fbm(ix * 0.07 + 70, iz * 0.07 + 20, 3) * 0.3 + wet * 0.4, 0, 1);
    }
  }

  // ---- queries
  T.height = (x, z) => {
    x = clamp(x, 0, N - 0.001); z = clamp(z, 0, N - 0.001);
    const ix = Math.floor(x), iz = Math.floor(z), fx = x - ix, fz = z - iz;
    const a = h[idx(ix, iz)], b = h[idx(ix + 1, iz)], c = h[idx(ix, iz + 1)], d = h[idx(ix + 1, iz + 1)];
    return lerp(lerp(a, b, fx), lerp(c, d, fx), fz);
  };
  T.cell = (x, z) => idx(clamp(Math.round(x), 0, N), clamp(Math.round(z), 0, N));
  T.depth = (x, z) => T.waterLevel - T.height(x, z);            // > 0 means under water
  T.isWater = (x, z) => T.depth(x, z) > 0.12;
  T.isDeep = (x, z) => T.depth(x, z) > 0.75;
  T.inside = (x, z, m = 1.5) => x > m && z > m && x < N - m && z < N - m;
  // Standing height for something on the ground (creatures wade, they do not sink).
  T.ground = (x, z) => Math.max(T.height(x, z), T.waterLevel - 0.42);
  T.slope = (x, z) => Math.hypot(T.height(x + 0.6, z) - T.height(x - 0.6, z), T.height(x, z + 0.6) - T.height(x, z - 0.6)) / 1.2;

  // ---- top surface
  const geo = new THREE.PlaneGeometry(N, N, N, N);
  geo.rotateX(-Math.PI / 2);
  geo.translate(N / 2, 0, N / 2);
  const pos = geo.attributes.position;
  const col = new THREE.Float32BufferAttribute(new Float32Array(GRID * GRID * 3), 3);
  geo.setAttribute('color', col);
  const writeHeights = () => {
    for (let i = 0; i < GRID * GRID; i++) pos.setY(i, h[i]);
    pos.needsUpdate = true;
    geo.computeVertexNormals();
    geo.computeBoundingSphere();
  };
  writeHeights();
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, metalness: 0 });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  scene.add(mesh);
  T.mesh = mesh;

  const tmp = new THREE.Color();
  T.updateColors = () => {
    const nor = geo.attributes.normal;
    const wl = T.waterLevel;
    for (let i = 0; i < GRID * GRID; i++) {
      const g = grass[i];
      if (g < 0.5) tmp.copy(C.soil).lerp(C.dry, g * 2);
      else tmp.copy(C.dry).lerp(C.green, (g - 0.5) * 2);
      const steep = 1 - nor.getY(i);
      if (steep > 0.1) tmp.lerp(C.rock, smooth(0.1, 0.34, steep));
      const d = wl - h[i];
      if (d > -0.35) tmp.lerp(C.sand, smooth(-0.35, 0.05, d));
      if (d > 0.1) tmp.lerp(C.deep, smooth(0.1, 1.6, d) * 0.85);
      const b = burnt[i];
      if (b > 0) tmp.lerp(b > 0.6 ? C.burnt : C.ash, Math.min(1, b * 1.3));
      if (fire[i] > 0) tmp.lerp(C.burnt, 0.8);
      const j = 1 + jitter[i] * 0.09;
      col.setXYZ(i, tmp.r * j, tmp.g * j, tmp.b * j);
    }
    col.needsUpdate = true;
    T.colorsDirty = false;
  };
  T.updateColors();

  // ---- earth sides with strata
  const bands = [[0.5, '#4d3a2b'], [1.9, '#b57a42'], [1.5, '#9c5c39'], [99, '#7b4c35']];
  const sidePos = [], sideCol = [];
  const quad = (ax, az, bx, bz, y0a, y0b, y1a, y1b, c) => {
    sidePos.push(ax, y0a, az, bx, y0b, bz, bx, y1b, bz, ax, y0a, az, bx, y1b, bz, ax, y1a, az);
    for (let k = 0; k < 6; k++) sideCol.push(c.r, c.g, c.b);
  };
  const edge = (pts) => {
    for (let i = 0; i < pts.length - 1; i++) {
      const [ax, az] = pts[i], [bx, bz] = pts[i + 1];
      let ta = h[idx(ax, az)], tb = h[idx(bx, bz)];
      for (const [t, hex] of bands) {
        const na = Math.max(BASE_Y, t > 50 ? BASE_Y : ta - t), nb = Math.max(BASE_Y, t > 50 ? BASE_Y : tb - t);
        quad(ax, az, bx, bz, ta, tb, na, nb, new THREE.Color(hex));
        ta = na; tb = nb;
      }
    }
  };
  const line = (f) => Array.from({ length: GRID }, (_, i) => f(i));
  edge(line(i => [i, N]));           // south face (towards +z)
  edge(line(i => [N, N - i]));       // east
  edge(line(i => [N - i, 0]));       // north
  edge(line(i => [0, i]));           // west
  const sideGeo = new THREE.BufferGeometry();
  sideGeo.setAttribute('position', new THREE.Float32BufferAttribute(sidePos, 3));
  sideGeo.setAttribute('color', new THREE.Float32BufferAttribute(sideCol, 3));
  sideGeo.computeVertexNormals();
  const sides = new THREE.Mesh(sideGeo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, side: THREE.DoubleSide }));
  sides.receiveShadow = true;
  scene.add(sides);

  // ---- wooden tray under the slab
  const tray = new THREE.Group();
  const wood = new THREE.MeshStandardMaterial({ color: '#c79c6b', roughness: 0.7 });
  const woodDark = new THREE.MeshStandardMaterial({ color: '#a97c50', roughness: 0.7 });
  const plate = new THREE.Mesh(new THREE.BoxGeometry(N + 10, 1.6, N + 10), wood);
  plate.position.set(N / 2, BASE_Y - 0.8, N / 2);
  const foot = new THREE.Mesh(new THREE.BoxGeometry(N + 4, 1.2, N + 4), woodDark);
  foot.position.set(N / 2, BASE_Y - 2.2, N / 2);
  plate.castShadow = plate.receiveShadow = true;
  tray.add(plate, foot);
  scene.add(tray);
  T.tray = tray;

  // ---- water: one sheet plus side curtains where the slab is cut through water
  const waterMat = new THREE.MeshStandardMaterial({
    color: '#3aa3c2', transparent: true, opacity: 0.74, roughness: 0.08, metalness: 0.1, depthWrite: false, side: THREE.DoubleSide,
  });
  const water = new THREE.Mesh(new THREE.PlaneGeometry(N, N, 1, 1).rotateX(-Math.PI / 2), waterMat);
  water.position.set(N / 2, 0, N / 2);
  water.receiveShadow = true;
  water.renderOrder = 2;
  scene.add(water);
  const curtain = new THREE.Mesh(new THREE.BufferGeometry(), waterMat);
  curtain.renderOrder = 2;
  scene.add(curtain);
  const rebuildCurtain = () => {
    const p = [], wl = T.waterLevel;
    const run = (pts) => {
      for (let i = 0; i < pts.length - 1; i++) {
        const [ax, az] = pts[i], [bx, bz] = pts[i + 1];
        const ya = Math.min(wl, h[idx(ax, az)]), yb = Math.min(wl, h[idx(bx, bz)]);
        if (ya >= wl && yb >= wl) continue;
        p.push(ax, wl, az, bx, wl, bz, bx, yb, bz, ax, wl, az, bx, yb, bz, ax, ya, az);
      }
    };
    run(line(i => [i, N])); run(line(i => [N, N - i])); run(line(i => [N - i, 0])); run(line(i => [0, i]));
    curtain.geometry.dispose();
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(p, 3));
    g.computeVertexNormals();
    curtain.geometry = g;
  };
  T.setWaterLevel = (y) => {
    if (Math.abs(y - T.waterLevel) < 0.002 && curtain.geometry.attributes.position) return;
    T.waterLevel = y;
    water.position.y = y;
    rebuildCurtain();
    T.colorsDirty = true;
  };
  T.setWaterLevel(0);
  T.water = water;

  // ---- sculpting. fn(dist, oldHeight, weight) -> newHeight; weight fades to 0 near the slab edge.
  T.deform = (cx, cz, r, fn) => {
    const x0 = Math.max(0, Math.floor(cx - r)), x1 = Math.min(N, Math.ceil(cx + r));
    const z0 = Math.max(0, Math.floor(cz - r)), z1 = Math.min(N, Math.ceil(cz + r));
    for (let iz = z0; iz <= z1; iz++) {
      for (let ix = x0; ix <= x1; ix++) {
        const d = Math.hypot(ix - cx, iz - cz);
        if (d > r) continue;
        const edgeW = smooth(0, 4, Math.min(ix, iz, N - ix, N - iz));
        if (edgeW <= 0) continue;
        const i = idx(ix, iz);
        h[i] = clamp(lerp(h[i], fn(d, h[i]), edgeW), BASE_Y + 1.5, 14);
      }
    }
    writeHeights();
    T.colorsDirty = true;
    T.version++;
  };
  T.version = 0;

  // Nearest shoreline point to (x,z), searched on a coarse ring pattern.
  T.findShore = (x, z, maxR = 130) => {
    for (let r = 1; r < maxR; r += 1.5) {
      const steps = Math.max(8, Math.floor(r * 3));
      const off = (x * 7 + z * 13) % 6.28;
      for (let k = 0; k < steps; k++) {
        const a = off + (k / steps) * Math.PI * 2;
        const px = x + Math.cos(a) * r, pz = z + Math.sin(a) * r;
        if (!T.inside(px, pz, 2)) continue;
        const d = T.depth(px, pz);
        if (d > 0.05 && d < 0.45) return { x: px, z: pz };
      }
    }
    return null;
  };

  return T;
}
