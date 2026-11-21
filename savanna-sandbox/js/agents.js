// Movement shared by animals and people: walk towards a point, steer around deep
// water and the slab edge, wade through shallows, keep feet on the ground.
import { angDiff, clamp } from './util.js';
import { N } from './terrain.js';

// Town walls are rings with one gate. People plan around them: to get in or out they
// head for the gate; to pass a town they are not visiting they walk around it.
function routeAround(walls, a, tx, tz) {
  for (const w of walls) {
    const da = Math.hypot(a.x - w.x, a.z - w.z), dt = Math.hypot(tx - w.x, tz - w.z);
    const aIn = da < w.r, tIn = dt < w.r;
    const gx = Math.cos(w.gate), gz = Math.sin(w.gate);
    if (aIn !== tIn) {
      const ang = Math.abs(angDiff(Math.atan2(a.z - w.z, a.x - w.x), w.gate));
      const inCorridor = ang < w.gap * 0.55 && Math.abs(da - w.r) < 4.5;
      const k = (aIn ? (inCorridor ? 3 : -3) : (inCorridor ? -3 : 3.5));
      return [w.x + gx * (w.r + k), w.z + gz * (w.r + k)];
    }
    if (!aIn && da < w.r + 70) {
      // Would the straight line cut through the town? Then walk round the outside of the
      // ring, a stretch at a time, on whichever side is shorter.
      const dx = tx - a.x, dz = tz - a.z, len2 = dx * dx + dz * dz;
      if (len2 > 1) {
        const u = clamp(((w.x - a.x) * dx + (w.z - a.z) * dz) / len2, 0, 1);
        const od = Math.hypot(a.x + dx * u - w.x, a.z + dz * u - w.z);
        if (od < w.r + 1.5 && u > 0) {
          const ta = Math.atan2(a.z - w.z, a.x - w.x), tt = Math.atan2(tz - w.z, tx - w.x);
          const side = angDiff(ta, tt) >= 0 ? 1 : -1;
          const ang = ta + side * Math.min(0.7, 14 / da);
          return [w.x + Math.cos(ang) * (w.r + 5), w.z + Math.sin(ang) * (w.r + 5)];
        }
      }
    }
  }
  return null;
}

export function moveToward(T, a, tx, tz, speed, dt) {
  const walls = T.walls;
  if (a.human && walls.length) {
    const via = routeAround(walls, a, tx, tz);
    if (via) {
      const d = Math.hypot(tx - a.x, tz - a.z);
      stepToward(T, a, via[0], via[1], speed, dt);
      return Math.max(d, 2);
    }
  }
  return stepToward(T, a, tx, tz, speed, dt);
}

function stepToward(T, a, tx, tz, speed, dt) {
  const walls = T.walls;
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
  let nx = clamp(a.x + Math.sin(a.yaw) * step, 1, N - 1), nz = clamp(a.z + Math.cos(a.yaw) * step, 1, N - 1);
  // Nobody walks through a wall: crossing the ring is only allowed inside the gate gap.
  for (let i = 0; i < walls.length; i++) {
    const w = walls[i];
    const d0 = Math.hypot(a.x - w.x, a.z - w.z), d1 = Math.hypot(nx - w.x, nz - w.z);
    if ((d0 < w.r) === (d1 < w.r)) continue;
    const ang = Math.atan2(nz - w.z, nx - w.x);
    if (Math.abs(angDiff(ang, w.gate)) < w.gap) continue;
    const keep = d0 < w.r ? Math.min(d0, w.r - 0.3) : Math.max(d0, w.r + 0.3);
    nx = w.x + Math.cos(ang) * keep; nz = w.z + Math.sin(ang) * keep;      // slide along the wall
  }
  a.x = nx; a.z = nz;
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
