// Movement shared by animals and people: walk towards a point, steer around deep
// water and the slab edge, wade through shallows, keep feet on the ground.
import { angDiff, clamp } from './util.js';
import { N } from './terrain.js';

export function moveToward(T, a, tx, tz, speed, dt) {
  const dx = tx - a.x, dz = tz - a.z;
  const d = Math.hypot(dx, dz);
  if (d < 0.05 || speed <= 0) { settle(T, a, dt); return d; }
  let want = Math.atan2(dx, dz);
  // Probe ahead; if it is deep water or off the slab, try turning aside.
  const ok = (ang) => {
    const px = a.x + Math.sin(ang) * 1.6, pz = a.z + Math.cos(ang) * 1.6;
    return px > 1.2 && pz > 1.2 && px < N - 1.2 && pz < N - 1.2 && !T.isDeep(px, pz);
  };
  if (!ok(want)) {
    const side = a.side || (a.side = (a.id ?? 0) % 2 ? 1 : -1);
    let found = false;
    for (const k of [0.6, 1.1, 1.6, 2.2]) {
      if (ok(want + side * k)) { want += side * k; found = true; break; }
      if (ok(want - side * k)) { want -= side * k; a.side = -side; found = true; break; }
    }
    if (!found) want += Math.PI;
  }
  const turn = angDiff(a.yaw, want);
  a.yaw += clamp(turn, -7 * dt, 7 * dt);
  const wade = T.depth(a.x, a.z) > 0.15 ? 0.6 : 1;
  const v = speed * wade * (Math.abs(turn) > 1.5 ? 0.35 : 1);
  const step = Math.min(v * dt, d);
  a.x = clamp(a.x + Math.sin(a.yaw) * step, 1, N - 1);
  a.z = clamp(a.z + Math.cos(a.yaw) * step, 1, N - 1);
  a.gait += step * (a.stride || 5);
  a.amp += (clamp(0.35 + v * 0.14, 0, 1) - a.amp) * Math.min(1, dt * 8);
  a.y = T.ground(a.x, a.z);
  return d;
}

export function settle(T, a, dt) {
  a.amp += (0 - a.amp) * Math.min(1, dt * 6);
  a.y = T.ground(a.x, a.z);
}

export const faceTo = (a, x, z, dt) => {
  const want = Math.atan2(x - a.x, z - a.z);
  a.yaw += clamp(angDiff(a.yaw, want), -6 * dt, 6 * dt);
};
