// Draws every creature of one kind with a handful of instanced meshes (one per body part).
import * as THREE from '../vendor/three/three.module.js';
import { toyMaterial } from './util.js';

const M = new THREE.Matrix4(), L = new THREE.Matrix4(), R = new THREE.Matrix4(), O = new THREE.Matrix4();
const q = new THREE.Quaternion(), e3 = new THREE.Euler(0, 0, 0, 'YXZ'), p = new THREE.Vector3(), s = new THREE.Vector3();
const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);
const material = toyMaterial();

export class CreatureKind {
  constructor(scene, parts, max, opts = {}) {
    this.parts = parts;
    this.max = max;
    this.list = [];
    this.swing = opts.swing ?? 0.75;
    this.hop = opts.hop || 0;        // models without separate legs walk with a small hop and sway
    this.meshes = parts.map(pt => {
      const m = new THREE.InstancedMesh(pt.geo, pt.material || material, max);
      m.castShadow = true;
      m.receiveShadow = false;
      m.frustumCulled = false;
      m.count = 0;
      scene.add(m);
      return m;
    });
  }

  // Entities carry: x, y, z, yaw, scale, gait, amp, and optional pitch, roll, bob, flap,
  // attack (0..1), cheer (0..1), spear, shield, carry.
  draw() {
    const list = this.list, n = Math.min(list.length, this.max), parts = this.parts;
    for (let i = 0; i < n; i++) {
      const c = list[i];
      const sc = c.scale || 1;
      let hopY = 0, sway = 0;
      if (this.hop && c.amp > 0.02) { hopY = Math.abs(Math.sin(c.gait * 0.5)) * this.hop * c.amp * sc; sway = Math.sin(c.gait * 0.5) * 0.07 * c.amp; }
      e3.set((c.pitch || 0) * (this.hop ? 0.35 : 1), c.yaw, (c.roll || 0) + sway);
      q.setFromEuler(e3);
      M.compose(p.set(c.x, c.y + (c.bob || 0) + hopY, c.z), q, s.set(sc, sc, sc));
      for (let k = 0; k < parts.length; k++) {
        const pt = parts[k], mesh = this.meshes[k];
        let ang = 0, axis = 0, dz = 0;
        switch (pt.kind) {
          case 'body': break;
          case 'leg': ang = Math.sin(c.gait + pt.phase) * this.swing * c.amp; break;
          case 'arm':
            ang = Math.sin(c.gait + pt.phase) * 0.6 * c.amp;
            if (c.cheer) ang = -2.7 * c.cheer + Math.sin(c.gait * 2 + pt.phase) * 0.25;
            if (c.attack && pt.phase === Math.PI) ang = -1.9 * c.attack;
            if (c.carry) ang = -2.9;
            break;
          case 'wingR': ang = Math.sin(c.flap || 0) * 0.75; axis = 2; break;
          case 'wingL': ang = -Math.sin(c.flap || 0) * 0.75; axis = 2; break;
          case 'spear': if (!c.spear) { mesh.setMatrixAt(i, ZERO); continue; } ang = c.attack ? 1.1 * c.attack : 0; dz = c.attack ? 0.35 * c.attack : 0; break;
          case 'shield': if (!c.shield) { mesh.setMatrixAt(i, ZERO); continue; } break;
          case 'carry': if (!c.carry) { mesh.setMatrixAt(i, ZERO); continue; } break;
        }
        L.makeTranslation(pt.pivot[0], pt.pivot[1], pt.pivot[2] + dz);
        if (ang !== 0) { axis === 2 ? R.makeRotationZ(ang) : R.makeRotationX(ang); L.multiply(R); }
        O.multiplyMatrices(M, L);
        mesh.setMatrixAt(i, O);
      }
    }
    for (const mesh of this.meshes) { mesh.count = n; mesh.instanceMatrix.needsUpdate = true; }
  }
}
