// The god's study: the slab sits on a big dark desk in a wood-panelled room with a
// fireplace, lamps and bookshelves. Mostly seen out of focus behind the savanna.
// `?room=0` switches back to the plain studio backdrop.
import * as THREE from '../vendor/three/three.module.js';
import { N, BASE_Y } from './terrain.js';
import { Builder, makeRng } from './util.js';

export function createRoom(stage) {
  const { scene } = stage;
  const c = N / 2, U = N / 256;          // U: room units per slab size
  const rng = makeRng(77);
  const group = new THREE.Group();
  scene.add(group);
  const DIM = 0.3;      // the lamp over the table is bright; the room itself stays dark
  const std = (color, rough = 0.8) => { const m = new THREE.MeshStandardMaterial({ color, roughness: rough }); m.color.multiplyScalar(DIM); return m; };
  const add = (geo, mat, x, y, z, shadow = false) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z); m.receiveShadow = shadow;
    group.add(m);
    return m;
  };
  const box = (w, h, d) => new THREE.BoxGeometry(w * U, h * U, d * U);

  // desk
  const deskY = BASE_Y - 3.0;
  add(box(470, 9, 400), std('#4a2616', 0.32), c, deskY - 4.5 * U, c, true);
  add(box(480, 5, 410), std('#2f170d', 0.4), c, deskY - 11 * U, c);
  add(box(440, 170, 370), std('#27130b', 0.6), c, deskY - 98 * U, c);
  // things on the desk
  const bk = new Builder();
  bk.box(46, 7, 60, 0, 3.5, 0, '#5b1f1b'); bk.box(42, 5, 56, 2, 9.5, 1, '#e8dcc0'); bk.box(46, 2, 60, 1, 13, 0, '#5b1f1b');
  bk.box(40, 6, 54, -3, 17, 4, '#1f3a34', 0, 0.3, 0);
  bk.cyl(7, 9, 26, 62, 13, -30, '#b08a3a', 12); bk.cyl(1.2, 1.2, 40, 62, 40, -30, '#e9e2d0', 6, 0.2, 0, 0.15);
  const deskStuff = new THREE.Mesh(bk.build().scale(U, U, U), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.6, color: new THREE.Color(0.5, 0.5, 0.5) }));
  deskStuff.position.set(c - 186 * U, deskY, c + 120 * U);
  group.add(deskStuff);

  // floor and walls
  const floorY = deskY - 185 * U;
  add(new THREE.PlaneGeometry(4200 * U, 4200 * U).rotateX(-Math.PI / 2), std('#2a1810', 0.5), c, floorY, c);
  add(box(1100, 6, 760), std('#6a2a22', 0.95), c, floorY + 3 * U, c);          // rug
  add(box(1040, 7, 700), std('#8a6a3c', 0.95), c, floorY + 3.2 * U, c);
  add(box(960, 8, 620), std('#5c2420', 0.95), c, floorY + 3.4 * U, c);
  const WZ = 1050, WX = 1250, WH = 900;
  const wallMat = std('#3b2014', 0.7), panelMat = std('#4a2a1a', 0.55), trimMat = std('#2a150c', 0.6);
  const wall = (x, z, ry, len) => {
    const g = new THREE.Group();
    g.position.set(c + x * U, floorY, c + z * U); g.rotation.y = ry;
    const m = new THREE.Mesh(box(len, WH, 12), wallMat); m.position.y = WH * U / 2; g.add(m);
    const n = Math.floor(len / 190);
    for (let i = 0; i < n; i++) {
      const px = (-len / 2 + (i + 0.5) * (len / n)) * U;
      const lo = new THREE.Mesh(box(150, 210, 8), panelMat); lo.position.set(px, 135 * U, 8 * U); g.add(lo);
      const hi = new THREE.Mesh(box(150, 330, 8), panelMat); hi.position.set(px, 440 * U, 8 * U); g.add(hi);
    }
    const rail = new THREE.Mesh(box(len, 18, 20), trimMat); rail.position.set(0, 258 * U, 8 * U); g.add(rail);
    const base = new THREE.Mesh(box(len, 30, 20), trimMat); base.position.set(0, 15 * U, 8 * U); g.add(base);
    const crown = new THREE.Mesh(box(len, 40, 26), trimMat); crown.position.set(0, 640 * U, 8 * U); g.add(crown);
    group.add(g);
    return g;
  };
  wall(0, -WZ, 0, WX * 2);
  wall(-WX, 0, Math.PI / 2, WZ * 2);
  wall(WX, 0, -Math.PI / 2, WZ * 2);
  wall(0, WZ, Math.PI, WX * 2);

  const glowMat = (color) => new THREE.MeshBasicMaterial({ color, toneMapped: false });
  const lights = [];

  // fireplace on the back wall
  const fpX = c - 260 * U, fpZ = c + (-WZ + 20) * U;
  add(box(400, 330, 50), std('#b9ab95', 0.8), fpX, floorY + 165 * U, fpZ);
  add(box(460, 26, 70), std('#d2c6b0', 0.7), fpX, floorY + 340 * U, fpZ + 6 * U);
  add(box(230, 200, 20), std('#0d0806', 1), fpX, floorY + 100 * U, fpZ + 20 * U);
  const fire = add(box(150, 90, 6), glowMat('#ff8a2e'), fpX, floorY + 55 * U, fpZ + 30 * U);
  const fire2 = add(box(80, 60, 6), glowMat('#ffd27a'), fpX, floorY + 45 * U, fpZ + 33 * U);
  const fireLight = new THREE.PointLight('#ff8a3a', 0, 0, 1.4);
  fireLight.position.set(fpX, floorY + 120 * U, fpZ + 90 * U);
  group.add(fireLight);
  // painting above it
  add(box(300, 190, 10), std('#b08a3a', 0.4), fpX, floorY + 500 * U, fpZ - 10 * U);
  add(box(262, 152, 12), std('#5e6b58', 0.9), fpX, floorY + 500 * U, fpZ - 8 * U);
  add(box(262, 60, 13), std('#a39a78', 0.9), fpX, floorY + 470 * U, fpZ - 8 * U);

  // wall sconces and standing lamps: the warm out-of-focus dots behind the table
  const lamp = (x, y, z, r, color = '#ffcf8a') => {
    const m = add(new THREE.SphereGeometry(r * U, 16, 12), glowMat(color), c + x * U, floorY + y * U, c + z * U);
    lights.push(m);
    return m;
  };
  for (const x of [-900, -560, 40, 380, 760]) lamp(x, 470, -WZ + 34, 20);
  for (const z of [-600, -100, 420]) { lamp(-WX + 34, 470, z, 20); lamp(WX - 34, 470, z, 20); }
  for (const x of [-700, 100, 700]) lamp(x, 470, WZ - 34, 20);
  const stand = (x, z) => {
    add(box(8, 330, 8), std('#b08a3a', 0.4), c + x * U, floorY + 165 * U, c + z * U);
    add(new THREE.CylinderGeometry(22 * U, 34 * U, 10 * U, 16), std('#b08a3a', 0.4), c + x * U, floorY + 5 * U, c + z * U);
    lamp(x, 372, z, 52, '#ffc070');
    const l = new THREE.PointLight('#ffb466', 0, 0, 1.6);
    l.position.set(c + x * U, floorY + 372 * U, c + z * U);
    group.add(l);
    return l;
  };
  const standLights = [stand(470, -420), stand(-520, 330)];

  // bookshelves on the left wall and right of the fireplace
  const shelf = (x, z, ry, w) => {
    const b = new Builder();
    b.box(w, 560, 60, 0, 280, 0, '#2a150c');
    const cols = ['#6a2a22', '#23463e', '#7a5a2a', '#2b3558', '#8a7a5c', '#4a2030', '#b9a070'];
    for (let row = 0; row < 6; row++) {
      let px = -w / 2 + 14;
      while (px < w / 2 - 22) {
        const bw = rng.range(8, 20), bh = rng.range(50, 74);
        b.box(bw, bh, 36, px + bw / 2, 26 + row * 88 + bh / 2, 16, rng.pick(cols));
        px += bw + rng.range(0.5, 2.5);
      }
      b.box(w - 8, 7, 54, 0, 22 + row * 88, 8, '#3b2014');
    }
    const m = new THREE.Mesh(b.build().scale(U, U, U), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.75, color: new THREE.Color(DIM, DIM, DIM) }));
    m.position.set(c + x * U, floorY, c + z * U); m.rotation.y = ry;
    group.add(m);
  };
  shelf(330, -WZ + 44, 0, 520);
  shelf(900, -WZ + 44, 0, 420);
  shelf(-WX + 44, -300, Math.PI / 2, 620);
  shelf(-WX + 44, 480, Math.PI / 2, 520);
  shelf(WX - 44, 100, -Math.PI / 2, 700);

  // an armchair behind the desk, where the god sits
  const ch = new Builder();
  ch.box(190, 60, 170, 0, 70, 0, '#5a1f1c'); ch.box(190, 230, 40, 0, 215, -75, '#5a1f1c');
  ch.box(36, 110, 170, 95, 115, 0, '#4a1917'); ch.box(36, 110, 170, -95, 115, 0, '#4a1917');
  ch.box(200, 40, 180, 0, 20, 0, '#2a150c');
  const chair = new THREE.Mesh(ch.build().scale(U, U, U), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.6, color: new THREE.Color(DIM, DIM, DIM) }));
  chair.position.set(c + 30 * U, floorY, c - 330 * U);
  group.add(chair);

  const R = { group, bg: new THREE.Color('#120a06') };
  R.update = (time, night) => {
    const flick = 0.85 + Math.sin(time * 9) * 0.08 + Math.sin(time * 23) * 0.05;
    fire.scale.y = 0.85 + Math.sin(time * 11) * 0.12; fire2.scale.y = 0.8 + Math.sin(time * 17 + 1) * 0.18;
    fireLight.intensity = 4.0e4 * U * U * flick * (0.6 + night * 0.4);
    for (const l of standLights) l.intensity = 1.6e4 * U * U * (0.6 + night * 0.4);
  };
  return R;
}
