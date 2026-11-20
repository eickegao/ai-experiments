// Every model in the sandbox, built from coloured primitives. Creatures face +Z.
// A creature is a list of parts; each part's geometry is centred on its pivot so
// legs, arms and wings can swing.
import { Builder } from './util.js';

const part = (kind, pivot, fn, phase = 0) => {
  const b = new Builder();
  fn(b);
  b.recenter(pivot[0], pivot[1], pivot[2]);
  return { kind, pivot, phase, geo: b.build() };
};

// Four legs: diagonal pairs move together.
const quadLegs = (w, h, d, x, z, top, bottom, hoof = null, zBack = -z) => {
  const mk = (sx, pz, phase) => part('leg', [sx * x, h, pz], b => {
    b.box(w, h * 0.72, d, sx * x, h * 0.64, pz, top);
    b.box(w * 0.86, h * 0.3, d * 0.86, sx * x, h * 0.15, pz, bottom);
    if (hoof) b.box(w, h * 0.1, d, sx * x, h * 0.05, pz, hoof);
  }, phase);
  return [mk(1, z, 0), mk(-1, z, Math.PI), mk(1, zBack, Math.PI), mk(-1, zBack, 0)];
};

export const TRIBES = [
  { id: 0, cloth: '#c8432a', accent: '#f3cf63', dark: '#7d2617' },
  { id: 1, cloth: '#2b58b8', accent: '#f4efe2', dark: '#1a3676' },
];
const SKIN = '#6a4630', SKIN_D = '#523424', HAIR = '#1d1613';

export function humanParts(tribe) {
  const t = TRIBES[tribe];
  return [
    part('body', [0, 0, 0], b => {
      b.box(0.36, 0.26, 0.26, 0, 0.55, 0, t.cloth);          // wrap
      b.box(0.38, 0.05, 0.28, 0, 0.44, 0, t.accent);        // hem
      b.box(0.32, 0.36, 0.2, 0, 0.84, 0, SKIN);             // chest
      b.box(0.34, 0.06, 0.22, 0, 0.98, 0, t.accent);         // necklace
      b.box(0.25, 0.26, 0.25, 0, 1.17, 0, SKIN);              // head
      b.box(0.27, 0.09, 0.27, 0, 1.33, -0.01, HAIR);
      b.box(0.275, 0.05, 0.275, 0, 1.27, 0, t.cloth);       // headband

    }),
    part('leg', [0.1, 0.46, 0], b => { b.box(0.12, 0.46, 0.14, 0.09, 0.23, 0, SKIN_D); }, 0),
    part('leg', [-0.1, 0.46, 0], b => { b.box(0.12, 0.46, 0.14, -0.09, 0.23, 0, SKIN_D); }, Math.PI),
    part('arm', [0.21, 0.98, 0], b => { b.box(0.09, 0.44, 0.1, 0.21, 0.77, 0, SKIN); }, Math.PI),
    part('arm', [-0.21, 0.98, 0], b => { b.box(0.09, 0.44, 0.1, -0.21, 0.77, 0, SKIN); }, 0),
    part('spear', [0.33, 0.9, 0.05], b => {
      b.box(0.05, 1.7, 0.05, 0.33, 0.95, 0.1, '#7a5a3a');
      b.box(0.09, 0.26, 0.03, 0.33, 1.9, 0.1, '#d9d6cf');
      b.box(0.07, 0.07, 0.07, 0.33, 1.72, 0.1, t.cloth);
    }),
    part('shield', [-0.34, 0.8, 0.1], b => {
      b.box(0.07, 0.72, 0.44, -0.36, 0.78, 0.12, t.cloth);
      b.box(0.075, 0.5, 0.12, -0.375, 0.78, 0.12, t.accent);
      b.box(0.08, 0.12, 0.3, -0.38, 0.78, 0.12, t.dark);
    }),
    part('carry', [0, 1.36, 0], b => {
      b.box(0.5, 0.2, 0.4, 0, 1.46, 0, '#c9a56a');
      b.box(0.52, 0.05, 0.42, 0, 1.56, 0, '#a98350');
      b.box(0.16, 0.14, 0.16, -0.1, 1.63, 0.05, '#b8372e');
      b.box(0.16, 0.12, 0.16, 0.1, 1.62, -0.05, '#d1583a');
      b.box(0.12, 0.1, 0.12, 0.02, 1.62, 0.12, '#8fae4a');
    }),
  ];
}

export function zebraParts() {
  const W = '#f1eee4', K = '#27221f';
  return [
    part('body', [0, 0, 0], b => {
      b.box(0.52, 0.52, 1.15, 0, 0.9, 0, W);
      for (let i = 0; i < 5; i++) b.box(0.545, 0.545, 0.09, 0, 0.9, -0.44 + i * 0.22, K);
      b.box(0.3, 0.62, 0.32, 0, 1.3, 0.56, W, -0.55);
      b.box(0.315, 0.1, 0.335, 0, 1.2, 0.5, K, -0.55);
      b.box(0.315, 0.1, 0.335, 0, 1.4, 0.62, K, -0.55);
      b.box(0.1, 0.62, 0.12, 0, 1.36, 0.4, K, -0.55);             // mane
      b.box(0.28, 0.28, 0.5, 0, 1.56, 0.86, W);
      b.box(0.24, 0.22, 0.16, 0, 1.52, 1.14, K);                   // muzzle
      b.box(0.08, 0.16, 0.08, 0.1, 1.76, 0.7, W); b.box(0.08, 0.16, 0.08, -0.1, 1.76, 0.7, W);
      b.box(0.08, 0.5, 0.08, 0, 0.82, -0.62, K, 0.35);             // tail
    }),
    ...quadLegs(0.14, 0.66, 0.14, 0.17, 0.42, W, W, K),
  ];
}

export function wildebeestParts() {
  const D = '#4a443f', L = '#6e655c', K = '#201c1a';
  return [
    part('body', [0, 0, 0], b => {
      b.box(0.56, 0.56, 1.2, 0, 0.92, 0, D);
      b.box(0.5, 0.3, 0.5, 0, 1.2, 0.3, D);                        // hump
      b.box(0.57, 0.4, 0.5, 0, 0.9, -0.38, L);                     // lighter rump
      b.box(0.14, 0.4, 0.6, 0, 1.3, 0.3, K);                       // mane
      b.box(0.34, 0.5, 0.44, 0, 0.98, 0.78, K, 0.35);              // long face
      b.box(0.12, 0.3, 0.1, 0, 0.6, 0.72, '#d9d0bd');              // beard
      b.box(0.5, 0.08, 0.08, 0, 1.24, 0.72, '#d8cdb5');            // horns
      b.box(0.08, 0.22, 0.08, 0.27, 1.34, 0.72, '#d8cdb5'); b.box(0.08, 0.22, 0.08, -0.27, 1.34, 0.72, '#d8cdb5');
      b.box(0.07, 0.6, 0.07, 0, 0.8, -0.66, K, 0.3);
    }),
    ...quadLegs(0.13, 0.66, 0.13, 0.18, 0.44, D, K),
  ];
}

export function gazelleParts() {
  const T = '#d6a45c', W = '#f5efe0', K = '#2a221c';
  return [
    part('body', [0, 0, 0], b => {
      b.box(0.36, 0.3, 0.86, 0, 0.84, 0, T);
      b.box(0.34, 0.12, 0.84, 0, 0.66, 0, W);
      b.box(0.375, 0.07, 0.6, 0, 0.74, 0, K);                      // side stripe
      b.box(0.2, 0.5, 0.2, 0, 1.16, 0.4, T, -0.3);
      b.box(0.2, 0.2, 0.34, 0, 1.42, 0.56, T);
      b.box(0.16, 0.12, 0.1, 0, 1.38, 0.76, K);
      b.box(0.04, 0.4, 0.04, 0.07, 1.7, 0.46, K, 0.25); b.box(0.04, 0.4, 0.04, -0.07, 1.7, 0.46, K, 0.25);
      b.box(0.22, 0.22, 0.06, 0, 0.84, -0.44, W);
      b.box(0.06, 0.16, 0.06, 0, 0.9, -0.48, K);
    }),
    ...quadLegs(0.09, 0.62, 0.09, 0.12, 0.33, T, W, K),
  ];
}

export function elephantParts() {
  const G = '#8f8b8e', D = '#77737a', W = '#f3ead6';
  return [
    part('body', [0, 0, 0], b => {
      b.box(1.3, 1.25, 1.95, 0, 1.6, 0, G);
      b.box(1.1, 0.3, 1.5, 0, 2.3, -0.1, G);
      b.box(1.02, 1.05, 0.85, 0, 1.9, 1.25, G);                    // head
      b.box(0.1, 1.05, 0.9, 0.6, 1.95, 0.95, D, 0, 0.5);           // ears
      b.box(0.1, 1.05, 0.9, -0.6, 1.95, 0.95, D, 0, -0.5);
      b.box(0.34, 0.6, 0.34, 0, 1.3, 1.72, G, 0.15);               // trunk
      b.box(0.27, 0.55, 0.27, 0, 0.82, 1.8, G);
      b.box(0.2, 0.4, 0.2, 0, 0.42, 1.86, D, -0.3);
      b.box(0.1, 0.1, 0.6, 0.3, 1.38, 1.85, W, 0.3); b.box(0.1, 0.1, 0.6, -0.3, 1.38, 1.85, W, 0.3);
      b.box(0.08, 0.7, 0.08, 0, 1.5, -1.0, D, 0.2);
    }),
    ...quadLegs(0.44, 1.0, 0.44, 0.4, 0.68, G, D, '#d9d1c4'),
  ];
}

export function giraffeParts() {
  const Y = '#e6b95c', B = '#9a5b2b', K = '#3a2a1e';
  const legs = quadLegs(0.15, 1.6, 0.15, 0.17, 0.4, Y, '#f0dfb6', K);
  return [
    part('body', [0, 0, 0], b => {
      b.box(0.52, 0.62, 1.15, 0, 1.9, 0, Y);
      for (const [x, y, z] of [[0.27, 2.0, 0.3], [0.27, 1.8, -0.2], [-0.27, 1.95, -0.1], [-0.27, 1.75, 0.35], [0.27, 1.75, 0.05], [-0.27, 2.05, -0.4]])
        b.box(0.03, 0.24, 0.28, x, y, z, B);
      b.box(0.3, 0.03, 0.3, 0, 2.22, 0.2, B); b.box(0.3, 0.03, 0.3, 0, 2.22, -0.3, B);
      b.box(0.28, 2.0, 0.32, 0, 2.95, 0.82, Y, 0.38);              // neck
      for (const [y, z] of [[2.5, 0.63], [3.0, 0.83], [3.5, 1.03]]) b.box(0.3, 0.26, 0.2, 0, y, z, B, 0.38);
      b.box(0.08, 1.8, 0.1, 0, 3.0, 0.62, B, 0.38);                // mane
      b.box(0.26, 0.28, 0.58, 0, 3.95, 1.32, Y);
      b.box(0.22, 0.2, 0.14, 0, 3.9, 1.64, K);
      b.box(0.06, 0.22, 0.06, 0.08, 4.18, 1.18, K); b.box(0.06, 0.22, 0.06, -0.08, 4.18, 1.18, K);
      b.box(0.07, 0.8, 0.07, 0, 1.7, -0.64, K, 0.25);
    }),
    ...legs,
  ];
}

export function lionParts() {
  const T = '#d7a24f', M = '#8b5625', L = '#ecd09a', K = '#2a1e16';
  return [
    part('body', [0, 0, 0], b => {
      b.box(0.5, 0.46, 1.2, 0, 0.74, 0, T);
      b.box(0.66, 0.68, 0.46, 0, 0.92, 0.56, M);                   // mane
      b.box(0.44, 0.42, 0.4, 0, 0.98, 0.82, T);
      b.box(0.26, 0.18, 0.16, 0, 0.9, 1.06, L);
      b.box(0.1, 0.07, 0.04, 0, 0.97, 1.15, K);
      b.box(0.1, 0.1, 0.06, 0.15, 1.24, 0.76, T); b.box(0.1, 0.1, 0.06, -0.15, 1.24, 0.76, T);
      b.box(0.07, 0.07, 0.75, 0, 0.82, -0.9, T, -0.5);
      b.box(0.13, 0.13, 0.18, 0, 1.03, -1.25, M);
    }),
    ...quadLegs(0.16, 0.52, 0.17, 0.17, 0.44, T, T, L),
  ];
}

export function birdParts(body = '#3a3330', wing = '#262220', head = '#e8dcc6') {
  return [
    part('body', [0, 0, 0], b => {
      b.box(0.18, 0.14, 0.5, 0, 0, 0, body);
      b.box(0.12, 0.12, 0.16, 0, 0.05, 0.3, head);
      b.box(0.05, 0.04, 0.12, 0, 0.03, 0.42, '#d99a3a');
      b.box(0.2, 0.03, 0.2, 0, 0, -0.32, wing);
    }),
    part('wingR', [0.08, 0.04, 0], b => { b.box(0.7, 0.035, 0.3, 0.43, 0.04, 0, wing); b.box(0.3, 0.03, 0.22, 0.9, 0.04, -0.03, wing); }),
    part('wingL', [-0.08, 0.04, 0], b => { b.box(0.7, 0.035, 0.3, -0.43, 0.04, 0, wing); b.box(0.3, 0.03, 0.22, -0.9, 0.04, -0.03, wing); }),
  ];
}

// ------------------------------------------------------------------ plants and rocks

export function acaciaGeo(v) {
  const b = new Builder();
  const BARK = '#6a4a34', L1 = '#7d9640', L2 = '#8fa84a', L3 = '#6b8236';
  const lean = [0.12, -0.1, 0.05][v % 3], hgt = [3.3, 3.9, 2.9][v % 3];
  b.cyl(0.16, 0.26, hgt, hgt * lean * 0.5, hgt / 2, 0, BARK, 6, 0, 0, -lean);
  const tx = hgt * lean, ty = hgt;
  b.cyl(0.08, 0.14, 1.5, tx + 0.55, ty + 0.25, 0.1, BARK, 5, 0, 0, -0.9);
  b.cyl(0.08, 0.14, 1.4, tx - 0.5, ty + 0.2, -0.15, BARK, 5, 0, 0, 0.9);
  b.cyl(0.07, 0.12, 1.1, tx, ty + 0.3, 0.45, BARK, 5, 0.8, 0, 0);
  const R = [2.5, 2.9, 2.2][v % 3];
  b.ball(1, tx, ty + 0.85, 0, L1, R, 0.36, R * 0.9);
  b.ball(1, tx + R * 0.4, ty + 1.12, 0.3, L2, R * 0.62, 0.3, R * 0.6);
  b.ball(1, tx - R * 0.45, ty + 1.05, -0.4, L2, R * 0.55, 0.28, R * 0.55);
  b.ball(1, tx + 0.2, ty + 0.62, -0.2, L3, R * 0.8, 0.2, R * 0.75);
  return b.build();
}

export function burntTreeGeo() {
  const b = new Builder();
  const K = '#2a2420', K2 = '#3a322c';
  b.cyl(0.14, 0.25, 3.0, 0.1, 1.5, 0, K, 6, 0, 0, -0.07);
  b.cyl(0.06, 0.12, 1.5, 0.75, 3.1, 0.1, K2, 5, 0, 0, -0.9);
  b.cyl(0.06, 0.12, 1.3, -0.4, 3.0, -0.15, K2, 5, 0, 0, 0.9);
  b.cyl(0.05, 0.1, 1.0, 0.2, 3.2, 0.4, K2, 5, 0.8, 0, 0);
  return b.build();
}

export function baobabGeo() {
  const b = new Builder();
  const BARK = '#a3836a', BARK2 = '#8d6f58', L = '#7f9a45', L2 = '#93ad52';
  b.cyl(0.85, 1.15, 2.2, 0, 1.1, 0, BARK, 9);
  b.cyl(0.6, 0.85, 1.6, 0, 3.0, 0, BARK, 9);
  const arms = [[0.9, 0.2], [-0.8, 0.5], [0.2, -0.9], [-0.3, 0.85], [0.75, -0.6]];
  for (const [x, z] of arms) {
    const a = Math.atan2(z, x);
    b.cyl(0.12, 0.24, 1.5, x * 0.75, 4.15, z * 0.75, BARK2, 5, Math.sin(a) * 0.75, 0, -Math.cos(a) * 0.75);
    b.ball(0.62, x * 1.45, 4.9, z * 1.45, L, 1, 0.6, 1);
    b.ball(0.42, x * 1.1, 5.2, z * 1.1, L2, 1, 0.6, 1);
  }
  return b.build();
}

export function bushGeo() {
  const b = new Builder();
  b.ball(0.55, 0, 0.42, 0, '#6f8f3c', 1, 0.8, 1);
  b.ball(0.42, 0.42, 0.34, 0.2, '#7b9b44', 1, 0.8, 1);
  b.ball(0.38, -0.36, 0.3, -0.25, '#648436', 1, 0.8, 1);
  return b.build();
}
export function berriesGeo() {
  const b = new Builder();
  for (const [x, y, z] of [[0.2, 0.82, 0.25], [-0.25, 0.75, 0.2], [0.05, 0.9, -0.2], [0.55, 0.6, 0.35], [-0.5, 0.52, -0.3], [0.3, 0.7, -0.35], [-0.1, 0.78, 0.42]])
    b.box(0.13, 0.13, 0.13, x, y, z, '#c7352f', 0.5, 0.5, 0);
  return b.build();
}
export function rockGeo(v) {
  const b = new Builder();
  const cols = ['#a69a8c', '#958a7d', '#b3a797'];
  if (v === 0) { b.ball(1, 0, 0.45, 0, cols[0], 1.0, 0.62, 0.8); b.ball(1, 0.7, 0.3, 0.3, cols[1], 0.55, 0.4, 0.5); }
  if (v === 1) { b.ball(1, 0, 0.7, 0, cols[1], 0.8, 0.95, 0.75); b.ball(1, -0.55, 0.3, 0.35, cols[2], 0.5, 0.38, 0.45); b.ball(1, 0.5, 0.25, -0.4, cols[0], 0.4, 0.3, 0.42); }
  if (v === 2) { b.ball(1, 0, 0.28, 0, cols[2], 0.62, 0.36, 0.5); }
  return b.build();
}
export function tuftGeo() {
  const b = new Builder();
  for (let i = 0; i < 5; i++) {
    const a = i * 1.26;
    b.box(0.07, 0.52, 0.03, Math.cos(a) * 0.14, 0.24, Math.sin(a) * 0.14, '#ffffff', Math.sin(a) * 0.35, a, Math.cos(a) * 0.35);
  }
  return b.build();
}
export function carcassGeo() {
  const b = new Builder();
  b.box(0.5, 0.3, 0.9, 0, 0.16, 0, '#9c4a3a');
  for (let i = 0; i < 4; i++) b.box(0.56, 0.06, 0.05, 0, 0.34, -0.3 + i * 0.2, '#efe6d2');
  b.box(0.2, 0.2, 0.3, 0, 0.14, 0.6, '#efe6d2');
  return b.build();
}

// ------------------------------------------------------------------ buildings
// Each returns { geo, glow } where glow is the geometry of the parts lit at night.

const THATCH = '#dcb962', THATCH_D = '#b9933f', MUD = '#cfa377', MUD_D = '#b0855b', WOOD = '#7b5a3c', STONE = '#cfc5b3', STONE_D = '#aca291';

export function shelterModel(tribe) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  b.box(1.9, 0.09, 1.7, 0.5, 0.62, 0, THATCH_D, 0, 0, 0.9);
  b.box(1.9, 0.09, 1.7, -0.5, 0.62, 0, THATCH, 0, 0, -0.9);
  b.box(0.08, 1.5, 0.08, 0, 0.75, 0.86, WOOD); b.box(0.08, 1.5, 0.08, 0, 0.75, -0.86, WOOD);
  b.box(0.1, 0.1, 1.9, 0, 1.3, 0, WOOD);
  b.box(0.3, 0.3, 0.06, 0, 1.5, 0.9, t.cloth, 0, 0, 0.78);
  g.box(0.5, 0.5, 0.05, 0, 0.3, 0.2, '#ffb14a');
  return { geo: b.build(), glow: g.build() };
}

export function hutModel(tribe) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  b.cyl(1.05, 1.1, 1.0, 0, 0.5, 0, MUD, 10);
  b.cyl(1.08, 1.08, 0.14, 0, 0.78, 0, t.cloth, 10);
  b.cyl(1.09, 1.09, 0.05, 0, 0.62, 0, t.accent, 10);
  b.cone(1.5, 1.35, 0, 1.62, 0, THATCH, 10);
  b.cone(0.75, 0.75, 0, 2.2, 0, THATCH_D, 10);
  b.box(0.06, 0.4, 0.06, 0, 2.7, 0, WOOD);
  b.box(0.5, 0.74, 0.1, 0, 0.37, 1.06, '#4a3423');
  g.box(0.4, 0.62, 0.06, 0, 0.35, 1.1, '#ffb14a');
  return { geo: b.build(), glow: g.build() };
}

export function houseModel(tribe) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  b.box(2.5, 1.5, 2.1, 0, 0.75, 0, MUD);
  b.box(2.7, 0.16, 2.3, 0, 1.56, 0, MUD_D);
  b.box(2.52, 0.18, 2.12, 0, 1.12, 0, t.cloth);
  for (let i = -4; i <= 4; i++) b.box(0.16, 0.16, 2.14, i * 0.28, 0.94, 0, i % 2 ? t.accent : t.dark);
  b.box(1.3, 0.95, 1.3, -0.5, 2.1, -0.3, MUD);
  b.box(1.45, 0.14, 1.45, -0.5, 2.62, -0.3, MUD_D);
  for (const [x, z] of [[1.25, 1.05], [-1.25, 1.05], [1.25, -1.05], [-1.25, -1.05]]) b.box(0.22, 0.34, 0.22, x, 1.78, z, MUD_D);
  for (let i = 0; i < 4; i++) b.box(0.12, 0.12, 0.5, 0.2 + i * 0.3, 1.4, 1.2, WOOD);   // roof beams
  b.box(0.56, 0.9, 0.1, 0.5, 0.45, 1.06, '#4a3423');
  b.box(0.08, 1.7, 0.08, 1.0, 0.85, 1.2, WOOD, 0, 0, 0.12); b.box(0.08, 1.7, 0.08, 1.3, 0.85, 1.2, WOOD, 0, 0, 0.12);
  g.box(0.44, 0.76, 0.06, 0.5, 0.42, 1.1, '#ffb14a');
  g.box(0.34, 0.34, 0.06, -0.6, 0.85, 1.08, '#ffb14a');
  g.box(0.3, 0.3, 0.06, -0.5, 2.15, 0.37, '#ffb14a');
  return { geo: b.build(), glow: g.build() };
}

export function stoneHouseModel(tribe) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  b.box(2.8, 1.7, 2.3, 0, 0.85, 0, STONE);
  for (let i = 0; i < 3; i++) b.box(2.84, 0.06, 2.34, 0, 0.4 + i * 0.45, 0, STONE_D);
  b.box(3.0, 0.2, 2.5, 0, 1.78, 0, STONE_D);
  b.box(2.0, 1.25, 1.7, 0, 2.5, 0, STONE);
  b.cone(1.75, 1.3, 0, 3.75, 0, t.cloth, 4, 0, Math.PI / 4);
  b.cone(0.5, 0.5, 0, 4.45, 0, t.accent, 4, 0, Math.PI / 4);
  b.box(0.06, 1.1, 0.06, 1.2, 2.4, 1.0, WOOD);
  b.box(0.5, 0.32, 0.04, 1.47, 2.76, 1.0, t.cloth);
  b.box(0.7, 1.05, 0.1, 0, 0.52, 1.16, '#4a3423');
  b.box(0.9, 0.14, 0.2, 0, 1.12, 1.18, t.accent);
  g.box(0.56, 0.9, 0.06, 0, 0.5, 1.2, '#ffc15e');
  g.box(0.36, 0.42, 0.06, 0.9, 0.95, 1.17, '#ffc15e'); g.box(0.36, 0.42, 0.06, -0.9, 0.95, 1.17, '#ffc15e');
  g.box(0.34, 0.4, 0.06, 0.45, 2.5, 0.87, '#ffc15e'); g.box(0.34, 0.4, 0.06, -0.45, 2.5, 0.87, '#ffc15e');
  g.box(0.06, 0.4, 0.34, 1.42, 0.95, 0, '#ffc15e'); g.box(0.06, 0.4, 0.34, -1.42, 0.95, 0, '#ffc15e');
  return { geo: b.build(), glow: g.build() };
}

export function bonfireModel() {
  const b = new Builder(), g = new Builder();
  for (let i = 0; i < 8; i++) { const a = i * 0.785; b.ball(0.2, Math.cos(a) * 0.7, 0.1, Math.sin(a) * 0.7, i % 2 ? '#9c9287' : '#b3a898', 1, 0.7, 1); }
  for (let i = 0; i < 4; i++) { const a = i * 0.785; b.box(0.14, 0.14, 1.1, 0, 0.14 + i * 0.03, 0, '#5f432c', 0.12, a, 0); }
  g.cone(0.3, 0.7, 0, 0.5, 0, '#ffb347', 5);
  return { geo: b.build(), glow: g.build() };
}

export function totemModel(tribe, era) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  const h = [0, 2.6, 3.4, 4.4, 5.6][era];
  b.cyl(0.5, 0.6, 0.3, 0, 0.15, 0, STONE_D, 8);
  b.box(0.42, h, 0.42, 0, 0.3 + h / 2, 0, WOOD);
  const cols = [t.cloth, t.accent, t.dark, t.cloth, t.accent];
  for (let i = 0; i < Math.floor(h / 0.9); i++) {
    const y = 0.75 + i * 0.9;
    b.box(0.56, 0.42, 0.56, 0, y, 0, cols[i % 5]);
    b.box(0.12, 0.1, 0.04, 0.12, y + 0.05, 0.29, '#f6f1e6'); b.box(0.12, 0.1, 0.04, -0.12, y + 0.05, 0.29, '#f6f1e6');
    b.box(0.3, 0.06, 0.04, 0, y - 0.1, 0.29, HAIR);
  }
  b.box(1.9, 0.14, 0.2, 0, 0.3 + h - 0.35, 0, t.cloth);
  b.box(0.3, 0.42, 0.22, 0.95, 0.3 + h - 0.2, 0, t.accent); b.box(0.3, 0.42, 0.22, -0.95, 0.3 + h - 0.2, 0, t.accent);
  b.cone(0.34, 0.5, 0, 0.3 + h + 0.25, 0, t.accent, 4, 0, Math.PI / 4);
  return { geo: b.build(), glow: g.build() };
}

export function granaryModel(tribe) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  for (const [x, z] of [[0.5, 0.5], [-0.5, 0.5], [0.5, -0.5], [-0.5, -0.5]]) b.box(0.1, 0.8, 0.1, x, 0.4, z, WOOD);
  b.box(1.4, 0.1, 1.4, 0, 0.82, 0, WOOD);
  b.cyl(0.6, 0.72, 1.1, 0, 1.42, 0, MUD, 9);
  b.cyl(0.74, 0.74, 0.1, 0, 1.5, 0, t.accent, 9);
  b.cone(0.95, 0.9, 0, 2.4, 0, THATCH, 9);
  return { geo: b.build(), glow: g.build() };
}

export function towerModel(tribe) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  for (const [x, z] of [[0.6, 0.6], [-0.6, 0.6], [0.6, -0.6], [-0.6, -0.6]]) b.box(0.14, 3.6, 0.14, x * 0.9, 1.8, z * 0.9, WOOD, z * 0.06, 0, -x * 0.06);
  b.box(1.5, 0.08, 0.1, 0, 1.3, 0.6, WOOD, 0, 0, 0.5); b.box(1.5, 0.08, 0.1, 0, 1.3, -0.6, WOOD, 0, 0, -0.5);
  b.box(1.7, 0.14, 1.7, 0, 3.6, 0, WOOD);
  for (const [x, z, w, d] of [[0, 0.8, 1.7, 0.08], [0, -0.8, 1.7, 0.08], [0.8, 0, 0.08, 1.7], [-0.8, 0, 0.08, 1.7]]) b.box(w, 0.5, d, x, 3.9, z, '#94714c');
  b.cone(1.5, 1.0, 0, 5.3, 0, THATCH, 4, 0, Math.PI / 4);
  for (const [x, z] of [[0.7, 0.7], [-0.7, 0.7], [0.7, -0.7], [-0.7, -0.7]]) b.box(0.08, 1.2, 0.08, x, 4.3, z, WOOD);
  b.box(0.05, 1.2, 0.05, 0, 6.3, 0, WOOD);
  b.box(0.6, 0.36, 0.04, 0.32, 6.65, 0, t.cloth);
  g.box(0.3, 0.3, 0.3, 0, 4.0, 0, '#ffb14a');
  return { geo: b.build(), glow: g.build() };
}

export function hallModel(tribe) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  b.box(7.4, 0.5, 6.2, 0, 0.25, 0, STONE_D);
  b.box(6.4, 0.5, 5.2, 0, 0.75, 0, STONE);
  b.box(5.0, 2.4, 3.8, 0, 2.2, -0.2, STONE);
  for (let i = 0; i < 4; i++) b.box(5.04, 0.07, 3.84, 0, 1.4 + i * 0.55, -0.2, STONE_D);
  b.box(5.6, 0.3, 4.4, 0, 3.55, -0.2, t.dark);
  b.box(4.4, 1.0, 3.2, 0, 4.2, -0.2, STONE);
  b.cone(3.4, 1.9, 0, 5.65, -0.2, t.cloth, 4, 0, Math.PI / 4);
  b.cone(1.1, 0.9, 0, 6.9, -0.2, t.accent, 4, 0, Math.PI / 4);
  for (const x of [-2.1, -0.75, 0.75, 2.1]) {
    b.cyl(0.24, 0.28, 2.5, x, 2.25, 2.1, STONE, 8);
    b.box(0.7, 0.2, 0.7, x, 3.5, 2.1, t.accent);
  }
  b.box(5.6, 0.3, 1.0, 0, 3.75, 2.1, t.dark);
  for (let i = 0; i < 3; i++) b.box(3.2 - i * 0.3, 0.17, 0.5, 0, 0.92 - i * 0.34 + 0.34, 2.9 + i * 0.4, STONE_D);
  b.box(1.2, 1.7, 0.1, 0, 1.85, 1.72, '#4a3423');
  for (const x of [-3.2, 3.2]) { b.box(0.08, 3.4, 0.08, x, 2.4, 2.6, WOOD); b.box(0.06, 1.3, 0.7, x, 3.3, 2.98, t.cloth); b.box(0.065, 0.3, 0.72, x, 3.1, 2.98, t.accent); }
  g.box(1.0, 1.5, 0.06, 0, 1.8, 1.76, '#ffc15e');
  for (const x of [-1.7, 1.7]) g.box(0.5, 0.7, 0.06, x, 2.3, 1.72, '#ffc15e');
  for (const x of [-1.4, 0, 1.4]) g.box(0.5, 0.42, 0.06, x, 4.25, 1.41, '#ffc15e');
  return { geo: b.build().scale(0.84, 0.84, 0.84), glow: g.build().scale(0.84, 0.84, 0.84) };
}

export function stallModel(tribe, v) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  const cloth = [t.cloth, t.accent, '#e28a3c', '#5aa77a'][v % 4];
  for (const [x, z] of [[0.8, 0.6], [-0.8, 0.6], [0.8, -0.6], [-0.8, -0.6]]) b.box(0.08, 1.5, 0.08, x, 0.75, z, WOOD);
  b.box(2.0, 0.08, 1.6, 0, 1.6, 0.1, cloth, 0.18);
  b.box(2.0, 0.085, 0.3, 0, 1.47, 0.82, '#f4efe2', 0.18);
  b.box(1.6, 0.5, 0.8, 0, 0.3, 0, '#a98350');
  for (let i = 0; i < 4; i++) b.box(0.25, 0.2, 0.25, -0.55 + i * 0.37, 0.65, 0.1, ['#c7352f', '#e0b23c', '#8fae4a', '#d1583a'][i]);
  return { geo: b.build(), glow: g.build() };
}

export function fieldModel() {
  const b = new Builder(), g = new Builder();
  b.box(4.2, 0.12, 3.4, 0, 0.02, 0, '#7a5435');
  for (let i = 0; i < 6; i++) {
    b.box(0.34, 0.1, 3.1, -1.75 + i * 0.7, 0.1, 0, '#8b6340');
    for (let k = 0; k < 7; k++) b.box(0.2, 0.34, 0.2, -1.75 + i * 0.7, 0.3, -1.35 + k * 0.45, k % 2 ? '#86b04a' : '#9cc257');
  }
  return { geo: b.build(), glow: g.build() };
}

// Ring wall: wooden stakes (era 3) or stone with towers (era 4). The gate faces gateAngle.
export function wallModel(tribe, era, R, gateAngle) {
  const t = TRIBES[tribe], b = new Builder(), g = new Builder();
  const gap = 0.3;
  if (era === 3) {
    const n = Math.floor((2 * Math.PI * R) / 0.42);
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2;
      let d = Math.abs(a - gateAngle); if (d > Math.PI) d = 2 * Math.PI - d;
      if (d < gap) continue;
      const hh = 1.5 + ((i * 7) % 5) * 0.07;
      const x = Math.cos(a) * R, z = Math.sin(a) * R;
      b.box(0.34, hh, 0.34, x, hh / 2, z, i % 3 ? '#8a6744' : '#7a5a3a', 0, -a, 0);
      b.cone(0.24, 0.4, x, hh + 0.2, z, '#94714c', 4, 0, -a);
    }
    for (const s of [-1, 1]) {
      const a = gateAngle + s * gap, x = Math.cos(a) * R, z = Math.sin(a) * R;
      b.box(0.4, 2.6, 0.4, x, 1.3, z, WOOD);
      b.box(0.5, 0.3, 0.04, x, 2.9, z, t.cloth, 0, -a + Math.PI / 2, 0);
    }
  } else {
    const n = Math.floor((2 * Math.PI * R) / 0.9);
    for (let i = 0; i < n; i++) {
      const a = ((i + 0.5) / n) * Math.PI * 2;
      let d = Math.abs(a - gateAngle); if (d > Math.PI) d = 2 * Math.PI - d;
      if (d < gap * 0.8) continue;
      const x = Math.cos(a) * R, z = Math.sin(a) * R;
      b.box(0.7, 1.9, 1.0, x, 0.95, z, i % 2 ? STONE : '#c4b9a6', 0, -a, 0);
      if (i % 2) b.box(0.74, 0.4, 0.5, x, 2.1, z, STONE_D, 0, -a, 0);
    }
    for (let k = 0; k < 6; k++) {
      const a = gateAngle + gap * 0.9 + (k / 6) * (Math.PI * 2 - gap * 1.8) + (k === 0 ? 0 : 0);
      const x = Math.cos(a) * R, z = Math.sin(a) * R;
      b.cyl(0.95, 1.05, 3.0, x, 1.5, z, STONE, 8);
      b.cyl(1.1, 1.1, 0.3, x, 3.1, z, STONE_D, 8);
      b.cone(1.2, 1.3, x, 3.9, z, t.cloth, 8);
      g.box(0.3, 0.4, 0.3, x * 1.07, 2.2, z * 1.07, '#ffc15e');
    }
    const a2 = gateAngle - gap * 0.9, x2 = Math.cos(a2) * R, z2 = Math.sin(a2) * R;
    b.cyl(0.95, 1.05, 3.0, x2, 1.5, z2, STONE, 8); b.cyl(1.1, 1.1, 0.3, x2, 3.1, z2, STONE_D, 8); b.cone(1.2, 1.3, x2, 3.9, z2, t.cloth, 8);
    const gx = Math.cos(gateAngle) * R, gz = Math.sin(gateAngle) * R;
    b.box(0.8, 0.6, 2 * R * Math.sin(gap * 0.9) , gx, 2.7, gz, STONE_D, 0, -gateAngle, 0);
    b.box(0.82, 0.5, 0.9, gx, 3.2, gz, t.accent, 0, -gateAngle, 0);
  }
  return { geo: b.build(), glow: g.build() };
}
