// Renderer, lights, day / night colours and the orbit camera.
import * as THREE from '../vendor/three/three.module.js';
import { clamp, lerp, smooth } from './util.js';
import { N } from './terrain.js';

const KEYS = [
  // t (0..1 of a day), sky, sun colour, sun intensity, hemi sky, hemi ground, hemi intensity
  { t: 0.00, sky: '#182040', sun: '#a9bcff', si: 0.9, hs: '#4a5aa8', hg: '#2a2a40', hi: 1.0 },
  { t: 0.20, sky: '#1c2446', sun: '#a9bcff', si: 0.9, hs: '#4a5aa8', hg: '#2a2a40', hi: 1.0 },
  { t: 0.27, sky: '#f3b48a', sun: '#ffb070', si: 1.6, hs: '#f6c9a8', hg: '#7a5a48', hi: 0.7 },
  { t: 0.36, sky: '#f4e7cf', sun: '#fff0d6', si: 2.7, hs: '#fdf3e0', hg: '#b89468', hi: 0.9 },
  { t: 0.64, sky: '#f4e7cf', sun: '#fff0d6', si: 2.7, hs: '#fdf3e0', hg: '#b89468', hi: 0.9 },
  { t: 0.73, sky: '#f2a36e', sun: '#ff9a52', si: 1.9, hs: '#f7b98e', hg: '#7a5040', hi: 0.7 },
  { t: 0.80, sky: '#34305e', sun: '#a9a4ff', si: 0.8, hs: '#4c4a98', hg: '#2a2438', hi: 0.95 },
  { t: 1.00, sky: '#182040', sun: '#a9bcff', si: 0.9, hs: '#4a5aa8', hg: '#2a2a40', hi: 1.0 },
];
const ca = new THREE.Color(), cb = new THREE.Color();

export function createStage(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color('#f4e7cf');

  const camera = new THREE.PerspectiveCamera(26, 1, 1, 3200);

  const hemi = new THREE.HemisphereLight('#fdf3e0', '#b89468', 0.9);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight('#fff0d6', 2.7);
  sun.castShadow = true;
  const maxTex = renderer.capabilities.maxTextureSize;
  sun.shadow.mapSize.set(Math.min(8192, maxTex), Math.min(8192, maxTex));
  const sc = sun.shadow.camera;
  const half = N * 0.78;
  sc.left = -half; sc.right = half; sc.top = half; sc.bottom = -half; sc.near = 10; sc.far = N * 4.2;
  sun.shadow.bias = -0.0005;
  sun.shadow.normalBias = 0.05;
  sun.shadow.radius = 2.5;
  sun.target.position.set(N / 2, 0, N / 2);
  scene.add(sun, sun.target);

  // A table top that only shows the slab's shadow.
  const table = new THREE.Mesh(new THREE.CircleGeometry(1400, 48).rotateX(-Math.PI / 2), new THREE.ShadowMaterial({ opacity: 0.22 }));
  table.position.set(N / 2, -7.9, N / 2);
  table.receiveShadow = true;
  scene.add(table);

  const S = { renderer, scene, camera, sun, hemi, night: 0, dayT: 0.4, flash: 0, shake: 0, bgBoost: 1 };

  // ---- day / night
  S.setTime = (t) => {
    t = ((t % 1) + 1) % 1;
    S.dayT = t;
    let i = 0;
    while (i < KEYS.length - 2 && KEYS[i + 1].t <= t) i++;
    const a = KEYS[i], b = KEYS[i + 1];
    const f = smooth(0, 1, (t - a.t) / (b.t - a.t));
    scene.background.copy(ca.set(a.sky)).lerp(cb.set(b.sky), f);
    sun.color.copy(ca.set(a.sun)).lerp(cb.set(b.sun), f);
    sun.intensity = lerp(a.si, b.si, f) + S.flash * 6;
    hemi.color.copy(ca.set(a.hs)).lerp(cb.set(b.hs), f);
    hemi.groundColor.copy(ca.set(a.hg)).lerp(cb.set(b.hg), f);
    hemi.intensity = lerp(a.hi, b.hi, f) + S.flash * 1.5;
    S.night = 1 - smooth(0.22, 0.3, t) * (1 - smooth(0.72, 0.8, t));
    scene.background.multiplyScalar(lerp(S.bgBoost, 0.55, S.night));
    if (S.room) { scene.background.copy(S.room.bg); table.visible = false; }
    // Sun travels east -> west during the day; at night the same light acts as a moon.
    const dayPhase = clamp((t - 0.25) / 0.5, 0, 1);
    const ang = S.night > 0.5 ? 0.62 * Math.PI : lerp(0.14, 0.86, dayPhase) * Math.PI;
    const elev = S.night > 0.5 ? 0.9 : 0.35 + Math.sin(dayPhase * Math.PI) * 0.75;
    const q = N / 96;
    sun.position.set(N / 2 + Math.cos(ang) * 150 * q, (Math.sin(elev) * 170 + 30) * q, N / 2 + (-70 + Math.sin(ang) * 30) * q);
  };

  // ---- orbit camera
  const cam = { tx: N / 2, ty: 0, tz: N / 2, yaw: 0.72, pitch: 0.66, dist: 235 * N / 96 };
  S.cam = cam;
  S.applyCamera = (time = 0) => {
    cam.pitch = clamp(cam.pitch, 0.05, 1.45);
    cam.dist = clamp(cam.dist, 10, 1200);
    const cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
    let sx = 0, sy = 0;
    if (S.shake > 0.001) {
      sx = Math.sin(time * 71) * S.shake; sy = Math.cos(time * 53) * S.shake;
    }
    camera.position.set(cam.tx + Math.sin(cam.yaw) * cp * cam.dist + sx, cam.ty + sp * cam.dist + sy, cam.tz + Math.cos(cam.yaw) * cp * cam.dist);
    camera.lookAt(cam.tx + sx, cam.ty + sy, cam.tz);
  };

  let drag = null;
  canvas.addEventListener('contextmenu', e => e.preventDefault());
  canvas.addEventListener('pointerdown', e => {
    if (S.onPointer && e.button === 0 && !e.shiftKey && S.onPointer('down', e)) { drag = { mode: 'tool' }; canvas.setPointerCapture(e.pointerId); return; }
    drag = { x: e.clientX, y: e.clientY, mode: e.button === 2 || e.shiftKey ? 'pan' : 'orbit' };
    canvas.setPointerCapture(e.pointerId);
  });
  canvas.addEventListener('pointermove', e => {
    if (!drag) { S.onPointer && S.onPointer('hover', e); return; }
    if (drag.mode === 'tool') { S.onPointer('drag', e); return; }
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag.x = e.clientX; drag.y = e.clientY;
    if (drag.mode === 'orbit') { cam.yaw -= dx * 0.005; cam.pitch += dy * 0.004; }
    else {
      const k = cam.dist * 0.0011;
      cam.tx -= (Math.cos(cam.yaw) * dx + Math.sin(cam.yaw) * dy) * k;
      cam.tz -= (-Math.sin(cam.yaw) * dx + Math.cos(cam.yaw) * dy) * k;
      cam.tx = clamp(cam.tx, -10, N + 10); cam.tz = clamp(cam.tz, -10, N + 10);
    }
  });
  const end = e => { if (drag && drag.mode === 'tool') S.onPointer('up', e); drag = null; };
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);
  canvas.addEventListener('wheel', e => { e.preventDefault(); cam.dist *= Math.exp(e.deltaY * 0.0012); }, { passive: false });

  S.resize = () => {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    // Portrait screens need a taller field of view to keep the slab in frame.
    camera.fov = w < h ? 34 : 26;
    camera.updateProjectionMatrix();
  };
  window.addEventListener('resize', S.resize);
  S.resize();

  // Screen point -> point on the terrain (marching along the ray).
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  S.pick = (e, terrain) => {
    const r = canvas.getBoundingClientRect();
    ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(ndc, camera);
    const o = ray.ray.origin, d = ray.ray.direction;
    let prev = 0;
    for (let t = 0; t < 2400; t += 0.5) {
      const x = o.x + d.x * t, y = o.y + d.y * t, z = o.z + d.z * t;
      if (x < 0 || z < 0 || x > N || z > N) { prev = t; continue; }
      if (y <= Math.max(terrain.height(x, z), terrain.waterLevel)) {
        const tm = (prev + t) / 2;
        return { x: o.x + d.x * tm, z: o.z + d.z * tm };
      }
      prev = t;
    }
    return null;
  };

  return S;
}
