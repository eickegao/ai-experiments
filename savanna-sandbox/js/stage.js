// Renderer, lights, day / night colours and the orbit camera.
import * as THREE from '../vendor/three/three.module.js';
import { clamp, lerp, smooth } from './util.js';
import { N } from './terrain.js';

const KEYS = [
  // t (0..1 of a day), sky, sun colour, sun intensity, hemi sky, hemi ground, hemi intensity
  { t: 0.00, sky: '#3a4a86', sun: '#c2d0ff', si: 1.5, hs: '#7f93e0', hg: '#4a4f78', hi: 1.75 },
  { t: 0.20, sky: '#3d4d8a', sun: '#c2d0ff', si: 1.5, hs: '#7f93e0', hg: '#4a4f78', hi: 1.75 },
  { t: 0.27, sky: '#f6c3a0', sun: '#ffb884', si: 1.9, hs: '#f8d2b8', hg: '#8a6a58', hi: 1.0 },
  { t: 0.36, sky: '#cfe4f2', sun: '#fff4e2', si: 2.35, hs: '#e8f2ff', hg: '#b8a078', hi: 1.15 },
  { t: 0.64, sky: '#cfe4f2', sun: '#fff4e2', si: 2.35, hs: '#e8f2ff', hg: '#b8a078', hi: 1.15 },
  { t: 0.73, sky: '#f4ae84', sun: '#ffa468', si: 2.0, hs: '#f8c4a0', hg: '#8a6050', hi: 1.0 },
  { t: 0.80, sky: '#4a4a8c', sun: '#c0bcff', si: 1.4, hs: '#8088d8', hg: '#4a4870', hi: 1.6 },
  { t: 1.00, sky: '#3a4a86', sun: '#c2d0ff', si: 1.5, hs: '#7f93e0', hg: '#4a4f78', hi: 1.75 },
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
  scene.background = new THREE.Color('#cfe4f2');
  // Distance haze: the far parts of the map fade into the sky until you travel there.
  scene.fog = new THREE.Fog('#cfe4f2', 200, 400);

  const camera = new THREE.PerspectiveCamera(26, 1, 1, 3200);

  const hemi = new THREE.HemisphereLight('#fdf3e0', '#b89468', 0.9);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight('#fff0d6', 2.7);
  sun.castShadow = true;
  const maxTex = renderer.capabilities.maxTextureSize;
  sun.shadow.mapSize.set(Math.min(4096, maxTex), Math.min(4096, maxTex));
  const sc = sun.shadow.camera;
  const half = N * 0.78;
  sc.left = -half; sc.right = half; sc.top = half; sc.bottom = -half; sc.near = 10; sc.far = 2400;
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

  const S = { sunOffset: new THREE.Vector3(), renderer, scene, camera, sun, hemi, night: 0, dayT: 0.4, flash: 0, shake: 0, bgBoost: 1 };

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
    scene.background.multiplyScalar(lerp(S.bgBoost, 1.0, S.night));
    if (S.room) { scene.background.copy(S.room.bg); scene.fog.near = 1e5; scene.fog.far = 2e5; }
    scene.fog.color.copy(scene.background);
    table.visible = false;
    // Sun travels east -> west during the day; at night the same light acts as a moon.
    const dayPhase = clamp((t - 0.25) / 0.5, 0, 1);
    const ang = S.night > 0.5 ? 0.62 * Math.PI : lerp(0.14, 0.86, dayPhase) * Math.PI;
    const elev = S.night > 0.5 ? 0.9 : 0.35 + Math.sin(dayPhase * Math.PI) * 0.75;
    const q = N / 96;
    const qq = S.room ? q : 2.6;
    S.sunOffset.set(Math.cos(ang) * 150 * qq, (Math.sin(elev) * 170 + 30) * qq, (-70 + Math.sin(ang) * 30) * qq);
    sun.position.set(N / 2, 0, N / 2).add(S.sunOffset);
  };

  // ---- orbit camera
  const cam = { tx: N / 2, ty: 0, tz: N / 2 + 10, yaw: 0.5, pitch: 0.72, dist: 150 };
  S.maxDist = 230; S.margin = 48;
  // What is worth drawing: things within `r` of the point the camera looks at.
  S.view = { x: cam.tx, z: cam.tz, r: 400 };
  S.cam = cam;
  S.applyCamera = (time = 0) => {
    cam.pitch = clamp(cam.pitch, S.room ? 0.05 : 0.2, 1.45);
    cam.dist = clamp(cam.dist, 10, S.room ? 1200 : S.maxDist);
    if (!S.room) {
      cam.tx = clamp(cam.tx, S.margin, N - S.margin); cam.tz = clamp(cam.tz, S.margin, N - S.margin);
      scene.fog.near = cam.dist * 1.1 + (S.haze === false ? 260 : 40); scene.fog.far = cam.dist * 1.1 + (S.haze === false ? 520 : 230);
    }
    S.view.x = cam.tx; S.view.z = cam.tz; S.view.r = S.room ? 1e5 : cam.dist * (1.0 + 0.9 * (1 - Math.min(1, cam.pitch))) + (S.haze === false ? 300 : 150);
    // The sun's shadow box follows the camera so shadows stay sharp on a big map.
    const half = S.room ? N * 0.78 : clamp(cam.dist * 1.15 + 70, 90, 330);
    const scm = sun.shadow.camera;
    if (Math.abs(scm.right - half) > 4) { scm.left = -half; scm.right = half; scm.top = half; scm.bottom = -half; scm.updateProjectionMatrix(); }
    if (!S.room) { sun.target.position.set(cam.tx, 0, cam.tz); sun.position.copy(S.sunOffset).add(sun.target.position); sun.target.updateMatrixWorld(); }
    const cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
    let sx = 0, sy = 0;
    if (S.shake > 0.001) {
      sx = Math.sin(time * 71) * S.shake; sy = Math.cos(time * 53) * S.shake;
    }
    camera.position.set(cam.tx + Math.sin(cam.yaw) * cp * cam.dist + sx, cam.ty + sp * cam.dist + sy, cam.tz + Math.cos(cam.yaw) * cp * cam.dist);
    camera.lookAt(cam.tx + sx, cam.ty + sy, cam.tz);
  };

  let drag = null;
  S.dragMode = 'pan';       // left drag moves the map; the Rotate tool (or right drag) orbits
  const keys = new Set();
  window.addEventListener('keydown', e => keys.add(e.key.toLowerCase()));
  window.addEventListener('keyup', e => keys.delete(e.key.toLowerCase()));
  S.keyPan = (dt) => {
    let dx = 0, dy = 0;
    if (keys.has('a') || keys.has('arrowleft')) dx += 1;
    if (keys.has('d') || keys.has('arrowright')) dx -= 1;
    if (keys.has('w') || keys.has('arrowup')) dy += 1;
    if (keys.has('s') || keys.has('arrowdown')) dy -= 1;
    if (!dx && !dy) return;
    const k = cam.dist * 0.9 * dt;
    cam.tx -= (Math.cos(cam.yaw) * dx + Math.sin(cam.yaw) * dy) * k;
    cam.tz -= (-Math.sin(cam.yaw) * dx + Math.cos(cam.yaw) * dy) * k;
  };
  canvas.addEventListener('contextmenu', e => e.preventDefault());
  canvas.addEventListener('pointerdown', e => {
    if (S.onPointer && e.button === 0 && !e.shiftKey && S.onPointer('down', e)) { drag = { mode: 'tool' }; canvas.setPointerCapture(e.pointerId); return; }
    const other = S.dragMode === 'pan' ? 'orbit' : 'pan';
    drag = { x: e.clientX, y: e.clientY, mode: e.button === 2 || e.shiftKey ? other : S.dragMode };
    canvas.setPointerCapture(e.pointerId);
  });
  canvas.addEventListener('pointermove', e => {
    if (!drag) { S.onPointer && S.onPointer('hover', e); return; }
    if (drag.mode === 'tool') { S.onPointer('drag', e); return; }
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag.x = e.clientX; drag.y = e.clientY;
    if (drag.mode === 'orbit') { cam.yaw -= dx * 0.005; cam.pitch += dy * 0.004; }
    else {
      const k = cam.dist * 0.00125;
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
