// Weather and the god powers: grass growth, wildfire, rain, drought, water level,
// lightning, meteors, land sculpting.
import { clamp, lerp, smooth } from './util.js';
import { N, GRID } from './terrain.js';

export function createEnv(G) {
  const { stage, terrain: T, rng, fx } = G;
  const E = { burning: new Set(), rains: [], drought: 0, waterTarget: 0, wind: { x: 1, z: 0.25 }, storm: 0 };
  const wet = new Float32Array(GRID * GRID);     // how much water is nearby (recomputed now and then)
  let wetTimer = 0, growTimer = 0, spreadTimer = 0;

  const computeWet = () => {
    // Cheap distance-to-water: two blur passes over a water mask.
    const a = new Float32Array(GRID * GRID);
    for (let i = 0; i < GRID * GRID; i++) a[i] = T.waterLevel - T.h[i] > 0.05 ? 1 : 0;
    for (let pass = 0; pass < 3; pass++) {
      for (let z = 0; z < GRID; z++) for (let x = 0; x < GRID; x++) {
        let s = 0, n = 0;
        for (let d = -4; d <= 4; d += 2) { const xx = x + d; if (xx >= 0 && xx < GRID) { s += a[z * GRID + xx]; n++; } }
        wet[z * GRID + x] = s / n;
      }
      for (let z = 0; z < GRID; z++) for (let x = 0; x < GRID; x++) {
        let s = 0, n = 0;
        for (let d = -4; d <= 4; d += 2) { const zz = z + d; if (zz >= 0 && zz < GRID) { s += wet[zz * GRID + x]; n++; } }
        a[z * GRID + x] = s / n;
      }
    }
    for (let i = 0; i < GRID * GRID; i++) wet[i] = clamp(a[i] * 3.2, 0, 1);
  };
  computeWet();

  const raining = (x, z) => E.rains.some(r => Math.hypot(r.x - x, r.z - z) < r.r);

  // ---------------------------------------------------------------- fire
  E.ignite = (x, z, force = false) => {
    const c = T.cell(x, z);
    if (T.fire[c] > 0 || T.waterLevel - T.h[c] > 0) return false;
    if (!force && (T.grass[c] < 0.14 || T.burnt[c] > 0.3 || raining(x, z))) return false;
    T.fire[c] = 2.2 + T.grass[c] * 4.5;
    E.burning.add(c);
    T.colorsDirty = true;
    return true;
  };

  const updateFire = (dt) => {
    spreadTimer -= dt;
    const spread = spreadTimer <= 0;
    if (spread) spreadTimer = 0.3;
    const sum = fx.fireSum; sum.x = 0; sum.z = 0; sum.n = 0;
    for (const c of E.burning) {
      const x = c % GRID, z = (c - x) / GRID;
      T.fire[c] -= dt;
      sum.x += x; sum.z += z; sum.n++;
      if (T.fire[c] <= 0 || raining(x, z)) {
        T.fire[c] = 0; T.burnt[c] = 1; T.grass[c] = 0.03; E.burning.delete(c); T.colorsDirty = true;
        continue;
      }
      if (spread) {
        for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) {
          if (!dx && !dz) continue;
          const nx = x + dx, nz = z + dz;
          if (nx < 1 || nz < 1 || nx >= N || nz >= N) continue;
          const n = nz * GRID + nx;
          if (T.fire[n] > 0 || T.burnt[n] > 0.3) continue;
          const windBoost = 1 + 0.9 * (dx * E.wind.x + dz * E.wind.z);
          const dry = E.drought > 0 ? 1.5 : 1;
          if (rng() < 0.03 * (0.2 + T.grass[n]) * windBoost * dry) E.ignite(nx, nz);
        }
      }
    }
    if (sum.n && !E.fireLogged) { E.fireLogged = true; G.log('fire_start'); }
    if (!sum.n && E.fireLogged) { E.fireLogged = false; G.log('fire_end'); }
  };

  // flames are drawn per frame so they stay dense at any game speed
  const renderFire = () => {
    const n = E.burning.size;
    if (!n) return;
    const p = Math.min(1, 260 / n);
    for (const c of E.burning) {
      if (G.fx.R() > p) continue;
      const x = c % GRID, z = (c - x) / GRID, y = T.h[c];
      fx.flame(x, y + 0.2, z, 0.55);
      if (G.fx.R() < 0.2) fx.flame(x, y + 0.9, z, 0.8);
      if (G.fx.R() < 0.035) fx.smoke(x, y + 1.4, z, 0.8, 0.2);
      if (G.fx.R() < 0.03) fx.spark(x, y + 0.8, z, 2, '#ffb561', 0.6);
    }
  };

  // ---------------------------------------------------------------- grass and water
  const grow = (dt) => {
    const dry = E.drought > 0;
    for (let i = 0; i < GRID * GRID; i++) {
      if (T.fire[i] > 0) continue;
      if (T.burnt[i] > 0) T.burnt[i] = Math.max(0, T.burnt[i] - dt / 110);
      const target = dry ? 0.12 + wet[i] * 0.3 : 0.4 + wet[i] * 0.55;
      const g = T.grass[i];
      T.grass[i] = g + (target - g) * dt * (dry ? 0.02 : T.burnt[i] > 0.4 ? 0.002 : 0.008);
    }
    T.colorsDirty = true;
  };

  E.startRain = (x, z, r = 24, time = 14) => {
    const cloud = fx.addCloud(x - 2, z, 22 + rng.range(0, 2), r / 12, true);
    const cloud2 = fx.addCloud(x + r * 0.5, z + r * 0.35, 23.5, r / 15, true);
    const cloud3 = fx.addCloud(x - r * 0.35, z - r * 0.5, 24.5, r / 16, true);
    E.rains.push({ x, z, r, t: time, clouds: [cloud, cloud2, cloud3] });
    G.log('rain', { x, z });
  };

  const updateRain = (dt) => {
    for (let i = E.rains.length - 1; i >= 0; i--) {
      const r = E.rains[i];
      r.t -= dt;
      if (r.t <= 0) { r.clouds.forEach(c => c.dying = true); E.rains.splice(i, 1); continue; }
      const x0 = Math.max(0, Math.floor(r.x - r.r)), x1 = Math.min(N, Math.ceil(r.x + r.r));
      const z0 = Math.max(0, Math.floor(r.z - r.r)), z1 = Math.min(N, Math.ceil(r.z + r.r));
      for (let z = z0; z <= z1; z++) for (let x = x0; x <= x1; x++) {
        if (Math.hypot(x - r.x, z - r.z) > r.r) continue;
        const c = z * GRID + x;
        T.grass[c] = Math.min(1, T.grass[c] + dt * 0.07);
        T.burnt[c] = Math.max(0, T.burnt[c] - dt * 0.12);
      }
      T.colorsDirty = true;
    }
  };
  const renderRain = (real) => {
    for (const r of E.rains) {
      const n = Math.min(90, Math.ceil(r.r * r.r * 0.05 * real * 60));
      for (let k = 0; k < n; k++) {
        const a = G.fx.R() * 6.28, d = Math.sqrt(G.fx.R()) * r.r;
        const x = r.x + Math.cos(a) * d, z = r.z + Math.sin(a) * d;
        if (x < 0 || z < 0 || x > N || z > N) continue;
        fx.drop(x, z, 21 + G.fx.R() * 2);
      }
    }
  };

  E.startDrought = (time = 70) => { E.drought = time; E.waterTarget = -1.15; G.log('drought'); G.ui && G.ui.toast('drought'); };
  E.endDrought = () => { if (E.drought > 0) { E.drought = 0; E.waterTarget = 0; G.log('drought_end'); } };
  E.startStorm = (time = 16) => {
    E.storm = time; E.endDrought();
    E.waterTarget = 0.3;
    E.startRain(N / 2, N / 2, N * 0.75, time);
    E.stormClouds = [];
    for (let i = 0; i < 16; i++) E.stormClouds.push(fx.addCloud(rng.range(6, N - 6), rng.range(6, N - 6), rng.range(24, 28), rng.range(1.2, 1.9), true));
    G.log('storm'); G.ui && G.ui.toast('storm');
  };

  // ---------------------------------------------------------------- powers
  const killAt = (x, z, r, cause) => {
    for (const a of [...G.animals.all]) if (Math.hypot(a.x - x, a.z - z) < r) G.animals.kill(a, cause);
    G.tribes.killAt(x, z, r, cause);
  };

  E.powers = {
    rain: (x, z) => E.startRain(x, z),
    lightning: (x, z) => {
      // a thundercloud gathers over the strike and drifts apart again
      if (!raining(x, z)) { fx.addCloud(x - 2, z - 2, 27, 1.5, true).ttl = 4; fx.addCloud(x + 7, z + 4, 29, 1.1, true).ttl = 3.4; }
      fx.lightning(x, z);
      E.ignite(x, z, true);
      for (let i = 0; i < 4; i++) E.ignite(x + rng.range(-1.5, 1.5), z + rng.range(-1.5, 1.5), true);
      killAt(x, z, 1.8, 'lightning');
      G.animals.scare(x, z, 14);
      G.log('lightning', { x, z });
    },
    meteor: (x, z) => {
      G.log('meteor', { x, z });
      fx.meteor(x, z, () => {
        const R = 13;
        T.deform(x, z, R + 3, (d, h) => {
          const bowl = d < R ? -5 * (1 - (d / R) ** 2) : 0;
          const rim = 2 * Math.exp(-((d - R) ** 2) / 5);
          return h + bowl + rim;
        });
        G.flora.clear(x, z, R + 1.5);
        G.tribes.destroyAt(x, z, R + 1, 'meteor');
        killAt(x, z, R + 1.5, 'meteor');
        G.animals.scare(x, z, 60);
        for (let i = 0; i < 44; i++) { const a = rng.range(0, 6.28), d = R + rng.range(1.5, 7); E.ignite(x + Math.cos(a) * d, z + Math.sin(a) * d); }
        for (let i = 0; i < GRID * GRID; i++) {
          const cx = i % GRID, cz = (i - cx) / GRID, d = Math.hypot(cx - x, cz - z);
          if (d < R + 2) { T.grass[i] = 0.02; T.burnt[i] = Math.max(T.burnt[i], 1 - d / (R + 2) * 0.4); }
        }
        computeWet();
        G.log('meteor_impact', { x, z });
      });
    },
    raise: (x, z, dt = 1 / 30) => T.deform(x, z, 12, (d, h) => h + 8 * dt * smooth(12, 0, d)),
    lower: (x, z, dt = 1 / 30) => T.deform(x, z, 12, (d, h) => h - 8 * dt * smooth(12, 0, d)),
    drought: () => (E.drought > 0 ? E.endDrought() : E.startDrought()),
    storm: () => E.startStorm(),
    herd: (x, z) => {
      if (T.isWater(x, z)) return;
      const kind = rng.pick(['zebra', 'wildebeest', 'gazelle', 'gazelle', 'giraffe', 'elephant']);
      G.animals.spawnHerd(kind, x, z, kind === 'elephant' || kind === 'giraffe' ? 5 : 14);
      fx.spark(x, T.height(x, z) + 1, z, 30, '#fff3b0', 1.2);
      fx.ring(x, T.height(x, z), z, 6, '#fff3b0', 0.7);
      G.log('herd', { kind, x, z });
    },
    war: () => G.tribes.startWar(),
  };

  E.update = (dt) => {
    updateFire(dt);
    updateRain(dt);
    growTimer -= dt;
    if (growTimer <= 0) { growTimer = 1; grow(1); }
    if (E.drought > 0) { E.drought -= dt; if (E.drought <= 0) E.endDrought(); }
    if (E.storm > 0) {
      E.storm -= dt;
      if (rng() < dt * 0.8) E.powers.lightning(rng.range(8, N - 8), rng.range(8, N - 8));
      if (E.storm <= 0) { E.waterTarget = 0; (E.stormClouds || []).forEach(c => c.dying = true); }
    }
    if (Math.abs(T.waterLevel - E.waterTarget) > 0.004) {
      T.setWaterLevel(T.waterLevel + clamp(E.waterTarget - T.waterLevel, -0.035 * dt, 0.07 * dt));
      wetTimer -= dt;
      if (wetTimer <= 0) { wetTimer = 4; computeWet(); }
    }
  };
  E.render = (real) => { renderFire(); renderRain(real); };
  return E;
}
