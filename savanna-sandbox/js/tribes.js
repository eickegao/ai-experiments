// Two tribes: people forage, hunt, farm and build; villages grow through four eras; war.
import * as THREE from '../vendor/three/three.module.js';
import { clamp, toyMaterial } from './util.js';
import { N } from './terrain.js';
import { CreatureKind } from './creatures.js';
import { moveToward, settle, faceTo } from './agents.js';
import { SPEC } from './animals.js';
import * as MD from './models.js';

const HOUSE_CAP = [0, 4, 5, 6, 8];
const ERA_POP = [0, 30, 70, 120, 9999];        // population needed to leave each era
const WORK = { house: 7, granary: 8, totem: 6, field: 6, tower: 12, wall: 26, hall: 34, stall: 5, bonfire: 1 };
const MAX_POP = 230;
const WALL_R = 25;

export function createTribes(G) {
  const { stage, terrain: T, rng, villages } = G;
  const scene = stage.scene;
  const mat = toyMaterial();
  const glowMat = new THREE.MeshBasicMaterial({ vertexColors: true, toneMapped: false });
  const personKind = (id) => {
    const a = G.assets[id ? 'person_blue' : 'person_red'];
    if (!a) return new CreatureKind(scene, MD.humanParts(id), 300);
    // generated body; spear, shield and head basket stay as code-built parts
    const extras = MD.humanParts(id).filter(pt => pt.kind === 'spear' || pt.kind === 'shield' || pt.kind === 'carry');
    return new CreatureKind(scene, [{ kind: 'body', pivot: [0, 0, 0], phase: 0, geo: a.geo, material: a.mat }, ...extras], 300, { hop: 0.1 });
  };
  const kinds = [personKind(0), personKind(1)];
  const S = { tribes: [], people: [], kinds, war: null, peace: 60 };
  let nextId = 1000;

  const modelCache = {};
  const model = (key, make) => modelCache[key] || (modelCache[key] = make());
  const EMPTY = new THREE.BufferGeometry();
  // Generated building if there is one; the second tribe gets a cool tint so the two towns differ.
  const gen = (asset, tr, make) => {
    const a = G.assets[asset];
    if (!a) return make();
    let m = a.mat;
    if (tr === 1) { m = a.mat.clone(); m.color.set('#a9bdf2'); }
    return { geo: a.geo, glow: EMPTY, mat: m };
  };
  const houseModel = (tr, era) => model(`house${tr}${era}`, () => gen([null, 'shelter', 'hut', 'house', 'stone_house'][era], tr, () => [null, MD.shelterModel, MD.hutModel, MD.houseModel, MD.stoneHouseModel][era](tr)));

  // ------------------------------------------------------------ village layout
  villages.forEach((v, id) => {
    const gate = Math.atan2(N / 2 - v.z, N / 2 - v.x);
    const back = gate + Math.PI;
    const diff = (a, b) => { let d = Math.abs(a - b) % (Math.PI * 2); return d > Math.PI ? Math.PI * 2 - d : d; };
    const slots = [];
    for (const [r, n, off] of [[5.6, 7, 0.2], [9.0, 11, 0.5], [12.6, 15, 0.1], [16.2, 19, 0.4], [19.8, 23, 0.25]]) {
      for (let i = 0; i < n; i++) {
        const a = off + (i / n) * Math.PI * 2;
        if (diff(a, gate) < (r < 7 ? 0.55 : r < 10 ? 0.4 : 0.26)) continue;
        if (r < 10 && diff(a, back) < (r < 7 ? 1.2 : 0.62)) continue;
        slots.push({ x: v.x + Math.cos(a) * r, z: v.z + Math.sin(a) * r, used: null });
      }
    }
    const at = (r, a) => ({ x: v.x + Math.cos(a) * r, z: v.z + Math.sin(a) * r });
    const tribe = {
      id, x: v.x, z: v.z, gate, era: 1, food: 60, people: [], buildings: [], queue: [], slots,
      rally: at(31, gate), spots: {
        granary: at(3.1, gate + 2.1), totem: at(3.0, gate - 2.1), tower: at(22.5, gate + 0.3), hall: at(5.6, back),
        stalls: [at(3.4, gate + 0.75), at(3.4, gate - 0.75), at(6.6, gate + 1.25)],
        fields: [1.0, -1.0, 1.7, -1.7, 2.4, -2.4, 0.5, -0.5, 3.1].map(d => at(30.5, gate + d)).filter(f => T.inside(f.x, f.z, 4) && T.depth(f.x, f.z) < -0.3),
      },
      birth: 6, starve: 0, plan: 1, parties: [], cheer: 0, deaths: 0,
    };
    S.tribes.push(tribe);
  });

  // ------------------------------------------------------------ buildings
  const addBuilding = (tribe, type, x, z, extra = {}) => {
    const b = { tribe, type, x, z, era: tribe.era, built: 0, work: 0, need: WORK[type], state: 'site', yaw: Math.atan2(tribe.x - x, tribe.z - z), burn: 0, ...extra };
    b.mesh = new THREE.Mesh(new THREE.BufferGeometry(), mat);
    b.mesh.castShadow = b.mesh.receiveShadow = true;
    b.glow = new THREE.Mesh(new THREE.BufferGeometry(), glowMat);
    scene.add(b.mesh, b.glow);
    setModel(b);
    tribe.buildings.push(b);
    tribe.queue.push(b);
    if (G.flora && type !== 'wall') G.flora.clear(x, z, type === 'hall' ? 5 : type === 'field' ? 3.4 : 2.4);
    return b;
  };
  const setModel = (b) => {
    const tr = b.tribe.id;
    let m;
    switch (b.type) {
      case 'house': m = houseModel(tr, b.era); break;
      case 'bonfire': m = model('bonfire', () => gen('bonfire', 0, MD.bonfireModel)); break;
      case 'granary': m = model('granary' + tr, () => gen('granary', tr, () => MD.granaryModel(tr))); break;
      case 'totem': m = model(`totem${tr}${b.era}`, () => gen('totem', tr, () => MD.totemModel(tr, b.era))); break;
      case 'field': m = model('field', MD.fieldModel); break;
      case 'tower': m = model('tower' + tr, () => gen('tower', tr, () => MD.towerModel(tr))); break;
      case 'hall': m = model('hall' + tr, () => gen('hall', tr, () => MD.hallModel(tr))); break;
      case 'stall': m = model(`stall${tr}${b.v}`, () => gen('stall', tr, () => MD.stallModel(tr, b.v))); break;
      case 'wall': m = model(`wall${tr}${b.era}`, () => MD.wallModel(tr, b.era, WALL_R, b.tribe.gate)); break;
    }
    b.mesh.geometry = m.geo; b.glow.geometry = m.glow; b.mesh.material = m.mat || mat;
    if (b.type === 'wall') b.yaw = 0;
    if (b.type === 'field') b.yaw = b.tribe.gate;
  };
  const removeBuilding = (b) => {
    scene.remove(b.mesh, b.glow);
    const t = b.tribe;
    let i = t.buildings.indexOf(b); if (i >= 0) t.buildings.splice(i, 1);
    i = t.queue.indexOf(b); if (i >= 0) t.queue.splice(i, 1);
    if (b.slot) b.slot.used = null;
  };
  const destroy = (b, cause) => {
    G.fx.burst(b.x, T.height(b.x, b.z) + 1, b.z, b.era >= 4 ? '#cfc5b3' : '#c9a06a', 30, 1.2);
    G.fx.puff(b.x, T.height(b.x, b.z) + 0.6, b.z, '#d8c7a4', 14, 2.5);
    G.log('building_lost', { tribe: b.tribe.id, type: b.type, cause });
    removeBuilding(b);
  };
  const find = (tribe, type) => tribe.buildings.find(b => b.type === type);
  const count = (tribe, type) => tribe.buildings.filter(b => b.type === type).length;
  const capacity = (tribe) => tribe.buildings.reduce((s, b) => s + (b.type === 'house' && b.state === 'done' ? HOUSE_CAP[b.era] : 0), 0);

  // What should exist right now? Queue whatever is missing or out of date.
  const planTribe = (t) => {
    const pop = t.people.length;
    if (!find(t, 'bonfire')) { const b = addBuilding(t, 'bonfire', t.x, t.z); b.built = 1; b.state = 'done'; t.queue.pop(); }
    const houses = t.buildings.filter(b => b.type === 'house');
    const cap = HOUSE_CAP[t.era];
    const want = Math.min(t.slots.length, Math.ceil((pop + 3) / cap));
    const pending = t.queue.filter(b => b.type === 'house' && b.state !== 'done').length;
    if (houses.length < want && pending < 4) {
      const slot = t.slots.find(s => !s.used);
      if (slot) { const b = addBuilding(t, 'house', slot.x, slot.z, { slot }); slot.used = b; }
    }
    // upgrades, a couple at a time
    let upgrading = t.queue.filter(b => b.upgrading).length;
    for (const b of t.buildings) {
      if (upgrading >= 5) break;
      if ((b.type === 'house' || b.type === 'totem' || b.type === 'wall') && b.state === 'done' && b.era < t.era && !(b.type === 'wall' && t.era < 4)) {
        b.era = t.era; b.upgrading = true; b.state = 'site'; b.work = 0; b.built = 0.25; setModel(b); t.queue.push(b); upgrading++;
      }
    }
    const sp = t.spots;
    if (t.era >= 2) {
      if (!find(t, 'totem')) addBuilding(t, 'totem', sp.totem.x, sp.totem.z);
      if (!find(t, 'granary')) addBuilding(t, 'granary', sp.granary.x, sp.granary.z);
      const nf = count(t, 'field');
      if (nf < Math.min(sp.fields.length, t.era * 2) && !t.queue.some(b => b.type === 'field')) addBuilding(t, 'field', sp.fields[nf].x, sp.fields[nf].z);
    }
    if (t.era >= 3) {
      if (!find(t, 'wall')) addBuilding(t, 'wall', t.x, t.z);
      if (!find(t, 'tower')) addBuilding(t, 'tower', sp.tower.x, sp.tower.z);
    }
    if (t.era >= 4) {
      if (!find(t, 'hall')) addBuilding(t, 'hall', sp.hall.x, sp.hall.z);
      const ns = count(t, 'stall');
      if (ns < 3 && !t.queue.some(b => b.type === 'stall')) addBuilding(t, 'stall', sp.stalls[ns].x, sp.stalls[ns].z, { v: ns + t.id });
    }
    // next era?
    if (t.era < 4 && pop >= ERA_POP[t.era] && t.food > pop && houses.length && houses.every(b => b.era === t.era && b.state === 'done')) {
      t.era++;
      t.cheer = 5;
      G.log('era', { tribe: t.id, era: t.era });
      G.ui && G.ui.toast('era', t);
      for (let i = 0; i < 4; i++) G.fx.burst(t.x + rng.range(-3, 3), T.height(t.x, t.z) + 2.5, t.z + rng.range(-3, 3), i % 2 ? MD.TRIBES[t.id].cloth : MD.TRIBES[t.id].accent, 16, 1.3);
    }
  };

  // ------------------------------------------------------------ people
  const addPerson = (t, x, z, child = false) => {
    const p = {
      id: nextId++, tribe: t, x, z, y: T.ground(x, z), yaw: rng.range(0, 6.28), scale: child ? 0.45 : 0.86 * rng.range(0.94, 1.06), full: 0.86 * rng.range(0.94, 1.06),
      gait: rng.range(0, 6), amp: 0, stride: 6.5, role: child ? 'child' : 'idle', state: 'idle', timer: rng.range(0, 3), hp: 3, alive: true,
      spear: false, shield: false, carry: false, attack: 0, cheer: 0, bob: 0, cd: 0,
    };
    p.tx = x; p.tz = z;
    t.people.push(p); S.people.push(p); kinds[t.id].list.push(p);
    return p;
  };
  const removePerson = (p) => {
    p.alive = false;
    const t = p.tribe;
    let i = t.people.indexOf(p); if (i >= 0) t.people.splice(i, 1);
    i = S.people.indexOf(p); if (i >= 0) S.people.splice(i, 1);
    i = kinds[t.id].list.indexOf(p); if (i >= 0) kinds[t.id].list.splice(i, 1);
    if (p.bush) p.bush.taken = null;
    if (p.haul) { p.haul.taken = null; p.haul.carried = false; p.haul.x = p.x; p.haul.z = p.z; }
  };
  S.kill = (p, cause) => {
    if (!p.alive) return;
    removePerson(p);
    p.tribe.deaths++;
    G.log('death', { tribe: p.tribe.id, cause });
    G.fx.burst(p.x, p.y + 0.7, p.z, cause === 'starve' ? '#9c8f80' : MD.TRIBES[p.tribe.id].cloth, 10);
    G.fx.burst(p.x, p.y + 0.9, p.z, '#6a4630', 6);
  };
  S.killAt = (x, z, r, cause) => { for (const p of [...S.people]) if (Math.hypot(p.x - x, p.z - z) < r) S.kill(p, cause); };
  S.destroyAt = (x, z, r, cause) => {
    for (const t of S.tribes) for (const b of [...t.buildings]) if (b.type !== 'wall' && b.type !== 'bonfire' && Math.hypot(b.x - x, b.z - z) < r) destroy(b, cause);
  };

  for (const t of S.tribes) {
    for (let i = 0; i < 18; i++) { const a = rng.range(0, 6.28), r = rng.range(1.5, 7.5); addPerson(t, t.x + Math.cos(a) * r, t.z + Math.sin(a) * r); }
    planTribe(t);
    // Start with two finished shelters so the camp does not look empty.
    for (let i = 0; i < 6; i++) { planTribe(t); for (const b of t.buildings) if (b.type === 'house') { b.built = 1; b.state = 'done'; } t.queue.length = 0; }
  }

  const adults = (t) => t.people.filter(p => p.role !== 'child');
  const idleSpot = (p) => { const a = rng.range(0, 6.28), r = rng.range(1.6, 4.4 + Math.sqrt(p.tribe.people.length) * 0.9); p.tx = p.tribe.x + Math.cos(a) * r; p.tz = p.tribe.z + Math.sin(a) * r; };
  const goHome = (p) => { p.state = 'home'; const a = rng.range(0, 6.28); p.tx = p.tribe.x + Math.cos(a) * 2.6; p.tz = p.tribe.z + Math.sin(a) * 2.6; };
  const release = (p) => { p.role = 'idle'; p.state = 'idle'; p.spear = false; p.shield = false; p.timer = rng.range(0.5, 2); p.party = null; p.site = null; if (p.bush) { p.bush.taken = null; p.bush = null; } idleSpot(p); };

  // ------------------------------------------------------------ jobs
  const assignJobs = (t) => {
    const night = stage.night > 0.6;
    const idle = t.people.filter(p => p.role === 'idle' && !p.carry);
    if (S.war || night || !idle.length) return;
    const all = adults(t);
    const cnt = (role) => all.filter(p => p.role === role).length;

    const sites = t.queue.filter(b => b.state !== 'done');
    let builders = cnt('builder');
    const wantB = sites.length ? clamp(Math.ceil(all.length / 5), 1, 16) : 0;
    while (builders < wantB && idle.length) { const p = idle.pop(); p.role = 'builder'; p.state = 'toSite'; p.site = null; builders++; }

    const fields = t.buildings.filter(b => b.type === 'field' && b.state === 'done');
    let farmers = cnt('farmer');
    while (farmers < fields.length * 2 && idle.length) { const p = idle.pop(); p.role = 'farmer'; p.state = 'toField'; p.field = fields[farmers % fields.length]; farmers++; }

    // a hunting party of three
    t.parties = t.parties.filter(pt => pt.members.some(m => m.alive && m.party === pt));
    const wantParties = clamp(Math.floor(all.length / 14), 1, 6);
    if (t.parties.length < wantParties && idle.length >= 3) {
      const prey = G.animals.nearestPrey(t.x, t.z, 95, a => !a.hunted);
      if (prey) {
        const party = { members: [], prey, timer: 55, state: 'hunt' };
        prey.hunted = true;
        for (let i = 0; i < 3; i++) { const p = idle.pop(); p.role = 'hunter'; p.state = 'hunt'; p.spear = true; p.party = party; p.cd = rng.range(0.5, 1.5); party.members.push(p); }
        t.parties.push(party);
      }
    }
    for (const p of idle) { p.role = 'gatherer'; p.state = 'seek'; }
  };

  const nearestBush = (p) => {
    let best = null, bd = 90 * 90 * 1.6;
    for (const b of G.flora.bushes) {
      if (!b.alive || !b.berries || b.taken) continue;
      const d = (b.x - p.x) ** 2 + (b.z - p.z) ** 2 + ((b.x - p.tribe.x) ** 2 + (b.z - p.tribe.z) ** 2) * 0.5;
      if (d < bd) { bd = d; best = b; }
    }
    return best;
  };

  const deposit = (p, amount) => {
    p.tribe.food += amount;
    p.carry = false;
    G.fx.puff(p.x, p.y + 1.2, p.z, '#f3cf63', 3, 0.6);
  };

  const WALK = 2.3, RUN = 3.7;

  const updatePerson = (p, dt) => {
    const t = p.tribe;
    p.attack = Math.max(0, p.attack - dt * 3);
    p.cd -= dt;
    p.bob += (0 - p.bob) * Math.min(1, dt * 8);
    p.cheer = t.cheer > 0 && p.role !== 'warrior' ? 1 : Math.max(0, p.cheer - dt * 2);
    if (p.cheer > 0.5 && p.state !== 'fight') { p.bob = Math.abs(Math.sin(G.time * 9 + p.id)) * 0.3; p.gait += dt * 6; settle(T, p, dt); if (t.cheer > 0) return; }
    if (T.fire[T.cell(p.x, p.z)] > 0) { p.hp -= dt * 2.5; if (p.hp <= 0) { S.kill(p, 'fire'); return; } }

    if (p.role === 'child') {
      if (p.scale < p.full) p.scale += dt * 0.014; else { release(p); return; }
      p.timer -= dt;
      if (p.timer <= 0) { p.timer = rng.range(1.5, 4); idleSpot(p); }
      moveToward(T, p, p.tx, p.tz, WALK * 1.1, dt);
      return;
    }

    const night = stage.night > 0.6;
    if (night && !S.war && (p.role === 'gatherer' || p.role === 'farmer' || p.role === 'idle' || p.role === 'builder') && p.state !== 'fire' && p.state !== 'home' && p.state !== 'toFire') {
      if (p.bush) { p.bush.taken = null; p.bush = null; }
      p.role = 'idle'; goHome(p); p.state = 'toFire'; p.site = null;
      const a = (p.id * 2.399) % 6.28, rr = 2.4 + ((p.id * 7) % 5) * 0.9; p.tx = t.x + Math.cos(a) * rr; p.tz = t.z + Math.sin(a) * rr;
    }

    switch (p.role) {
      case 'idle': {
        if (p.state === 'toFire') {
          if (moveToward(T, p, p.tx, p.tz, WALK, dt) < 0.3) p.state = 'fire';
        } else if (p.state === 'fire') {
          faceTo(p, t.x, t.z, dt); settle(T, p, dt);
          p.bob = Math.abs(Math.sin(G.time * 6 + p.id)) * 0.22; p.cheer = 0.9; p.gait += dt * 5;
          if (!night) { p.state = 'idle'; p.cheer = 0; }
        } else if (p.state === 'home') {
          if (moveToward(T, p, p.tx, p.tz, p.carry ? WALK : WALK * 1.1, dt) < 0.5) {
            if (p.carry) deposit(p, p.load || 0);
            p.state = 'idle'; p.timer = rng.range(0.4, 1.5); idleSpot(p);
          }
        } else {
          p.timer -= dt;
          if (moveToward(T, p, p.tx, p.tz, WALK * 0.8, dt) < 0.3 && p.timer <= 0) { p.timer = rng.range(1, 4); idleSpot(p); }
        }
        break;
      }
      case 'gatherer': {
        if (p.state === 'seek') {
          const b = nearestBush(p);
          if (b) { b.taken = p; p.bush = b; p.state = 'toBush'; }
          else { const a = rng.range(0, 6.28), r = rng.range(28, 46); p.tx = clamp(t.x + Math.cos(a) * r, 3, N - 3); p.tz = clamp(t.z + Math.sin(a) * r, 3, N - 3); p.state = 'forage'; }
        } else if (p.state === 'toBush') {
          const b = p.bush;
          if (!b || !b.alive || !b.berries) { if (b) b.taken = null; p.bush = null; p.state = 'seek'; break; }
          if (moveToward(T, p, b.x, b.z, WALK, dt) < 0.9) { p.state = 'pick'; p.timer = 1.8; }
        } else if (p.state === 'forage') {
          if (moveToward(T, p, p.tx, p.tz, WALK, dt) < 0.6) { p.state = 'pick'; p.timer = 3.2; }
        } else if (p.state === 'pick') {
          settle(T, p, dt); p.timer -= dt; p.bob = -Math.abs(Math.sin(G.time * 8)) * 0.12; p.attack = 0.5 + Math.sin(G.time * 10) * 0.4;
          if (p.timer <= 0) {
            const b = p.bush;
            if (b) { b.berries = false; b.regrow = rng.range(45, 80); b.taken = null; G.flora.placeBush(b); p.bush = null; p.load = 5; }
            else p.load = T.grass[T.cell(p.x, p.z)] > 0.3 ? 2 : 0.5;
            p.carry = true; p.role = 'idle'; goHome(p);
          }
        }
        break;
      }
      case 'farmer': {
        const f = p.field;
        if (!f || !t.buildings.includes(f)) { release(p); break; }
        if (p.state === 'toField') {
          if (p.tx === undefined || p.fieldSet !== f) { p.fieldSet = f; p.tx = f.x + rng.range(-1.6, 1.6); p.tz = f.z + rng.range(-1.2, 1.2); }
          if (moveToward(T, p, p.tx, p.tz, WALK, dt) < 0.4) { p.state = 'farm'; p.timer = rng.range(8, 13); }
        } else if (p.state === 'farm') {
          settle(T, p, dt); p.timer -= dt;
          p.bob = -Math.abs(Math.sin(G.time * 5 + p.id)) * 0.14; p.attack = 0.4 + Math.sin(G.time * 5 + p.id) * 0.4;
          if (p.timer <= 0) { p.load = G.env.drought ? 1.5 : 7; p.carry = true; p.role = 'idle'; p.fieldSet = null; goHome(p); }
        }
        break;
      }
      case 'builder': {
        if (!p.site || p.site.state === 'done' || !t.buildings.includes(p.site)) {
          const open = t.queue.filter(b => b.state !== 'done');
          if (!open.length) { release(p); break; }
          p.site = open[p.id % Math.min(open.length, 5)];
          p.state = 'toSite';
          const a = rng.range(0, 6.28), r = p.site.type === 'wall' ? WALL_R + 0.9 : p.site.type === 'hall' ? 4.6 : 2.0;
          p.tx = p.site.x + Math.cos(a) * r; p.tz = p.site.z + Math.sin(a) * r;
        }
        if (p.state === 'toSite') {
          if (moveToward(T, p, p.tx, p.tz, WALK, dt) < 0.5) p.state = 'build';
        } else {
          settle(T, p, dt); faceTo(p, p.site.x, p.site.z, dt);
          p.attack = 0.5 + Math.sin(G.time * 9 + p.id) * 0.5;
          p.site.work += dt;
          if (rng() < dt * 1.2) G.fx.puff(p.site.x + rng.range(-1, 1), T.height(p.site.x, p.site.z) + 0.3, p.site.z + rng.range(-1, 1), '#e0cfa8', 2, 0.8);
        }
        break;
      }
      case 'hunter': updateHunter(p, dt); break;
      case 'warrior': updateWarrior(p, dt); break;
    }
  };

  const updateHunter = (p, dt) => {
    const pt = p.party;
    if (!pt) { release(p); return; }
    if (p.state === 'hunt') {
      const prey = pt.prey;
      if (!prey || !prey.alive || pt.timer <= 0) {
        if (prey) prey.hunted = false;
        const next = pt.timer > 0 && G.animals.nearestPrey(p.x, p.z, 22, a => !a.hunted);
        if (next) { pt.prey = next; next.hunted = true; }
        else { for (const m of pt.members) if (m.alive && m.state === 'hunt') { m.spear = false; m.role = 'idle'; m.party = null; goHome(m); } }
        return;
      }
      const d = Math.hypot(prey.x - p.x, prey.z - p.z);
      const i = pt.members.indexOf(p);
      if (d > 6.5) moveToward(T, p, prey.x + Math.cos(i * 2.1) * 2.5, prey.z + Math.sin(i * 2.1) * 2.5, d > 16 ? RUN * 0.9 : WALK * 1.15, dt);
      else {
        settle(T, p, dt); faceTo(p, prey.x, prey.z, dt);
        if (p.cd <= 0) {
          p.cd = 1.7; p.attack = 1;
          G.fx.lit.add({ x: p.x, y: p.y + 1.5, z: p.z, vx: (prey.x - p.x) / 0.4, vy: 2.2, vz: (prey.z - p.z) / 0.4, grav: 11, life: 0.4, max: 0.4, size: 0.09, sx: 1, sy: 1, spin: 0, r: 0.4, g: 0.3, b: 0.2 });
          if (rng() < 0.6) {
            prey.hp--;
            G.animals.scare(prey.x, prey.z, 4);
            if (prey.hp <= 0) {
              const car = G.animals.kill(prey, 'hunt');
              G.log('hunt_kill', { tribe: p.tribe.id, kind: prey.kind });
              if (car) { car.taken = 'tribe'; p.state = 'toCarcass'; p.haul = car; }
              for (const m of pt.members) if (m !== p && m.alive) { m.spear = false; m.role = 'idle'; m.party = null; goHome(m); }
            }
          }
        }
      }
    } else if (p.state === 'toCarcass') {
      const c = p.haul;
      if (moveToward(T, p, c.x, c.z, WALK * 1.2, dt) < 0.8) { c.gone = true; p.haul = null; p.load = c.meat * 2; p.carry = true; p.spear = false; p.role = 'idle'; p.party = null; goHome(p); }
    }
  };

  // ------------------------------------------------------------ war
  S.startWar = () => {
    if (S.war) return false;
    const war = { t: 0, phase: 'rally', sides: [], done: false };
    for (const t of S.tribes) {
      for (const pt of t.parties) if (pt.prey) pt.prey.hunted = false;
      t.parties = [];
      const list = adults(t).filter(p => !p.carry);
      const n = Math.max(Math.min(list.length, 3), Math.floor(list.length * 0.72));
      const ws = list.slice(0, n);
      ws.forEach((p, i) => {
        if (p.bush) { p.bush.taken = null; p.bush = null; }
        p.role = 'warrior'; p.state = 'rally'; p.spear = true; p.shield = true; p.party = null; p.hp = 5; p.target = null;
        const row = Math.floor(i / 14), colm = (i % 14) - 6.5;
        const ax = Math.cos(t.gate), az = Math.sin(t.gate);
        p.fx = t.rally.x - ax * row * 1.1 - az * colm * 1.0; p.fz = t.rally.z - az * row * 1.1 + ax * colm * 1.0;
      });
      war.sides.push({ tribe: t, start: ws.length, warriors: ws });
    }
    S.war = war;
    G.log('war_start');
    G.ui && G.ui.toast('war');
    return true;
  };
  const endWar = (winner) => {
    const war = S.war;
    for (const side of war.sides) for (const p of side.warriors) if (p.alive) { p.shield = false; p.spear = false; p.role = 'idle'; p.target = null; goHome(p); if (side.tribe === winner) p.cheer = 3; }
    if (winner) winner.cheer = 4;
    G.log('war_end', { winner: winner ? winner.id : -1 });
    G.ui && G.ui.toast('peace', winner);
    S.war = null; S.peace = 90;
  };
  const updateWar = (dt) => {
    const war = S.war;
    war.t += dt;
    for (const s of war.sides) s.warriors = s.warriors.filter(p => p.alive);
    if (war.phase === 'rally' && war.t > 11) { war.phase = 'march'; G.log('war_march'); }
    if (war.phase !== 'rally') {
      const [a, b] = war.sides;
      const lost = (s) => s.warriors.length <= Math.max(0, Math.floor(s.start * 0.25));
      if (lost(a) || lost(b) || war.t > 300) endWar(lost(a) && lost(b) ? null : lost(a) ? b.tribe : lost(b) ? a.tribe : null);
    }
  };
  const updateWarrior = (p, dt) => {
    const war = S.war;
    if (!war) { release(p); return; }
    if (war.phase === 'rally') {
      if (moveToward(T, p, p.fx, p.fz, RUN * 0.8, dt) < 0.4) { faceTo(p, N / 2, N / 2, dt); p.bob = Math.abs(Math.sin(G.time * 7 + p.id)) * 0.12; }
      return;
    }
    const enemy = war.sides.find(s => s.tribe !== p.tribe);
    p.scan = (p.scan || 0) - dt;
    if (p.scan <= 0 || !p.target || !p.target.alive) {
      p.scan = 0.5; p.target = null;
      let bd = 1e9;
      for (const e of enemy.warriors) { const d = (e.x - p.x) ** 2 + (e.z - p.z) ** 2; if (d < bd) { bd = d; p.target = e; } }
    }
    const e = p.target;
    if (!e) { moveToward(T, p, enemy.tribe.rally.x, enemy.tribe.rally.z, WALK * 1.25, dt); return; }
    const d = Math.hypot(e.x - p.x, e.z - p.z);
    if (d > 1.15) moveToward(T, p, e.x, e.z, d < 12 ? RUN : WALK * 1.3, dt);
    else {
      settle(T, p, dt); faceTo(p, e.x, e.z, dt);
      p.state = 'fight';
      if (p.cd <= 0) {
        p.cd = rng.range(0.7, 1.1); p.attack = 1;
        if (rng() < 0.5) {
          e.hp--;
          G.fx.spark(e.x, e.y + 0.9, e.z, 3, '#fff0c2', 0.5);
          if (e.hp <= 0) S.kill(e, 'war');
        } else G.fx.puff(e.x, e.y + 0.8, e.z, '#e9dfc8', 2, 0.5);
      }
    }
  };

  // ------------------------------------------------------------ per-tribe tick
  const updateTribe = (t, dt) => {
    const pop = t.people.length;
    t.cheer = Math.max(0, t.cheer - dt);
    t.food -= pop * 0.03 * dt;
    if (t.food <= 0) {
      t.food = 0; t.starve += dt;
      if (t.starve > 11 && pop > 2) { t.starve = 0; S.kill(rng.pick(t.people), 'starve'); }
    } else t.starve = Math.max(0, t.starve - dt);

    t.birth -= dt;
    if (t.birth <= 0) {
      t.birth = rng.range(1.6, 3.2) * (pop > 120 ? 1.6 : 1);
      if (pop >= 2 && pop < MAX_POP && pop < capacity(t) && t.food > 6 + pop * 1.2 && !S.war) {
        const h = rng.pick(t.buildings.filter(b => b.type === 'house' && b.state === 'done'));
        if (h) { addPerson(t, h.x + rng.range(-0.6, 0.6), h.z + rng.range(-0.6, 0.6), true); t.food -= 4; G.log('birth', { tribe: t.id }); }
      }
    }
    t.plan -= dt;
    if (t.plan <= 0) { t.plan = 1.5; planTribe(t); assignJobs(t); }

    // construction progress and fire
    for (const b of [...t.buildings]) {
      if (b.state !== 'done') {
        const target = clamp(b.work / b.need, 0, 1);
        b.built = Math.max(b.built, target);
        if (target >= 1) {
          b.state = 'done'; b.built = 1; b.upgrading = false;
          const i = t.queue.indexOf(b); if (i >= 0) t.queue.splice(i, 1);
          G.fx.puff(b.x, T.height(b.x, b.z) + 0.5, b.z, '#efe2c0', 10, 2);
          G.log('built', { tribe: t.id, type: b.type, era: b.era });
        }
      }
      if (b.type === 'house' || b.type === 'granary' || b.type === 'tower' || b.type === 'stall') {
        const burning = T.fire[T.cell(b.x, b.z)] > 0;
        if (burning && b.era < 4 && !b.burn) b.burn = b.era >= 3 ? 7 : 4.5;
        if (b.burn) {
          b.burn -= dt;
          const y = T.height(b.x, b.z);
          for (let k = 0; k < 3; k++) G.fx.flame(b.x + rng.range(-1, 1), y + rng.range(0.5, 2.2), b.z + rng.range(-1, 1), 0.7);
          if (rng() < 0.12) G.fx.smoke(b.x, y + 2.5, b.z, 0.8);
          if (b.burn <= 0) destroy(b, 'fire');
        }
      }
    }
  };

  S.update = (dt) => {
    if (S.war) updateWar(dt); else S.peace -= dt;
    for (const t of S.tribes) updateTribe(t, dt);
    for (let i = S.people.length - 1; i >= 0; i--) { const p = S.people[i]; if (p) updatePerson(p, dt); }
    for (const t of S.tribes) for (const pt of t.parties) pt.timer -= dt;
  };

  // ------------------------------------------------------------ drawing
  const fireLights = S.tribes.map(t => { const l = new THREE.PointLight('#ff9a45', 0, 60, 1.5); scene.add(l); return l; });
  S.render = (dt, time) => {
    kinds[0].draw(); kinds[1].draw();
    const night = stage.night;
    glowMat.color.setScalar(0.25 + night * 1.0);
    S.tribes.forEach((t, i) => {
      const gy = T.height(t.x, t.z);
      const n = night > 0.3 ? 3 : 1;
      for (let k = 0; k < n; k++) if (G.fx.R() < 0.7) G.fx.flame(t.x, gy + 0.3, t.z, night > 0.3 ? 0.62 : 0.34);
      if (G.fx.R() < 0.05) G.fx.smoke(t.x, gy + 1.5, t.z, 0.22, 0.62);
      fireLights[i].position.set(t.x, gy + 2.2, t.z);
      fireLights[i].intensity = (6 + night * 240) * (0.85 + Math.sin(time * 19 + i * 3) * 0.1 + Math.sin(time * 7.3 + i) * 0.05);
      for (const b of t.buildings) {
        const y = T.height(b.x, b.z);
        const k = b.built;
        const e = 1 - (1 - k) * (1 - k);
        b.mesh.position.set(b.x, y - (b.type === 'field' ? 0.02 : 0.06), b.z);
        b.mesh.rotation.y = b.yaw;
        b.mesh.scale.set(1, Math.max(0.02, e), 1);
        b.glow.position.copy(b.mesh.position); b.glow.rotation.y = b.yaw; b.glow.scale.copy(b.mesh.scale);
        b.glow.visible = b.state === 'done' && (night > 0.15 || b.type === 'bonfire');
      }
    });
  };

  S.info = () => S.tribes.map(t => ({ id: t.id, era: t.era, pop: t.people.length, food: Math.round(t.food), houses: count(t, 'house'), cap: capacity(t) }));
  return S;
}
