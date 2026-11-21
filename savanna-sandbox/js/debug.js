// ?debug=models : a line-up of every model, for checking how they look.
import * as THREE from '../vendor/three/three.module.js';
import { toyMaterial } from './util.js';
import { CreatureKind } from './creatures.js';
import * as MD from './models.js';

export function modelLineup(G) {
  const { stage, terrain: T } = G;
  const kinds = [MD.humanParts(0), MD.humanParts(1), MD.zebraParts(), MD.wildebeestParts(), MD.gazelleParts(), MD.lionParts(), MD.elephantParts(), MD.giraffeParts(), MD.birdParts()];
  const ck = kinds.map(p => new CreatureKind(stage.scene, p, 4));
  const cx = 64, cz = 52;
  ck.forEach((k, i) => {
    const x = cx - 12 + i * 3, z = cz + 4;
    k.list.push({ x, z, y: T.height(x, z) + (i === 8 ? 1.5 : 0), yaw: 0.5, gait: 1.0, amp: 0.7, flap: 0.6, spear: i < 2, shield: i === 1, carry: false });
    if (i < 2) k.list.push({ x: x + 0.2, z: z + 2.2, y: T.height(x, z + 2.2), yaw: 0.9, gait: 2.0, amp: 0.5, carry: true });
    G.systems.push({ render: () => k.draw() });
  });
  const mat = toyMaterial();
  const glowMat = new THREE.MeshBasicMaterial({ vertexColors: true });
  const models = [MD.shelterModel(0), MD.hutModel(0), MD.houseModel(0), MD.stoneHouseModel(0), MD.hutModel(1), MD.houseModel(1), MD.stoneHouseModel(1),
    MD.bonfireModel(), MD.totemModel(0, 3), MD.granaryModel(1), MD.towerModel(0), MD.stallModel(1, 0), MD.fieldModel()];
  models.forEach((m, i) => {
    const x = cx - 14 + (i % 7) * 4.6, z = cz - 3 - Math.floor(i / 7) * 6;
    const mesh = new THREE.Mesh(m.geo, mat); mesh.castShadow = mesh.receiveShadow = true;
    mesh.position.set(x, T.height(x, z), z); mesh.rotation.y = 0.5;
    const gl = new THREE.Mesh(m.glow, glowMat); gl.position.copy(mesh.position); gl.rotation.y = 0.5;
    stage.scene.add(mesh, gl);
  });
  const hall = MD.hallModel(0); const hm = new THREE.Mesh(hall.geo, mat); hm.castShadow = true; hm.position.set(cx + 14, T.height(cx + 14, cz - 14), cz - 14); hm.rotation.y = 0.5; stage.scene.add(hm);
  const wall = MD.wallModel(1, 4, 8, 1.2); const wm = new THREE.Mesh(wall.geo, mat); wm.castShadow = true; wm.position.set(cx - 22, T.height(cx - 22, cz - 12), cz - 12); stage.scene.add(wm);
  const wall3 = MD.wallModel(0, 3, 6, 1.2); const wm3 = new THREE.Mesh(wall3.geo, mat); wm3.castShadow = true; wm3.position.set(cx - 22, T.height(cx - 22, cz + 6), cz + 6); stage.scene.add(wm3);
  Object.assign(stage.cam, { tx: cx, tz: cz, ty: 2, dist: 62, yaw: 0.35, pitch: 0.45 });
}

// ?debug=assets : every generated model in a grid on the first village's flat ground.
export function assetLineup(G) {
  const { stage, terrain: T } = G;
  const names = Object.keys(G.assets);
  const v = G.villages[0];
  let x = v.x - 16, z = v.z - 8, rowH = 0;
  names.forEach((n) => {
    const a = G.assets[n];
    const w = Math.max(a.size.x, a.size.z) + 1.2;
    if (x + w > v.x + 18) { x = v.x - 16; z += rowH + 1.5; rowH = 0; }
    const m = new THREE.Mesh(a.geo, a.mat);
    m.castShadow = m.receiveShadow = true;
    m.position.set(x + w / 2, T.height(x + w / 2, z), z);
    stage.scene.add(m);
    x += w; rowH = Math.max(rowH, a.size.z);
    console.log('asset', n, 'tris', Math.round(a.tris), 'size', a.size.x.toFixed(2), a.size.y.toFixed(2), a.size.z.toFixed(2));
  });
  Object.assign(stage.cam, { tx: v.x, tz: v.z, ty: 1.5, dist: 48, yaw: 0.25, pitch: 0.3 });
}
