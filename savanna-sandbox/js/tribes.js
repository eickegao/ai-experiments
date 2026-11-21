// Two peoples (red and blue). Each starts with one camp; people forage, hunt, farm,
// fell trees, quarry stone and build; a settlement grows through four eras, and a big
// town sends settlers out to found a new one. War drums set the two peoples against
// each other. Walls are real: everyone goes through the gate.
import * as THREE from '../vendor/three/three.module.js';
import { clamp, lerp, smooth, toyMaterial } from './util.js';
import { N, KOPJES } from './terrain.js';
import { CreatureKind } from './creatures.js';
import { moveToward, settle, faceTo } from './agents.js';
import * as MD from './models.js';

const HOUSE_CAP = [0, 4, 5, 6, 8, 9, 12];
const MAX_ERA = 6;
const ERA_POP = [0, 34, 78, 130, 180, 215, 9999];
// An age cannot begin before this day, however well a town is doing: the whole climb
// from campfire to skyline takes about sixteen days.
const ERA_DAY = [0, 2.6, 5.2, 8.2, 12, 16, 1e9];        // population needed to leave each era
const WORK = { factory: 30, house: 7, granary: 8, totem: 6, field: 6, tower: 12, wall: 26, hall: 34, stall: 5, bonfire: 1 };
// what a building costs: [wood, stone]
const HOUSE_COST = [null, [2, 0], [4, 0], [6, 3], [4, 10], [10, 12], [8, 30]];
const COST = { factory: [40, 60], granary: [6, 0], totem: [4, 0], field: [0, 0], tower: [12, 0], hall: [30, 80], stall: [5, 0], bonfire: [0, 0] };
const WALL_COST = { 3: [70, 0], 4: [20, 140] };
const MAX_POP = 230;
const WALL_R = 25;
const MAX_VILLAGES = 5;        // per people

export function createTribes(G) {
  const { stage, terrain: T, rng, villages } = G;
  const scene = stage.scene;
  const mat = toyMaterial();
  const glowMat = new THREE.MeshBasicMaterial({ vertexColors: true, toneMapped: false });
  const personKind = (color) => {
    const a = G.assets[color ? 'person_blue' : 'person_red'];
    if (!a) return new CreatureKind(scene, MD.humanParts(color), 700);
    // generated body; spear, shield and head basket stay as code-built parts
    const extras = MD.humanParts(color).filter(pt => pt.kind === 'spear' || pt.kind === 'shield' || pt.kind === 'carry');
    return new CreatureKind(scene, [{ kind: 'body', pivot: [0, 0, 0], phase: 0, geo: a.geo, material: a.mat }, ...extras], 700, { hop: 0.1 });
  };
  const kinds = [personKind(0), personKind(1)];
  const S = { tribes: [], people: [], kinds, war: null, peace: 60 };
  let nextId = 1000;
  const isNight = () => G.isNight();

  const modelCache = {};
  const model = (key, make) => modelCache[key] || (modelCache[key] = make());
  const EMPTY = new THREE.BufferGeometry();
  // Generated building if there is one; the blue people get a cool tint so the towns differ.
  const gen = (asset, tr, make) => {
    const a = G.assets[asset];
    if (!a) return make();
    let m = a.mat;
    if (tr === 1) { m = a.mat.clone(); m.color.set('#a9bdf2'); }
    return { geo: a.geo, glow: EMPTY, mat: m };
  };
  // From the industrial age on, towns look the same whoever built them (no tint).
  const houseModel = (tr, era, tall) => {
    const name = [null, 'shelter', 'hut', 'house', 'stone_house', 'townhouse', tall ? 'tower_block' : 'apartment'][era];
    return model(`house${era >= 5 ? '' : tr}${name}`, () => gen(name, era >= 5 ? 0 : tr, () => [null, MD.shelterModel, MD.hutModel, MD.houseModel, MD.stoneHouseModel, MD.stoneHouseModel, MD.stoneHouseModel][era](tr)));
  };

  // ------------------------------------------------------------ settlement layout
  const createVillage = (x, z, color, era, towards = null) => {
    const gate = towards ? Math.atan2(towards.z - z, towards.x - x) : Math.atan2(N / 2 - z, N / 2 - x);
    const back = gate + Math.PI;
    const diff = (a, b) => { let d = Math.abs(a - b) % (Math.PI * 2); return d > Math.PI ? Math.PI * 2 - d : d; };
    const slots = [];
    for (const [r, n, off] of [[5.6, 7, 0.2], [9.0, 11, 0.5], [12.6, 15, 0.1], [16.2, 19, 0.4], [19.8, 23, 0.25]]) {
      for (let i = 0; i < n; i++) {
        const a = off + (i / n) * Math.PI * 2;
        if (diff(a, gate) < (r < 7 ? 0.55 : r < 10 ? 0.4 : 0.3)) continue;
        if (r < 10 && diff(a, back) < (r < 7 ? 1.2 : 0.62)) continue;
        slots.push({ x: x + Math.cos(a) * r, z: z + Math.sin(a) * r, used: null });
      }
    }
    const at = (r, a) => ({ x: x + Math.cos(a) * r, z: z + Math.sin(a) * r });
    const t = {
      id: S.tribes.length, color, x, z, gate, era, food: 60, wood: 30, stone: 0, people: [], buildings: [], queue: [], slots,
      rally: at(33, gate), spots: {
        granary: at(3.1, gate + 2.1), totem: at(3.0, gate - 2.1), tower: at(22, gate + 0.42), hall: at(5.6, back),
        factories: [at(47, gate + 0.8), at(47, gate - 0.8), at(52, gate + 1.6)].filter(f => T.inside(f.x, f.z, 8) && T.depth(f.x, f.z) < -0.3),
        stalls: [at(3.4, gate + 0.75), at(3.4, gate - 0.75), at(6.6, gate + 1.25)],
        fields: [1.0, -1.0, 1.7, -1.7, 2.4, -2.4, 0.5, -0.5, 3.1].map(d => at(31.5, gate + d)).concat([0.75, -0.75, 1.4, -1.4, 2.1, -2.1, 2.8].map(d => at(38.5, gate + d))).filter(f => T.inside(f.x, f.z, 4) && T.depth(f.x, f.z) < -0.3),
      },
      birth: 6, starve: 0, plan: 1, parties: [], cheer: 0, deaths: 0, colonyCd: 200, wall: null,
      light: new THREE.PointLight('#ff9a45', 0, 60, 1.5),
    };
    scene.add(t.light);
    S.tribes.push(t);
    return t;
  };

  // ------------------------------------------------------------ buildings
  const costOf = (b) => (b.type === 'house' ? HOUSE_COST[b.era] : b.type === 'wall' ? WALL_COST[b.era] : b.type === 'hall' && b.era >= 6 ? [20, 150] : COST[b.type]) || [0, 0];
  const addBuilding = (tribe, type, x, z, extra = {}) => {
    const b = { tribe, type, x, z, era: tribe.era, built: 0, work: 0, need: WORK[type], state: 'site', paid: false, yaw: Math.atan2(tribe.x - x, tribe.z - z), burn: 0, ...extra };
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
    const tr = b.tribe.color;
    let m;
    switch (b.type) {
      case 'house': m = houseModel(tr, b.era, b.slot && Math.hypot(b.slot.x - b.tribe.x, b.slot.z - b.tribe.z) < 13); break;
      case 'factory': m = model('factory', () => gen('factory', 0, () => MD.hallModel(0))); break;
      case 'bonfire': m = model('bonfire', () => gen('bonfire', 0, MD.bonfireModel)); break;
      case 'granary': m = model('granary' + tr, () => gen('granary', tr, () => MD.granaryModel(tr))); break;
      case 'totem': m = model(`totem${tr}${b.era}`, () => gen('totem', tr, () => MD.totemModel(tr, b.era))); break;
      case 'field': m = model('field', MD.fieldModel); break;
      case 'tower': m = model('tower' + tr, () => gen('tower', tr, () => MD.towerModel(tr))); break;
      case 'hall': m = b.era >= 6 ? model('skyscraper', () => gen('skyscraper', 0, () => MD.hallModel(tr))) : model('hall' + tr, () => gen('hall', tr, () => MD.hallModel(tr))); break;
      case 'stall': m = model(`stall${tr}${b.v % 4}`, () => gen('stall', tr, () => MD.stallModel(tr, b.v))); break;
      case 'wall': m = { geo: MD.wallModel(tr, b.era, WALL_R, b.tribe.gate).geo, glow: EMPTY }; break;
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
    G.log('building_lost', { tribe: b.tribe.color, type: b.type, cause });
    removeBuilding(b);
  };
  const find = (tribe, type) => tribe.buildings.find(b => b.type === type);
  const count = (tribe, type) => tribe.buildings.filter(b => b.type === type).length;
  const capacity = (tribe) => tribe.buildings.reduce((s, b) => s + (b.type === 'house' && b.state === 'done' ? HOUSE_CAP[b.era] : 0), 0);
  const free = (b) => { b.paid = true; b.built = 1; b.work = b.need; b.state = 'done'; const i = b.tribe.queue.indexOf(b); if (i >= 0) b.tribe.queue.splice(i, 1); };

  // What should exist right now? Queue whatever is missing or out of date, and pay for
  // queued work in order as wood and stone come in.
  const planTribe = (t) => {
    const pop = t.people.length;
    if (!find(t, 'bonfire')) free(addBuilding(t, 'bonfire', t.x, t.z));
    const houses = t.buildings.filter(b => b.type === 'house');
    const cap = HOUSE_CAP[t.era];
    const want = Math.min(t.slots.length, Math.ceil((pop + 3) / cap));
    const pending = t.queue.filter(b => b.type === 'house' && b.state !== 'done').length;
    if (houses.length < want && pending < 4) {
      const slot = t.slots.find(s => !s.used);
      if (slot) { const b = addBuilding(t, 'house', slot.x, slot.z, { slot }); slot.used = b; }
    }
    // upgrades, a few at a time
    let upgrading = t.queue.filter(b => b.upgrading).length;
    for (const b of t.buildings) {
      if (upgrading >= 5) break;
      const due = b.type === 'house' || b.type === 'totem' ? b.era < t.era : b.type === 'wall' ? b.era < t.era && t.era === 4 : b.type === 'hall' ? t.era >= 6 && b.era < 6 : false;
      if (due && b.state === 'done') {
        b.era = t.era; b.upgrading = true; b.state = 'site'; b.work = 0; b.built = 0.25; b.paid = false; setModel(b); t.queue.push(b); upgrading++;
      }
    }
    const sp = t.spots;
    villages[t.id].era = t.era;      // animals and trees look at this
    if (t.era >= 2) {
      if (!find(t, 'totem')) addBuilding(t, 'totem', sp.totem.x, sp.totem.z);
      if (!find(t, 'granary')) addBuilding(t, 'granary', sp.granary.x, sp.granary.z);
      const nf = count(t, 'field');
      if (nf < Math.min(sp.fields.length, 1 + t.era * 2 + Math.floor(pop / 40)) && !t.queue.some(b => b.type === 'field')) addBuilding(t, 'field', sp.fields[nf].x, sp.fields[nf].z);
    }
    if (t.era >= 5) {
      // an industrial city outgrows its wall, clears the land around it and burns wood in its factories
      if (t.wall && t.buildings.includes(t.wall)) {
        G.fx.puff(t.x + Math.cos(t.gate) * WALL_R, T.height(t.x, t.z) + 1, t.z + Math.sin(t.gate) * WALL_R, '#d8c7a4', 30, 6);
        removeBuilding(t.wall); t.wall = null; t.wallOn = false;
        const i = T.walls.findIndex(w => w.x === t.x && w.z === t.z); if (i >= 0) T.walls.splice(i, 1);
        G.log('wall_down', { tribe: t.color, village: t.id });
      }
      const nfac = count(t, 'factory');
      if (nfac < t.era - 4 + (pop > 180 ? 1 : 0) && nfac < sp.factories.length && !t.queue.some(b => b.type === 'factory')) addBuilding(t, 'factory', sp.factories[nfac].x, sp.factories[nfac].z);
      const cleared = G.flora.clearNear(t.x, t.z, 40 + (t.era - 4) * 18, 2);
      if (cleared) { t.wood += cleared * 5; G.log('land_cleared', { tribe: t.color, trees: cleared }); }
    }
    if (t.era >= 3 && t.era <= 4) {
      if (!find(t, 'wall')) t.wall = addBuilding(t, 'wall', t.x, t.z);
      if (!find(t, 'tower')) addBuilding(t, 'tower', sp.tower.x, sp.tower.z);
    }
    if (t.era >= 4) {
      if (!find(t, 'hall')) addBuilding(t, 'hall', sp.hall.x, sp.hall.z);
      const ns = count(t, 'stall');
      if (ns < 3 && !t.queue.some(b => b.type === 'stall')) addBuilding(t, 'stall', sp.stalls[ns].x, sp.stalls[ns].z, { v: ns + t.color });
    }
    for (const b of t.queue) {
      if (b.paid) continue;
      const [w, s] = costOf(b);
      if (t.wood >= w && t.stone >= s) { t.wood -= w; t.stone -= s; b.paid = true; }
      else if (b.type !== 'house' && b.type !== 'wall') break;      // save up for the big project first
    }
    // next era?
    if (t.era < MAX_ERA && G.time / G.DAY + 1 >= ERA_DAY[t.era] && pop >= ERA_POP[t.era] && t.food > pop && houses.length && houses.every(b => b.era === t.era && b.state === 'done')) {
      t.era++;
      t.cheer = 5;
      G.log('era', { tribe: t.color, village: t.id, era: t.era });
      G.sfx('era', t.x, t.z);
      G.ui && G.ui.toast('era', t);
      for (let i = 0; i < 4; i++) G.fx.burst(t.x + rng.range(-3, 3), T.height(t.x, t.z) + 2.5, t.z + rng.range(-3, 3), i % 2 ? MD.TRIBES[t.color].cloth : MD.TRIBES[t.color].accent, 16, 1.3);
    }
  };
  // wood / stone still owed for queued work
  const owed = (t) => { let w = 0, s = 0; for (const b of t.queue) if (!b.paid) { const c = costOf(b); w += c[0]; s += c[1]; } return [w, s]; };

  // ------------------------------------------------------------ people
  const addPerson = (t, x, z, child = false) => {
    const p = {
      id: nextId++, human: true, tribe: t, x, z, y: T.ground(x, z), yaw: rng.range(0, 6.28), scale: child ? 0.45 : 0.86 * rng.range(0.94, 1.06), full: 0.86 * rng.range(0.94, 1.06),
      gait: rng.range(0, 6), amp: 0, stride: 6.5, role: child ? 'child' : 'idle', state: 'idle', timer: rng.range(0, 3), hp: 3, alive: true,
      spear: false, shield: false, carry: false, attack: 0, cheer: 0, bob: 0, cd: 0, sick: 0,
    };
    p.tx = x; p.tz = z;
    t.people.push(p); S.people.push(p); kinds[t.color].list.push(p);
    return p;
  };
  const dropClaims = (p) => {
    if (p.bush) { p.bush.taken = null; p.bush = null; }
    if (p.tree) { p.tree.taken = null; p.tree = null; }
  };
  const removePerson = (p) => {
    p.alive = false;
    const t = p.tribe;
    let i = t.people.indexOf(p); if (i >= 0) t.people.splice(i, 1);
    i = S.people.indexOf(p); if (i >= 0) S.people.splice(i, 1);
    i = kinds[t.color].list.indexOf(p); if (i >= 0) kinds[t.color].list.splice(i, 1);
    dropClaims(p);
    if (p.haul) { p.haul.taken = null; p.haul.carried = false; p.haul.x = p.x; p.haul.z = p.z; }
  };
  S.kill = (p, cause) => {
    if (!p.alive) return;
    removePerson(p);
    p.tribe.deaths++;
    G.log('death', { tribe: p.tribe.color, cause });
    G.sfx('cry', p.x, p.z);
    const c = cause === 'starve' ? '#9c8f80' : cause === 'plague' ? '#7d9a52' : MD.TRIBES[p.tribe.color].cloth;
    G.fx.burst(p.x, p.y + 0.7, p.z, c, 10);
    G.fx.burst(p.x, p.y + 0.9, p.z, '#6a4630', 6);
  };
  S.killAt = (x, z, r, cause) => { for (const p of [...S.people]) if (Math.hypot(p.x - x, p.z - z) < r) S.kill(p, cause); };
  S.destroyAt = (x, z, r, cause) => {
    for (const t of S.tribes) for (const b of [...t.buildings]) if (b.type !== 'wall' && b.type !== 'bonfire' && Math.hypot(b.x - x, b.z - z) < r) destroy(b, cause);
  };
  // Safe from predators: behind a wall, or right by the fire.
  S.sheltered = (p) => {
    const t = p.tribe, d = Math.hypot(p.x - t.x, p.z - t.z);
    return d < 12 || (t.wallOn && d < WALL_R);
  };
  S.infect = (x, z, r) => { let n = 0; for (const p of S.people) if (!p.immune && !p.sick && Math.hypot(p.x - x, p.z - z) < r) { p.sick = rng.range(22, 40); n++; } return n; };
  S.heal = (x, z, r) => {
    for (const p of S.people) if (Math.hypot(p.x - x, p.z - z) < r) { if (p.sick) { p.sick = 0; p.immune = true; } p.hp = Math.max(p.hp, 3); }
    for (const t of S.tribes) if (Math.hypot(t.x - x, t.z - z) < r + 15) t.food += 80;
  };

  villages.slice(0, 2).forEach((v, color) => {
    const t = createVillage(v.x, v.z, color, 1);
    for (let i = 0; i < 18; i++) { const a = rng.range(0, 6.28), r = rng.range(1.5, 7.5); addPerson(t, t.x + Math.cos(a) * r, t.z + Math.sin(a) * r); }
    // Start with a few finished shelters so the camp does not look empty.
    for (let i = 0; i < 6; i++) { planTribe(t); for (const b of [...t.buildings]) if (b.type === 'house') free(b); }
  });

  const adults = (t) => t.people.filter(p => p.role !== 'child');
  const idleSpot = (p) => { const a = rng.range(0, 6.28), r = rng.range(1.6, 4.4 + Math.sqrt(p.tribe.people.length) * 0.9); p.tx = p.tribe.x + Math.cos(a) * r; p.tz = p.tribe.z + Math.sin(a) * r; };
  const goHome = (p) => { p.state = 'home'; const a = rng.range(0, 6.28); p.tx = p.tribe.x + Math.cos(a) * 2.6; p.tz = p.tribe.z + Math.sin(a) * 2.6; };
  const release = (p) => { p.role = 'idle'; p.state = 'idle'; p.spear = false; p.shield = false; p.timer = rng.range(0.5, 2); p.party = null; p.site = null; dropClaims(p); idleSpot(p); };

  // ------------------------------------------------------------ jobs
  const assignJobs = (t) => {
    const idle = t.people.filter(p => p.role === 'idle' && !p.carry && p.state !== 'home');
    if (S.war || isNight() || !idle.length) return;
    const all = adults(t);
    const cnt = (role) => all.filter(p => p.role === role).length;
    const take = (role, state, n, init) => { let have = cnt(role); while (have < n && idle.length) { const p = idle.pop(); p.role = role; p.state = state; init && init(p, have); have++; } };

    const [oweW, oweS] = owed(t);
    const share = (f) => clamp(Math.ceil(all.length * f), 1, 40);
    // the further a town has come, the more wood it wants
    const woodGoal = oweW + 24 + Math.max(0, t.era - 4) * 140;
    take('woodcutter', 'seek', t.wood < woodGoal ? share(0.16 + Math.max(0, t.era - 3) * 0.04) : t.wood < 90 ? 1 : 0);
    take('miner', 'seek', t.era >= 2 && t.stone < oweS + (t.era >= 3 ? 60 : 30) ? share(0.16) : 0);

    const sites = t.queue.filter(b => b.state !== 'done' && b.paid);
    take('builder', 'toSite', sites.length ? clamp(Math.ceil(all.length / 5), 1, 16) : 0, p => { p.site = null; });

    const fields = t.buildings.filter(b => b.type === 'field' && b.state === 'done');
    take('farmer', 'toField', t.food < 300 + all.length * 12 ? fields.length * 3 : Math.ceil(fields.length / 2), (p, i) => { p.field = fields[i % fields.length]; });

    // hunting parties of three
    t.parties = t.parties.filter(pt => pt.members.some(m => m.alive && m.party === pt));
    // later ages hunt more, further, and anything that moves (predators and elephants included)
    const wantParties = clamp(Math.floor(all.length / 14) * (t.era >= 5 ? 2 : 1), 1, 14);
    if (t.parties.length < wantParties && idle.length >= 3) {
      const reach = 95 + t.era * 14;
      const prey = G.animals.nearestPrey(t.x, t.z, reach, a => !a.hunted) || (t.era >= 4 ? G.animals.nearestAny(t.x, t.z, reach, a => !a.hunted) : null);
      if (prey) {
        const party = { members: [], prey, timer: 60, state: 'hunt' };
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
  const nearestRock = (t) => {
    let best = null, bd = 1e12;
    for (const k of KOPJES) { const d = (k.x - t.x) ** 2 + (k.z - t.z) ** 2; if (d < bd) { bd = d; best = k; } }
    return best;
  };
  // A quarry appears at an outcrop once people start cutting stone there.
  const quarries = new Map();
  const openQuarry = (k, t) => {
    if (quarries.has(k)) return;
    const a = G.assets.quarry;
    const ang = Math.atan2(t.z - k.z, t.x - k.x);
    const x = k.x + Math.cos(ang) * 9, z = k.z + Math.sin(ang) * 9;
    let mesh = null;
    if (a) {
      mesh = new THREE.Mesh(a.geo, a.mat); mesh.castShadow = mesh.receiveShadow = true;
      mesh.position.set(x, T.height(x, z) - 0.1, z); mesh.rotation.y = -ang + Math.PI / 2;
      scene.add(mesh);
    }
    quarries.set(k, { x, z, mesh });
    G.log('quarry', { tribe: t.color, x, z });
  };

  const deposit = (p) => {
    const t = p.tribe, n = p.load || 0;
    if (p.loadKind === 'wood') t.wood += n; else if (p.loadKind === 'stone') t.stone += n; else t.food += n;
    p.carry = false; p.loadKind = null;
    G.fx.puff(p.x, p.y + 1.2, p.z, '#f3cf63', 3, 0.6);
  };
  const carryHome = (p, kind, n) => { p.loadKind = kind; p.load = n; p.carry = true; p.role = 'idle'; goHome(p); };

  const WALK = 2.3, RUN = 3.7;

  const updatePerson = (p, dt) => {
    const t = p.tribe;
    p.attack = Math.max(0, p.attack - dt * 3);
    p.cd -= dt;
    p.bob += (0 - p.bob) * Math.min(1, dt * 8);
    p.cheer = t.cheer > 0 && p.role !== 'warrior' ? 1 : Math.max(0, p.cheer - dt * 2);
    if (p.cheer > 0.5 && p.state !== 'fight') { p.bob = Math.abs(Math.sin(G.time * 9 + p.id)) * 0.3; p.gait += dt * 6; settle(T, p, dt); if (t.cheer > 0) return; }
    if (T.fire[T.cell(p.x, p.z)] > 0) { p.hp -= dt * 2.5; if (p.hp <= 0) { S.kill(p, 'fire'); return; } }

    // plague: slows, spreads to people close by, and kills some
    let walk = WALK;
    if (p.sick > 0) {
      walk = WALK * 0.55;
      p.sick -= dt;
      p.bob = -0.06;
      if (G.fx.R() < dt * 1.5) G.fx.puff(p.x, p.y + 1.1, p.z, '#8fae4a', 1, 0.4);
      if (G.fx.R() < dt * 0.25) G.sfx('cough', p.x, p.z);
      p.spread = (p.spread || 0) - dt;
      if (p.spread <= 0) {
        p.spread = 1.5;
        for (const o of t.people) if (!o.sick && !o.immune && Math.abs(o.x - p.x) < 2.6 && Math.abs(o.z - p.z) < 2.6 && rng() < 0.3) o.sick = rng.range(22, 40);
      }
      if (p.sick <= 0) { p.sick = 0; if (rng() < 0.42) { S.kill(p, 'plague'); return; } p.immune = true; }
    }

    if (p.role === 'child') {
      if (p.scale < p.full) p.scale += dt * 0.014; else { release(p); return; }
      p.timer -= dt;
      if (p.timer <= 0) { p.timer = rng.range(1.5, 4); idleSpot(p); }
      moveToward(T, p, p.tx, p.tz, walk * 1.1, dt);
      return;
    }

    if (isNight() && !S.war && p.role !== 'warrior' && p.role !== 'hunter' && p.role !== 'settler' && p.state !== 'fire' && p.state !== 'home' && p.state !== 'toFire') {
      dropClaims(p);
      p.role = 'idle'; p.state = 'toFire'; p.site = null;
      const a = (p.id * 2.399) % 6.28, rr = 2.4 + ((p.id * 7) % 5) * 0.9; p.tx = t.x + Math.cos(a) * rr; p.tz = t.z + Math.sin(a) * rr;
    }

    switch (p.role) {
      case 'idle': {
        if (p.state === 'toFire') {
          if (moveToward(T, p, p.tx, p.tz, walk, dt) < 0.3) p.state = 'fire';
          if (!isNight()) p.state = 'idle';
        } else if (p.state === 'fire') {
          faceTo(p, t.x, t.z, dt); settle(T, p, dt);
          p.bob = Math.abs(Math.sin(G.time * 6 + p.id)) * 0.22; p.cheer = 0.9; p.gait += dt * 5;
          if (!isNight()) { p.state = 'idle'; p.cheer = 0; }
        } else if (p.state === 'home') {
          if (moveToward(T, p, p.tx, p.tz, p.carry ? walk : walk * 1.1, dt) < 0.5) {
            if (p.carry) deposit(p);
            p.state = 'idle'; p.timer = rng.range(0.4, 1.5); idleSpot(p);
          }
        } else {
          p.timer -= dt;
          if (moveToward(T, p, p.tx, p.tz, walk * 0.8, dt) < 0.3 && p.timer <= 0) { p.timer = rng.range(1, 4); idleSpot(p); }
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
          if (moveToward(T, p, b.x, b.z, walk, dt) < 0.9) { p.state = 'pick'; p.timer = 1.8; }
        } else if (p.state === 'forage') {
          if (moveToward(T, p, p.tx, p.tz, walk, dt) < 0.6) { p.state = 'pick'; p.timer = 3.2; }
        } else if (p.state === 'pick') {
          settle(T, p, dt); p.timer -= dt; p.bob = -Math.abs(Math.sin(G.time * 8)) * 0.12; p.attack = 0.5 + Math.sin(G.time * 10) * 0.4;
          if (p.timer <= 0) {
            const b = p.bush;
            let n = T.grass[T.cell(p.x, p.z)] > 0.3 ? 2 : 0.5;
            if (b) { b.berries = false; b.regrow = rng.range(45, 80); b.taken = null; G.flora.placeBush(b); p.bush = null; n = 6; }
            carryHome(p, 'food', n);
          }
        }
        break;
      }
      case 'woodcutter': {
        if (p.state === 'seek') {
          const tr = G.flora.nearestTree(p.x, p.z, 130, t.x, t.z);
          if (tr) { tr.taken = p; p.tree = tr; p.state = 'toTree'; } else release(p);
        } else if (p.state === 'toTree') {
          const tr = p.tree;
          if (!tr || tr.state !== 'alive') { if (tr) tr.taken = null; p.tree = null; p.state = 'seek'; break; }
          if (moveToward(T, p, tr.x, tr.z, walk, dt) < 1.0) { p.state = 'chop'; p.timer = 5.5; }
        } else if (p.state === 'chop') {
          const tr = p.tree;
          if (!tr || tr.state !== 'alive') { p.tree = null; p.state = 'seek'; break; }
          settle(T, p, dt); faceTo(p, tr.x, tr.z, dt); p.timer -= dt;
          p.attack = 0.5 + Math.sin(G.time * 7 + p.id) * 0.5;
          if (G.fx.R() < dt * 2.4) { G.sfx('chop', p.x, p.z); G.fx.puff(tr.x, p.y + 0.6, tr.z, '#d9c08a', 1, 0.7); }
          if (p.timer <= 0) {
            G.flora.fell(tr); p.tree = null;
            G.sfx('timber', tr.x, tr.z); G.fx.puff(tr.x, p.y + 0.5, tr.z, '#cdb98a', 10, 2.5);
            G.log('tree_felled', { tribe: t.color });
            carryHome(p, 'wood', 8);
          }
        }
        break;
      }
      case 'miner': {
        if (p.state === 'seek') {
          const k = nearestRock(t);
          if (!k || Math.hypot(k.x - t.x, k.z - t.z) > 230) { release(p); break; }
          openQuarry(k, t);
          const qy = quarries.get(k);
          p.rock = k; p.tx = qy.x + rng.range(-3, 3); p.tz = qy.z + rng.range(-3, 3); p.state = 'toRock';
        } else if (p.state === 'toRock') {
          if (moveToward(T, p, p.tx, p.tz, walk, dt) < 0.8) { p.state = 'mine'; p.timer = 6.5; }
        } else if (p.state === 'mine') {
          settle(T, p, dt); faceTo(p, p.rock.x, p.rock.z, dt); p.timer -= dt;
          p.attack = 0.5 + Math.sin(G.time * 6 + p.id) * 0.5;
          if (G.fx.R() < dt * 1.8) { G.sfx('pick', p.x, p.z); G.fx.spark(p.x + Math.sin(p.yaw) * 0.6, p.y + 0.5, p.z + Math.cos(p.yaw) * 0.6, 2, '#fff0c2', 0.4); }
          if (p.timer <= 0) carryHome(p, 'stone', 6);
        }
        break;
      }
      case 'farmer': {
        const f = p.field;
        if (!f || !t.buildings.includes(f)) { release(p); break; }
        if (p.state === 'toField') {
          if (p.fieldSet !== f) { p.fieldSet = f; p.tx = f.x + rng.range(-1.6, 1.6); p.tz = f.z + rng.range(-1.2, 1.2); }
          if (moveToward(T, p, p.tx, p.tz, walk, dt) < 0.4) { p.state = 'farm'; p.timer = rng.range(8, 13); }
        } else if (p.state === 'farm') {
          settle(T, p, dt); p.timer -= dt;
          p.bob = -Math.abs(Math.sin(G.time * 5 + p.id)) * 0.14; p.attack = 0.4 + Math.sin(G.time * 5 + p.id) * 0.4;
          if (p.timer <= 0) { p.fieldSet = null; carryHome(p, 'food', G.env.drought ? 2 : 11); }
        }
        break;
      }
      case 'builder': {
        if (!p.site || p.site.state === 'done' || !t.buildings.includes(p.site)) {
          const open = t.queue.filter(b => b.state !== 'done' && b.paid);
          if (!open.length) { release(p); break; }
          p.site = open[p.id % Math.min(open.length, 5)];
          p.state = 'toSite';
          const a = rng.range(0, 6.28), r = p.site.type === 'wall' ? WALL_R + 1.4 : p.site.type === 'hall' ? 4.6 : 2.0;
          p.tx = p.site.x + Math.cos(a) * r; p.tz = p.site.z + Math.sin(a) * r;
        }
        if (p.state === 'toSite') {
          if (moveToward(T, p, p.tx, p.tz, walk, dt) < 0.5) p.state = 'build';
        } else {
          settle(T, p, dt); faceTo(p, p.site.x, p.site.z, dt);
          p.attack = 0.5 + Math.sin(G.time * 9 + p.id) * 0.5;
          p.site.work += dt;
          if (G.fx.R() < dt * 2.2) G.sfx('hammer', p.x, p.z);
          if (G.fx.R() < dt * 1.2) G.fx.puff(p.site.x + G.fx.R.range(-1, 1), T.height(p.site.x, p.site.z) + 0.3, p.site.z + G.fx.R.range(-1, 1), '#e0cfa8', 2, 0.8);
        }
        break;
      }
      case 'settler': {
        const c = p.dest;
        if (moveToward(T, p, p.tx, p.tz, walk * 1.1, dt) < 2.5 || Math.hypot(p.x - c.x, p.z - c.z) < 8) {
          // arrived: join the new settlement
          let i = t.people.indexOf(p); if (i >= 0) t.people.splice(i, 1);
          p.tribe = c; c.people.push(p); p.dest = null; p.carry = false;
          release(p);
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
      const gun = p.tribe.era >= 5;
      if (d > (gun ? 11 : 6.5)) moveToward(T, p, prey.x + Math.cos(i * 2.1) * 2.5, prey.z + Math.sin(i * 2.1) * 2.5, d > 16 ? RUN * 0.9 : WALK * 1.15, dt);
      else {
        settle(T, p, dt); faceTo(p, prey.x, prey.z, dt);
        if (p.cd <= 0) {
          p.cd = 1.7; p.attack = 1;
          G.sfx(gun ? 'gun' : 'spear', p.x, p.z);
          if (gun) G.fx.spark(p.x + Math.sin(p.yaw) * 0.5, p.y + 1.1, p.z + Math.cos(p.yaw) * 0.5, 3, '#ffe6a0', 0.5);
          G.fx.lit.add({ x: p.x, y: p.y + 1.5, z: p.z, vx: (prey.x - p.x) / 0.4, vy: 2.2, vz: (prey.z - p.z) / 0.4, grav: 11, life: 0.4, max: 0.4, size: 0.09, sx: 1, sy: 1, spin: 0, r: 0.4, g: 0.3, b: 0.2 });
          if (rng() < (gun ? 0.8 : 0.6)) {
            prey.hp -= gun ? 4 : 1;
            G.animals.scare(prey.x, prey.z, 4);
            if (prey.hp <= 0) {
              const car = G.animals.kill(prey, 'hunt');
              G.log('hunt_kill', { tribe: p.tribe.color, kind: prey.kind });
              if (car) { car.taken = 'tribe'; p.state = 'toCarcass'; p.haul = car; } else { p.spear = false; p.role = 'idle'; p.party = null; goHome(p); }
              for (const m of pt.members) if (m !== p && m.alive) { m.spear = false; m.role = 'idle'; m.party = null; goHome(m); }
            }
          }
        }
      }
    } else if (p.state === 'toCarcass') {
      const c = p.haul;
      if (moveToward(T, p, c.x, c.z, WALK * 1.2, dt) < 0.8) { c.gone = true; p.haul = null; p.spear = false; p.party = null; carryHome(p, 'food', c.meat * 2); }
    }
  };

  // ------------------------------------------------------------ war (red against blue, every settlement joins)
  S.startWar = () => {
    if (S.war) return false;
    const war = { t: 0, phase: 'rally', sides: [{ color: 0, start: 0, warriors: [] }, { color: 1, start: 0, warriors: [] }] };
    for (const t of S.tribes) {
      for (const pt of t.parties) if (pt.prey) pt.prey.hunted = false;
      t.parties = [];
      const list = adults(t).filter(p => !p.carry && p.role !== 'settler' && !p.sick);
      const n = Math.max(Math.min(list.length, 3), Math.floor(list.length * 0.72));
      list.slice(0, n).forEach((p, i) => {
        dropClaims(p);
        p.role = 'warrior'; p.state = 'rally'; p.spear = true; p.shield = true; p.party = null; p.hp = 5; p.target = null;
        const row = Math.floor(i / 14), colm = (i % 14) - 6.5;
        const ax = Math.cos(t.gate), az = Math.sin(t.gate);
        p.fx = t.rally.x - ax * row * 1.1 - az * colm * 1.0; p.fz = t.rally.z - az * row * 1.1 + ax * colm * 1.0;
        war.sides[t.color].warriors.push(p);
      });
      G.sfx('drum', t.x, t.z);
    }
    for (const s of war.sides) s.start = s.warriors.length;
    S.war = war;
    G.sfx('horn');
    G.log('war_start');
    G.ui && G.ui.toast('war');
    return true;
  };
  const endWar = (winner) => {
    const war = S.war;
    for (const side of war.sides) for (const p of side.warriors) if (p.alive) { p.shield = false; p.spear = false; p.role = 'idle'; p.target = null; goHome(p); if (side.color === winner) p.cheer = 3; }
    for (const t of S.tribes) if (t.color === winner) t.cheer = 4;
    G.log('war_end', { winner });
    G.sfx('horn');
    G.ui && G.ui.toast('peace', winner >= 0 ? { color: winner } : null);
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
      if (lost(a) || lost(b) || war.t > 420) endWar(lost(a) && lost(b) ? -1 : lost(a) ? 1 : lost(b) ? 0 : -1);
    }
  };
  const updateWarrior = (p, dt) => {
    const war = S.war;
    if (!war) { release(p); return; }
    if (war.phase === 'rally') {
      if (moveToward(T, p, p.fx, p.fz, RUN * 0.8, dt) < 0.4) { faceTo(p, N / 2, N / 2, dt); p.bob = Math.abs(Math.sin(G.time * 7 + p.id)) * 0.12; }
      return;
    }
    const enemy = war.sides[1 - p.tribe.color];
    p.scan = (p.scan || 0) - dt;
    if (p.scan <= 0 || !p.target || !p.target.alive) {
      p.scan = 0.5; p.target = null;
      let bd = 1e9;
      for (const e of enemy.warriors) { const d = (e.x - p.x) ** 2 + (e.z - p.z) ** 2; if (d < bd) { bd = d; p.target = e; } }
    }
    const e = p.target;
    if (!e) return;
    const d = Math.hypot(e.x - p.x, e.z - p.z);
    if (d > 1.15) moveToward(T, p, e.x, e.z, d < 12 ? RUN : WALK * 1.3, dt);
    else {
      settle(T, p, dt); faceTo(p, e.x, e.z, dt);
      p.state = 'fight';
      if (p.cd <= 0) {
        p.cd = rng.range(0.7, 1.1); p.attack = 1;
        G.sfx('clash', p.x, p.z);
        if (rng() < 0.5) {
          e.hp--;
          G.fx.spark(e.x, e.y + 0.9, e.z, 3, '#fff0c2', 0.5);
          if (e.hp <= 0) S.kill(e, 'war');
        } else G.fx.puff(e.x, e.y + 0.8, e.z, '#e9dfc8', 2, 0.5);
      }
    }
  };

  // ------------------------------------------------------------ founding a new settlement
  const findSite = (t) => {
    for (let i = 0; i < 60; i++) {
      const a = rng.range(0, 6.28), r = rng.range(125, 200);
      const x = t.x + Math.cos(a) * r, z = t.z + Math.sin(a) * r;
      if (!T.inside(x, z, 62)) continue;
      if (S.tribes.some(o => Math.hypot(o.x - x, o.z - z) < 115)) continue;
      let ok = true;
      for (let k = 0; k < 10 && ok; k++) { const b = k * 0.628; if (T.depth(x + Math.cos(b) * 24, z + Math.sin(b) * 24) > -0.3 || T.depth(x + Math.cos(b) * 10, z + Math.sin(b) * 10) > -0.3) ok = false; }
      if (!ok || T.slope(x, z) > 0.5) continue;
      return { x, z };
    }
    return null;
  };
  const foundColony = (t) => {
    const site = findSite(t);
    if (!site) { t.colonyCd = 60; return; }
    const level = T.height(site.x, site.z);
    T.deform(site.x, site.z, 38, (d, h) => lerp(h, level, smooth(36, 24, d)));
    G.flora.clear(site.x, site.z, 11);
    villages.push({ x: site.x, z: site.z });
    const c = createVillage(site.x, site.z, t.color, Math.max(1, t.era - 1), t);
    c.food = 120; c.wood = 50; c.stone = t.era >= 4 ? 30 : 0;
    t.food = Math.max(0, t.food - 120); t.wood = Math.max(0, t.wood - 30);
    const movers = adults(t).filter(p => (p.role === 'idle' || p.role === 'gatherer') && !p.carry && !p.sick).slice(0, 22);
    for (const p of movers) {
      dropClaims(p);
      p.role = 'settler'; p.state = 'walk'; p.dest = c; p.carry = true; p.loadKind = 'food'; p.load = 0;
      p.tx = c.x + rng.range(-4, 4); p.tz = c.z + rng.range(-4, 4);
    }
    t.colonyCd = 300;
    G.log('colony', { tribe: t.color, x: site.x, z: site.z, settlers: movers.length });
    G.sfx('horn', t.x, t.z);
    G.ui && G.ui.toast('colony', t);
  };

  // ------------------------------------------------------------ per-settlement tick
  const updateTribe = (t, dt) => {
    const pop = t.people.length;
    t.cheer = Math.max(0, t.cheer - dt);
    t.food -= pop * 0.026 * dt;
    if (t.food <= 0) {
      t.food = 0; t.starve += dt;
      if (t.starve > 11 && pop > 2) { t.starve = 0; S.kill(rng.pick(t.people), 'starve'); }
    } else t.starve = Math.max(0, t.starve - dt);

    t.birth -= dt;
    if (t.birth <= 0) {
      t.birth = rng.range(2.2, 4.2) * (pop > 120 ? 1.6 : 1);
      if (pop >= 2 && pop < MAX_POP && pop < capacity(t) && t.food > 6 + pop * 1.2 && !S.war) {
        const h = rng.pick(t.buildings.filter(b => b.type === 'house' && b.state === 'done'));
        if (h) { addPerson(t, h.x + rng.range(-0.6, 0.6), h.z + rng.range(-0.6, 0.6), true); t.food -= 4; G.log('birth', { tribe: t.color }); }
      }
    }
    t.plan -= dt;
    if (t.plan <= 0) { t.plan = 1.5; planTribe(t); assignJobs(t); }

    for (const b of t.buildings) if (b.type === 'factory' && b.state === 'done') t.wood = Math.max(0, t.wood - 0.14 * dt);
    t.colonyCd -= dt;
    if (t.colonyCd <= 0 && pop >= 160 && t.era >= 4 && !S.war && G.opts.colonies && S.tribes.filter(o => o.color === t.color).length < MAX_VILLAGES) foundColony(t);

    // the wall starts to matter once it is half up
    if (t.wall && !t.wallOn && t.buildings.includes(t.wall) && (t.wall.built > 0.5 || t.wall.upgrading)) {
      t.wallOn = true;
      T.walls.push({ x: t.x, z: t.z, r: WALL_R, gate: t.gate, gap: 0.24 });
    }

    // construction progress and fire
    for (const b of [...t.buildings]) {
      if (b.state !== 'done') {
        const target = clamp(b.work / b.need, 0, 1);
        b.built = Math.max(b.built, target);
        if (target >= 1) {
          b.state = 'done'; b.built = 1; b.upgrading = false;
          const i = t.queue.indexOf(b); if (i >= 0) t.queue.splice(i, 1);
          G.fx.puff(b.x, T.height(b.x, b.z) + 0.5, b.z, '#efe2c0', 10, 2);
          G.sfx('build', b.x, b.z);
          G.log('built', { tribe: t.color, type: b.type, era: b.era });
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
    for (let i = 0; i < S.tribes.length; i++) updateTribe(S.tribes[i], dt);
    for (let i = S.people.length - 1; i >= 0; i--) { const p = S.people[i]; if (p) updatePerson(p, dt); }
    for (const t of S.tribes) for (const pt of t.parties) pt.timer -= dt;
  };

  // ------------------------------------------------------------ drawing
  S.render = (dt, time) => {
    kinds[0].draw(); kinds[1].draw();
    const night = stage.night, view = stage.view;
    glowMat.color.setScalar(0.25 + night * 1.0);
    S.tribes.forEach((t, i) => {
      const seen = Math.hypot(t.x - view.x, t.z - view.z) < view.r + 40;
      t.light.visible = seen;
      for (const b of t.buildings) { b.mesh.visible = seen; if (!seen) b.glow.visible = false; }
      if (!seen) return;
      const gy = T.height(t.x, t.z);
      const n = night > 0.3 ? 3 : 1;
      for (let k = 0; k < n; k++) if (G.fx.R() < 0.7) G.fx.flame(t.x, gy + 0.3, t.z, night > 0.3 ? 0.62 : 0.34);
      if (G.fx.R() < 0.05) G.fx.smoke(t.x, gy + 1.5, t.z, 0.22, 0.62);
      t.light.position.set(t.x, gy + 2.2, t.z);
      t.light.intensity = (6 + night * 240) * (0.85 + Math.sin(time * 19 + i * 3) * 0.1 + Math.sin(time * 7.3 + i) * 0.05);
      for (const b of t.buildings) {
        const y = T.height(b.x, b.z);
        const k = b.paid ? b.built : Math.min(b.built, 0.06);
        const e = 1 - (1 - k) * (1 - k);
        b.mesh.position.set(b.x, y - (b.type === 'field' ? 0.02 : 0.06), b.z);
        b.mesh.rotation.y = b.yaw;
        b.mesh.scale.set(1, Math.max(0.02, e), 1);
        b.glow.position.copy(b.mesh.position); b.glow.rotation.y = b.yaw; b.glow.scale.copy(b.mesh.scale);
        b.glow.visible = b.state === 'done' && (night > 0.15 || b.type === 'bonfire');
        if (b.type === 'factory' && b.state === 'done' && G.fx.R() < 0.35) G.fx.smoke(b.x + G.fx.R.range(-2.5, 2.5), y + 6.5, b.z + G.fx.R.range(-2, 2), 1.1, 0.3);
      }
    });
  };

  // one line per people for the interface and the logs
  S.summary = () => [0, 1].map(color => {
    const vs = S.tribes.filter(t => t.color === color);
    return {
      color, villages: vs.length, era: Math.max(...vs.map(t => t.era)), pop: vs.reduce((n, t) => n + t.people.length, 0),
      food: Math.round(vs.reduce((n, t) => n + t.food, 0)), wood: Math.round(vs.reduce((n, t) => n + t.wood, 0)), stone: Math.round(vs.reduce((n, t) => n + t.stone, 0)),
    };
  });
  S.info = S.summary;
  return S;
}
