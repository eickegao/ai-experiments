// Loads the generated GLB models (assets/models/*.glb) and turns each into one
// geometry plus one textured material, normalised so that it stands on y = 0,
// is centred on the origin, faces +Z and has the size the game expects.
// Anything that fails to load is simply missing from the result, and the game
// falls back to the model built in code.
import * as THREE from '../vendor/three/three.module.js';
import { GLTFLoader } from '../vendor/three/addons/GLTFLoader.js';
import { mergeGeometries } from '../vendor/three/addons/BufferGeometryUtils.js';

// size: [axis, world units]. yaw: turn (radians) applied so the model faces +Z.
export const SPEC = {
  person_red: { size: ['y', 1.32], yaw: 0, align: 'x' },
  person_blue: { size: ['y', 1.32], yaw: 0, align: 'x' },
  zebra: { size: ['y', 1.75], yaw: 0, align: 'z' },
  wildebeest: { size: ['y', 1.6], yaw: 0, align: 'z' },
  gazelle: { size: ['y', 1.5], yaw: 0, align: 'z' },
  elephant: { size: ['y', 3.2], yaw: 0, align: 'z' },
  giraffe: { size: ['y', 4.6], yaw: -0.35, align: 'z' },
  lion: { size: ['y', 1.35], yaw: 0, align: 'z' },
  vulture: { size: ['x', 2.4], yaw: Math.PI, align: 'x' },
  acacia_a: { size: ['y', 5.6], yaw: 0 },
  acacia_b: { size: ['y', 6.2], yaw: 0 },
  baobab: { size: ['y', 6.4], yaw: 0 },
  bush: { size: ['x', 1.9], yaw: 0 },
  rock_a: { size: ['x', 2.6], yaw: 0 },
  rock_b: { size: ['y', 1.9], yaw: 0 },
  shelter: { size: ['x', 2.6], yaw: 0 },
  hut: { size: ['y', 2.9], yaw: 0 },
  house: { size: ['x', 3.2], yaw: 0 },
  stone_house: { size: ['y', 4.6], yaw: 0 },
  hall: { size: ['x', 7.6], yaw: 0 },
  granary: { size: ['y', 3.0], yaw: 0 },
  tower: { size: ['y', 6.6], yaw: 0 },
  totem: { size: ['y', 4.6], yaw: 0 },
  stall: { size: ['x', 2.6], yaw: 0 },
  bonfire: { size: ['x', 1.8], yaw: 0 },
  crocodile: { size: ['z', 2.2], yaw: 0, align: 'z' },
  hyena: { size: ['y', 1.0], yaw: 0, align: 'z' },
  stump: { size: ['x', 1.0], yaw: 0 },
  quarry: { size: ['x', 9], yaw: 0 },
  lumber: { size: ['x', 1.6], yaw: 0 },
  tower_block: { size: ['y', 16], yaw: 0 },
  apartment: { size: ['y', 8], yaw: 0 },
};

export async function loadAssets(names = Object.keys(SPEC), base = 'assets/models/') {
  const loader = new GLTFLoader();
  const found = {};
  await Promise.all(names.map(async (name) => {
    try {
      const gltf = await loader.loadAsync(`${base}${name}.glb`);
      const geos = [];
      let map = null;
      gltf.scene.updateMatrixWorld(true);
      gltf.scene.traverse((o) => {
        if (!o.isMesh) return;
        const g = o.geometry.clone().applyMatrix4(o.matrixWorld);
        for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
        if (!g.attributes.normal) g.computeVertexNormals();
        geos.push(g);
        if (!map && o.material && o.material.map) map = o.material.map;
      });
      if (!geos.length) return;
      const geo = geos.length === 1 ? geos[0] : mergeGeometries(geos, false);
      const spec = SPEC[name] || { size: ['y', 1], yaw: 0 };
      // The generator keeps the three-quarter pose of the reference picture, so creatures come
      // out turned by some unknown angle. Find the long horizontal axis of the body (principal
      // axis of the footprint) and line it up with z (animals) or x (shoulders, wingspan);
      // `yaw` then only has to say whether the head ended up at the front or the back.
      if (spec.align) {
        const pos = geo.attributes.position;
        let mx = 0, mz = 0;
        for (let i = 0; i < pos.count; i++) { mx += pos.getX(i); mz += pos.getZ(i); }
        mx /= pos.count; mz /= pos.count;
        let cxx = 0, czz = 0, cxz = 0;
        for (let i = 0; i < pos.count; i++) { const x = pos.getX(i) - mx, z = pos.getZ(i) - mz; cxx += x * x; czz += z * z; cxz += x * z; }
        const phi = 0.5 * Math.atan2(2 * cxz, cxx - czz);
        geo.rotateY(spec.align === 'z' ? phi - Math.PI / 2 : phi);
      }
      if (spec.yaw) geo.rotateY(spec.yaw);
      geo.computeBoundingBox();
      const bb = geo.boundingBox, sz = new THREE.Vector3(); bb.getSize(sz);
      const k = spec.size[1] / sz[spec.size[0]];
      geo.translate(-(bb.min.x + bb.max.x) / 2, -bb.min.y, -(bb.min.z + bb.max.z) / 2);
      geo.scale(k, k, k);
      geo.computeBoundingBox(); geo.computeBoundingSphere();
      if (map) { map.colorSpace = THREE.SRGBColorSpace; map.anisotropy = 4; }
      const mat = new THREE.MeshStandardMaterial({ map, roughness: 0.86, metalness: 0 });
      found[name] = { geo, mat, size: geo.boundingBox.getSize(new THREE.Vector3()), tris: (geo.index ? geo.index.count : geo.attributes.position.count) / 3 };
    } catch (e) { /* not generated yet: the code-built model is used instead */ }
  }));
  const out = {};
  for (const n of names) if (found[n]) out[n] = found[n];      // keep a stable order
  return out;
}
