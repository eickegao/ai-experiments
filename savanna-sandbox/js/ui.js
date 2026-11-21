// Interface: title, tribe cards, the god-power toolbar, speed buttons, toasts, and the brush ring.
import * as THREE from '../vendor/three/three.module.js';
import { TRIBES } from './models.js';

const STR = {
  zh: {
    title: '草原沙盘', sub: '你是这片草原的神', day: n => `第 ${n} 天`,
    tribes: ['赤岩部落', '蓝河部落'], eras: ['', '营地', '村落', '城寨', '王城'], pop: '人口', food: '粮食',
    tools: { hand: '移动', rotate: '旋转', rain: '降雨', lightning: '闪电', meteor: '陨石', raise: '隆起', lower: '下陷', herd: '兽群', drought: '干旱', storm: '暴雨', war: '战鼓' },
    toast: { era: (t, e) => `${t}进入「${e}」时代`, war: '战鼓响起，两个部落开战', peace: t => (t ? `${t}赢得了这场战争` : '战争结束，双方退兵'), drought: '大旱降临，河水开始退去', storm: '暴雨来了' },
    hint: '拖动移动地图 · 滚轮缩放 · 右键拖动旋转 · WASD 也能移动',
    animals: '动物',
  },
  en: {
    title: 'Savanna Sandbox', sub: 'You are the god of this grassland', day: n => `Day ${n}`,
    tribes: ['Redrock', 'Blueriver'], eras: ['', 'Camp', 'Village', 'Town', 'Kingdom'], pop: 'People', food: 'Food',
    tools: { hand: 'Move', rotate: 'Rotate', rain: 'Rain', lightning: 'Lightning', meteor: 'Meteor', raise: 'Raise', lower: 'Lower', herd: 'Herd', drought: 'Drought', storm: 'Storm', war: 'War drum' },
    toast: { era: (t, e) => `${t} enters the ${e} age`, war: 'War drums: the tribes march', peace: t => (t ? `${t} wins the war` : 'The war ends in a draw'), drought: 'Drought. The river is falling', storm: 'A storm rolls in' },
    hint: 'Drag to move the map · Scroll to zoom · Right-drag to rotate · WASD also moves',
    animals: 'Animals',
  },
};

const ICON = {
  hand: '<path d="M12 2l3.5 4h-2.5v5h5V8.5l4 3.5l-4 3.5V13h-5v5h2.5L12 22l-3.5-4H11v-5H6v2.5L2 12l4-3.5V11h5V6H8.5z"/>',
  rotate: '<path d="M12 4a8 8 0 1 0 7.7 10.2h-2.1A6 6 0 1 1 12 6c1.6 0 3 .6 4.1 1.7L13 11h8V3l-3.5 3.3A8 8 0 0 0 12 4z"/>',
  rain: '<path d="M7 13a4 4 0 0 1 .6-8A5 5 0 0 1 17 6.2A3.5 3.5 0 0 1 17 13z"/><path d="M8 15l-1 3M12 15l-1 4M16 15l-1 3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/>',
  lightning: '<path d="M13 2L5 13h5l-1 9l8-12h-5z"/>',
  meteor: '<circle cx="15" cy="15" r="5"/><path d="M3 3l8 6M6 2l6 5M2 7l7 4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/>',
  raise: '<path d="M2 19l7-11l4 5l2-3l7 9z"/><path d="M12 6V1m-3 3l3-3l3 3" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round"/>',
  lower: '<path d="M2 9h5l5 9l5-9h5v11H2z"/><path d="M12 2v6m-3-3l3 3l3-3" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round"/>',
  herd: '<path d="M4 10h11l3-4h2v4l-2 2v7h-2v-5H8v5H6v-6z"/>',
  drought: '<circle cx="12" cy="12" r="4.5"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  storm: '<path d="M7 12a4 4 0 0 1 .6-8A5 5 0 0 1 17 5.2A3.5 3.5 0 0 1 17 12z"/><path d="M12 13l-3 5h3l-1 4l4-6h-3l1-3z"/>',
  war: '<path d="M4 3l9 9l-2 2l-9-9zM20 3l-9 9l2 2l9-9zM4 21l4-4M20 21l-4-4" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/>',
};
const AREA_TOOLS = ['rain', 'lightning', 'meteor', 'raise', 'lower', 'herd'];
const RADIUS = { rain: 24, lightning: 2.5, meteor: 13, raise: 12, lower: 12, herd: 6 };

export function createUI(G, lang) {
  const L = STR[lang] || STR.en;
  const { stage, terrain: T } = G;
  const root = document.getElementById('ui');
  const U = { tool: 'hand', L };
  const el = (tag, cls, html = '') => { const e = document.createElement(tag); e.className = cls; e.innerHTML = html; return e; };

  const head = el('div', 'head', `<h1>${L.title}</h1><p>${L.sub}</p><div class="day"></div>`);
  const cards = el('div', 'cards');
  const cardEls = G.tribes.tribes.map((t, i) => {
    const c = el('div', 'card', `<div class="dot" style="background:${TRIBES[i].cloth}"></div><div class="name">${L.tribes[i]}</div><div class="era"></div>
      <div class="row"><span>${L.pop}</span><b class="pop"></b></div><div class="row"><span>${L.food}</span><b class="food"></b></div>`);
    cards.appendChild(c);
    return c;
  });
  const wild = el('div', 'card wild', `<div class="row"><span>${L.animals}</span><b class="n"></b></div>`);
  cards.appendChild(wild);
  const bar = el('div', 'bar');
  const buttons = {};
  for (const k of Object.keys(ICON)) {
    const b = el('button', 'tool', `<svg viewBox="0 0 24 24" fill="currentColor">${ICON[k]}</svg><span>${L.tools[k]}</span>`);
    b.onclick = () => {
      if (AREA_TOOLS.includes(k) || k === 'hand' || k === 'rotate') U.setTool(k);
      else { G.env.powers[k](); flash(b); }
    };
    buttons[k] = b;
    bar.appendChild(b);
    if (k === 'rotate' || k === 'herd') bar.appendChild(el('i', 'sep'));
  }
  const speed = el('div', 'speed');
  const speedBtns = [[0, '❙❙'], [1, '1×'], [4, '4×'], [16, '16×']].map(([s, label]) => {
    const b = el('button', 'spd', label);
    b.onclick = () => { G.paused = s === 0; if (s) G.setSpeed(s); };
    speed.appendChild(b);
    return [s, b];
  });
  const toasts = el('div', 'toasts');
  const hint = el('div', 'hint', L.hint);
  root.append(head, cards, bar, speed, toasts, hint);
  const flash = (b) => { b.classList.add('hit'); setTimeout(() => b.classList.remove('hit'), 350); };

  U.setTool = (k) => {
    U.tool = k;
    if (k === 'hand') stage.dragMode = 'pan';
    if (k === 'rotate') stage.dragMode = 'orbit';
    for (const n in buttons) buttons[n].classList.toggle('on', n === k);
    ring.visible = false;
  };

  U.toast = (kind, tribe) => {
    let text = L.toast[kind];
    if (kind === 'era') text = L.toast.era(L.tribes[tribe.id], L.eras[tribe.era]);
    if (kind === 'peace') text = L.toast.peace(tribe ? L.tribes[tribe.id] : null);
    const t = el('div', 'toast', text);
    if (tribe) t.style.borderColor = TRIBES[tribe.id].cloth;
    toasts.appendChild(t);
    setTimeout(() => t.classList.add('out'), 3600);
    setTimeout(() => t.remove(), 4300);
  };

  // brush ring that hugs the terrain
  const SEG = 48;
  const ringGeo = new THREE.BufferGeometry();
  ringGeo.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array((SEG + 1) * 3), 3));
  const ring = new THREE.Line(ringGeo, new THREE.LineBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.9, depthTest: false }));
  ring.renderOrder = 10; ring.visible = false; ring.frustumCulled = false;
  stage.scene.add(ring);
  const moveRing = (pt) => {
    const r = RADIUS[U.tool] || 3, pos = ringGeo.attributes.position;
    for (let i = 0; i <= SEG; i++) {
      const a = (i / SEG) * Math.PI * 2, x = pt.x + Math.cos(a) * r, z = pt.z + Math.sin(a) * r;
      pos.setXYZ(i, x, Math.max(T.height(x, z), T.waterLevel) + 0.25, z);
    }
    pos.needsUpdate = true;
    ring.visible = true;
  };

  let held = null;
  stage.onPointer = (type, e) => {
    if (U.tool === 'hand' || U.tool === 'rotate') return false;
    const pt = stage.pick(e, T);
    if (type === 'hover') { if (pt) moveRing(pt); else ring.visible = false; return false; }
    if (type === 'up') { held = null; return true; }
    if (!pt) return type === 'drag';
    moveRing(pt);
    if (type === 'down') {
      if (U.tool === 'raise' || U.tool === 'lower') held = pt;
      else G.env.powers[U.tool](pt.x, pt.z);
      return true;
    }
    if (type === 'drag' && held) held = pt;
    return true;
  };

  let slow = 0;
  U.render = (real) => {
    if (held) G.env.powers[U.tool](held.x, held.z, real);
    slow -= real;
    if (slow > 0) return;
    slow = 0.25;
    head.querySelector('.day').textContent = L.day(G.day);
    G.tribes.tribes.forEach((t, i) => {
      const c = cardEls[i];
      c.querySelector('.era').textContent = L.eras[t.era];
      c.querySelector('.pop').textContent = t.people.length;
      c.querySelector('.food').textContent = Math.round(t.food);
    });
    wild.querySelector('.n').textContent = G.animals.all.length;
    for (const [s, b] of speedBtns) b.classList.toggle('on', G.paused ? s === 0 : s === G.speed);
    buttons.drought.classList.toggle('on', G.env.drought > 0);
    buttons.war.classList.toggle('on', !!G.tribes.war);
    buttons.storm.classList.toggle('on', G.env.storm > 0);
  };
  U.setTool('hand');
  return U;
}
