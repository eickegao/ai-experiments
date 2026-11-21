// Visual effects: toy-cube particles, flames, rain, lightning, meteors and clouds.
import * as THREE from '../vendor/three/three.module.js';
import { Builder, clamp, lerp, makeRng } from './util.js';
import { N } from './terrain.js';

const M = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), p = new THREE.Vector3(), s = new THREE.Vector3();
const col = new THREE.Color(), c2 = new THREE.Color();
const FIRE = [new THREE.Color('#fff3b0'), new THREE.Color('#ffc247'), new THREE.Color('#ff7a1f'), new THREE.Color('#c43a12')];

class Pool {
  constructor(scene, max, material, shadow) {
    this.max = max; this.items = [];
    this.mesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), material, max);
    this.mesh.frustumCulled = false; this.mesh.count = 0; this.mesh.castShadow = shadow;
    this.mesh.setColorAt(0, col.set('#fff'));
    scene.add(this.mesh);
  }
  add(o) { if (this.items.length < this.max) this.items.push(o); return o; }
  step(dt, ground) {
    const it = this.items;
    for (let i = it.length - 1; i >= 0; i--) {
      const o = it[i];
      o.life -= dt;
      if (o.life <= 0) { it[i] = it[it.length - 1]; it.pop(); continue; }
      o.vy -= (o.grav || 0) * dt;
      if (o.drag) { const k = Math.exp(-o.drag * dt); o.vx *= k; o.vy *= k; o.vz *= k; }
      o.x += o.vx * dt; o.y += o.vy * dt; o.z += o.vz * dt;
      if (o.bounce) {
        const g = ground(o.x, o.z);
        if (o.y < g + o.size * 0.5) { o.y = g + o.size * 0.5; o.vy = Math.abs(o.vy) * 0.35; o.vx *= 0.6; o.vz *= 0.6; if (o.vy < 0.6) o.vy = 0; }
      }
    }
  }
  draw(time) {
    const it = this.items, n = it.length, mesh = this.mesh;
    for (let i = 0; i < n; i++) {
      const o = it[i];
      const t = 1 - o.life / o.max;
      let sc = o.size;
      if (o.grow) sc *= 1 + o.grow * t;
      if (o.shrink) sc *= Math.min(1, (o.life / o.max) * o.shrink);
      e.set(o.spin ? o.spin * time + i : 0, o.yaw || (o.spin ? o.spin * 0.7 * time + i * 2 : 0), o.tilt || 0);
      q.setFromEuler(e);
      mesh.setMatrixAt(i, M.compose(p.set(o.x, o.y, o.z), q, s.set(sc * (o.sx || 1), sc * (o.sy || 1), sc * (o.sx || 1))));
      if (o.fire) {
        const f = Math.min(2.999, Math.max(0, t || 0) * 3), k = Math.floor(f);
        col.copy(FIRE[k]).lerp(FIRE[k + 1], f - k);
      } else col.setRGB(o.r, o.g, o.b);
      mesh.setColorAt(i, col);
    }
    mesh.count = n;
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  }
}

const SMOOTH_BALL = new THREE.SphereGeometry(1, 14, 10);
function cloudGeo(rng) {
  const b = new Builder();
  const n = rng.int(4, 6);
  for (let i = 0; i < n; i++) {
    const r = rng.range(1.6, 2.8);
    b.add(SMOOTH_BALL, '#ffffff', (i - n / 2) * 2.1 + rng.range(-0.5, 0.5), rng.range(-0.2, 0.6), rng.range(-1.2, 1.2), 0, 0, 0, r, r * 0.6, r);
  }
  return b.build();
}

export function createFx(G) {
  const { stage, terrain: T, rng } = G;
  const scene = stage.scene;
  const lit = new Pool(scene, 5000, new THREE.MeshStandardMaterial({ roughness: 0.85, flatShading: true }), true);
  const glow = new Pool(scene, 8000, new THREE.MeshBasicMaterial({ toneMapped: false }), false);
  const R = makeRng(4242);            // cosmetic randomness only; never feeds the simulation
  const F = { lit, glow, clouds: [], meteors: [], rings: [], bolts: [], R };

  F.burst = (x, y, z, color, n = 12, power = 1) => {
    c2.set(color);
    for (let i = 0; i < n; i++) {
      const a = R() * 6.28, v = (1.5 + R() * 3.5) * power, k = 0.75 + R() * 0.4;
      lit.add({ x, y, z, vx: Math.cos(a) * v, vy: (3 + R() * 4.5) * power, vz: Math.sin(a) * v, grav: 16, bounce: true, life: 1.6 + R() * 1.6, max: 3.2,
        size: 0.14 + R() * 0.2, shrink: 3, spin: 3 + R() * 6, r: c2.r * k, g: c2.g * k, b: c2.b * k });
    }
  };
  F.puff = (x, y, z, color = '#e4d3ae', n = 8, spread = 1) => {
    c2.set(color);
    for (let i = 0; i < n; i++) {
      const a = R() * 6.28, v = (0.4 + R() * 1.4) * spread;
      lit.add({ x: x + Math.cos(a) * 0.3 * spread, y, z: z + Math.sin(a) * 0.3 * spread, vx: Math.cos(a) * v, vy: 0.5 + R() * 1.2, vz: Math.sin(a) * v, drag: 1.6,
        life: 0.8 + R() * 0.9, max: 1.7, size: 0.22 + R() * 0.3, grow: 1.4, shrink: 2.2, spin: 1 + R(), r: c2.r, g: c2.g, b: c2.b });
    }
  };
  F.smoke = (x, y, z, size = 0.5, dark = 0.3) => {
    const k = dark + R() * 0.12;
    lit.add({ x: x + (R() - 0.5) * 0.6, y, z: z + (R() - 0.5) * 0.6, vx: 0.7 + R() * 0.6, vy: 1.5 + R() * 1.1, vz: (R() - 0.5) * 0.5 + 0.2, drag: 0.2, life: 1.6 + R() * 1.6, max: 3.2,
      size: size * (0.35 + R() * 0.4), grow: 0.9, shrink: 1.25, spin: 0.8, r: k, g: k * 0.97, b: k * 0.94 });
  };
  F.flame = (x, y, z, size = 0.45) => {
    glow.add({ x: x + (R() - 0.5) * 0.7, y, z: z + (R() - 0.5) * 0.7, vx: (R() - 0.5) * 0.5, vy: 1.6 + R() * 2.4, vz: (R() - 0.5) * 0.5, life: 0.45 + R() * 0.55, max: 1.0,
      size: size * (0.6 + R() * 0.8), shrink: 2.2, spin: 4, fire: true, sy: 1.5 });
  };
  F.spark = (x, y, z, n = 6, color = '#ffd27a', power = 1) => {
    c2.set(color);
    for (let i = 0; i < n; i++) {
      const a = R() * 6.28, v = (2 + R() * 6) * power;
      glow.add({ x, y, z, vx: Math.cos(a) * v, vy: (2 + R() * 7) * power, vz: Math.sin(a) * v, grav: 14, life: 0.5 + R() * 0.8, max: 1.3, size: 0.1 + R() * 0.12, shrink: 2, spin: 8, r: c2.r, g: c2.g, b: c2.b });
    }
  };
  F.drop = (x, z, top) => {
    glow.add({ x, y: top, z, vx: 1.2, vy: -26, vz: 0, life: (top - Math.max(T.height(x, z), T.waterLevel)) / 26, max: 1, size: 0.07, sy: 9, tilt: 0.05, r: 0.72, g: 0.86, b: 1.0 });
  };

  // ---- lightning: a jagged bolt drawn with stretched glowing boxes
  F.lightning = (x, z) => {
    const gy = Math.max(T.height(x, z), T.waterLevel);
    let px = x + (R() - 0.5) * 6, py = 27, pz = z + (R() - 0.5) * 6;
    const segs = [];
    const steps = 11;
    for (let i = 1; i <= steps; i++) {
      const t = i / steps;
      const nx = lerp(px, x, 0.28) + (R() - 0.5) * 4.5 * (1 - t), nz = lerp(pz, z, 0.28) + (R() - 0.5) * 4.5 * (1 - t), ny = lerp(27, gy, t);
      segs.push([px, py, pz, i === steps ? x : nx, ny, i === steps ? z : nz]);
      if (i > 3 && R() < 0.3) segs.push([px, py, pz, px + (R() - 0.5) * 9, py - 4 - R() * 4, pz + (R() - 0.5) * 9, 0.5]);
      px = i === steps ? x : nx; py = ny; pz = i === steps ? z : nz;
    }
    F.bolts.push({ segs, life: 0.34, max: 0.34 });
    stage.flash = 1; stage.shake = Math.max(stage.shake, 0.5);
    F.spark(x, gy + 0.3, z, 26, '#fff6c9', 1.3);
    F.puff(x, gy + 0.3, z, '#3a332e', 10, 2);
  };
  const boltMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshBasicMaterial({ color: '#fffbe6', toneMapped: false }), 120);
  boltMesh.frustumCulled = false; boltMesh.count = 0;
  scene.add(boltMesh);
  const up = new THREE.Vector3(0, 1, 0), dir = new THREE.Vector3();

  // ---- meteor
  const ballGeo = new THREE.IcosahedronGeometry(1, 1);
  F.meteor = (x, z, onImpact, size = 1.7) => {
    const gy = Math.max(T.height(x, z), T.waterLevel);
    const mesh = new THREE.Mesh(ballGeo, new THREE.MeshBasicMaterial({ color: '#ffd9a0', toneMapped: false }));
    mesh.scale.setScalar(1.3 * size);
    scene.add(mesh);
    F.meteors.push({ mesh, x0: x - 110, y0: 140, z0: z - 60, x, y: gy, z, t: 0, dur: 1.9, onImpact, size });
  };
  const ringGeo = new THREE.RingGeometry(0.86, 1, 48).rotateX(-Math.PI / 2);
  F.ring = (x, y, z, r, color = '#fff1cf', dur = 0.9) => {
    const mesh = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, toneMapped: false, depthWrite: false, side: THREE.DoubleSide }));
    mesh.position.set(x, y + 0.4, z);
    scene.add(mesh);
    F.rings.push({ mesh, r, t: 0, dur });
  };

  // ---- clouds (white ones drift; grey ones are parked over rain)
  const cloudMat = new THREE.MeshStandardMaterial({ color: '#ffffff', roughness: 1, emissive: '#ffffff', emissiveIntensity: 0.32, transparent: true, opacity: 0.96 });
  const geos = [0, 1, 2].map(() => cloudGeo(rng));
  F.addCloud = (x, z, y, sc, rain = false) => {
    const mat = cloudMat.clone();
    if (rain) { mat.color.set('#3c424e'); mat.emissive.set('#000000'); mat.opacity = 0.9; }
    const mesh = new THREE.Mesh(geos[F.clouds.length % 3], mat);
    mesh.castShadow = true;
    mesh.position.set(x, y, z); mesh.scale.setScalar(0.001);
    scene.add(mesh);
    const c = { mesh, sc, rain, life: rain ? 1 : Infinity, grow: 0, vx: rain ? 0 : rng.range(0.5, 1.1) };
    F.clouds.push(c);
    return c;
  };

  // ---- fire light: one light that follows the blaze
  const fireLight = new THREE.PointLight('#ff8a3a', 0, 120, 1.6);
  scene.add(fireLight);
  F.fireLight = fireLight;
  F.fireSum = { x: 0, z: 0, n: 0 };

  F.render = (dt, time) => {
    lit.step(dt, T.height); glow.step(dt, T.height);
    lit.draw(time); glow.draw(time);

    // bolts
    let n = 0;
    for (let i = F.bolts.length - 1; i >= 0; i--) {
      const b = F.bolts[i];
      b.life -= dt;
      if (b.life <= 0) { F.bolts.splice(i, 1); continue; }
      const flick = (Math.sin(b.life * 90) > -0.3 ? 1 : 0.25) * (b.life / b.max);
      for (const sg of b.segs) {
        if (n >= 120) break;
        dir.set(sg[3] - sg[0], sg[4] - sg[1], sg[5] - sg[2]);
        const len = dir.length();
        q.setFromUnitVectors(up, dir.normalize());
        const w = 0.6 * flick * (sg[6] || 1);
        boltMesh.setMatrixAt(n++, M.compose(p.set((sg[0] + sg[3]) / 2, (sg[1] + sg[4]) / 2, (sg[2] + sg[5]) / 2), q, s.set(w, len, w)));
      }
    }
    boltMesh.count = n; boltMesh.instanceMatrix.needsUpdate = true;

    // meteors
    for (let i = F.meteors.length - 1; i >= 0; i--) {
      const m = F.meteors[i];
      m.t += dt;
      const t = Math.min(1, m.t / m.dur), tt = t * t;
      const x = lerp(m.x0, m.x, tt), y = lerp(m.y0, m.y, tt), z = lerp(m.z0, m.z, tt);
      m.mesh.position.set(x, y, z);
      for (let k = 0; k < 5; k++) {
        glow.add({ x: x + (R() - 0.5), y: y + (R() - 0.5), z: z + (R() - 0.5), vx: -3 + R() * 2, vy: 2 + R() * 2, vz: -2 + R() * 2, life: 0.5 + R() * 0.5, max: 1, size: (0.6 + R() * 0.7) * m.size, shrink: 1.6, spin: 5, fire: true });
      }
      if (R() < 0.6) F.smoke(x, y, z, 1.2 * m.size, 0.25);
      if (t >= 1) {
        scene.remove(m.mesh); F.meteors.splice(i, 1);
        stage.flash = 1.4; stage.shake = 2.6 * m.size;
        F.ring(m.x, m.y, m.z, 20 * m.size, '#fff1cf', 0.8);
        F.ring(m.x, m.y, m.z, 11 * m.size, '#ffb561', 1.1);
        F.burst(m.x, m.y + 0.5, m.z, '#8a6a48', 90, 2.3);
        F.burst(m.x, m.y + 0.5, m.z, '#4b3a2c', 60, 1.7);
        F.spark(m.x, m.y + 0.5, m.z, 80, '#ffb561', 2.4);
        for (let k = 0; k < 40; k++) F.smoke(m.x + (R() - 0.5) * 8, m.y + R() * 2, m.z + (R() - 0.5) * 8, 1.1, 0.24);
        m.onImpact && m.onImpact();
      }
    }
    for (let i = F.rings.length - 1; i >= 0; i--) {
      const r = F.rings[i];
      r.t += dt;
      const t = r.t / r.dur;
      if (t >= 1) { scene.remove(r.mesh); F.rings.splice(i, 1); continue; }
      const k = 1 - (1 - t) * (1 - t);
      r.mesh.scale.setScalar(Math.max(0.01, r.r * k));
      r.mesh.material.opacity = 0.9 * (1 - t);
    }

    // clouds
    for (let i = F.clouds.length - 1; i >= 0; i--) {
      const c = F.clouds[i];
      if (c.ttl !== undefined) { c.ttl -= dt; if (c.ttl <= 0) c.dying = true; }
      const target = c.dying ? 0 : 1;
      c.grow += clamp(target - c.grow, -dt * 0.9, dt * (c.ttl !== undefined ? 6 : 0.9));
      c.mesh.scale.setScalar(Math.max(0.001, c.sc * c.grow * (1 + Math.sin(time * 0.4 + i) * 0.02)));
      c.mesh.position.x += c.vx * dt * G.speed * 0.6;
      if (c.mesh.position.x > N + 30) c.mesh.position.x = -30;
      // Clouds fade away as the camera gets close, so a close-up never ends up inside one.
      const cd = stage.camera.position.distanceTo(c.mesh.position);
      const nearFade = clamp((cd - 11 * c.sc) / 14, 0, 1);
      c.mesh.material.opacity = (c.rain ? 0.9 : 0.96 * (1 - stage.night * 0.3)) * nearFade;
      c.mesh.material.emissiveIntensity = c.rain ? 0 : 0.32 * (1 - stage.night * 0.85);
      c.mesh.visible = nearFade > 0.01;
      c.mesh.castShadow = nearFade > 0.5;
      if (c.dying && c.grow <= 0.001) { scene.remove(c.mesh); F.clouds.splice(i, 1); }
    }

    // fire light
    const fs = F.fireSum;
    const want = fs.n > 0 ? Math.min(900, 120 + fs.n * 22) : 0;
    fireLight.intensity += (want * (0.85 + Math.sin(time * 23) * 0.15) - fireLight.intensity) * Math.min(1, dt * 6);
    if (fs.n > 0) fireLight.position.set(fs.x / fs.n, 5, fs.z / fs.n);
  };

  return F;
}
