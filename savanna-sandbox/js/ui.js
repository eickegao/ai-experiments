// Interface: title, the two peoples' cards, the tool bar (move / rotate / god powers),
// speed buttons, the settings panel, toasts, and the brush ring.
import * as THREE from '../vendor/three/three.module.js';
import { TRIBES } from './models.js';

const STR = {
  zh: {
    title: '草原沙盘', sub: '你是这片草原的神', day: n => `第 ${n} 天`,
    tribes: ['赤岩人', '蓝河人'], eras: ['', '营地', '村落', '城寨', '王城'], pop: '人口', food: '粮食', wood: '木头', stone: '石头', towns: '聚落',
    tools: { hand: '移动', rotate: '旋转', rain: '降雨', lightning: '闪电', meteor: '陨石', tornado: '龙卷风', plague: '瘟疫', bless: '祝福', raise: '隆起', lower: '下陷', herd: '兽群', drought: '干旱', storm: '暴雨', war: '战鼓' },
    toast: {
      era: (t, e) => `${t}进入「${e}」时代`, war: '战鼓响起，两族开战', peace: t => (t ? `${t}赢得了这场战争` : '战争结束，双方退兵'),
      drought: '大旱降临，河水开始退去', storm: '暴雨来了', plague: '瘟疫开始蔓延', colony: t => `${t}派人外出，建立了新的聚落`,
    },
    hint: '拖动移动地图 · 滚轮缩放 · 右键拖动旋转 · WASD 也能移动',
    animals: '动物', settings: '设置',
    set: {
      day: '昼夜', dayOpts: { cycle: '昼夜交替', day: '永远白天', night: '永远黑夜' }, sound: '声音', volume: '音量',
      predators: '猛兽会吃人', nature: '大自然自己降灾（雷雨、干旱）', colonies: '人多了外出建新聚落', haze: '远处起雾', labels: '显示界面文字提示',
    },
  },
  en: {
    title: 'Savanna Sandbox', sub: 'You are the god of this grassland', day: n => `Day ${n}`,
    tribes: ['Redrock', 'Blueriver'], eras: ['', 'Camp', 'Village', 'Town', 'Kingdom'], pop: 'People', food: 'Food', wood: 'Wood', stone: 'Stone', towns: 'Towns',
    tools: { hand: 'Move', rotate: 'Rotate', rain: 'Rain', lightning: 'Lightning', meteor: 'Meteor', tornado: 'Tornado', plague: 'Plague', bless: 'Bless', raise: 'Raise', lower: 'Lower', herd: 'Herd', drought: 'Drought', storm: 'Storm', war: 'War drum' },
    toast: {
      era: (t, e) => `${t} enters the ${e} age`, war: 'War drums: the two peoples march', peace: t => (t ? `${t} wins the war` : 'The war ends in a draw'),
      drought: 'Drought. The river is falling', storm: 'A storm rolls in', plague: 'A plague is spreading', colony: t => `${t} sends settlers out to found a new town`,
    },
    hint: 'Drag to move the map · Scroll to zoom · Right-drag to rotate · WASD also moves',
    animals: 'Animals', settings: 'Settings',
    set: {
      day: 'Day and night', dayOpts: { cycle: 'Day and night', day: 'Always day', night: 'Always night' }, sound: 'Sound', volume: 'Volume',
      predators: 'Predators eat people', nature: 'Nature strikes on its own (storms, drought)', colonies: 'Big towns found new ones', haze: 'Distance haze', labels: 'Show the hint line',
    },
  },
};

const ICON = {
  hand: '<path d="M12 2l3.5 4h-2.5v5h5V8.5l4 3.5l-4 3.5V13h-5v5h2.5L12 22l-3.5-4H11v-5H6v2.5L2 12l4-3.5V11h5V6H8.5z"/>',
  rotate: '<path d="M12 4a8 8 0 1 0 7.7 10.2h-2.1A6 6 0 1 1 12 6c1.6 0 3 .6 4.1 1.7L13 11h8V3l-3.5 3.3A8 8 0 0 0 12 4z"/>',
  rain: '<path d="M7 13a4 4 0 0 1 .6-8A5 5 0 0 1 17 6.2A3.5 3.5 0 0 1 17 13z"/><path d="M8 15l-1 3M12 15l-1 4M16 15l-1 3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/>',
  lightning: '<path d="M13 2L5 13h5l-1 9l8-12h-5z"/>',
  meteor: '<circle cx="15" cy="15" r="5"/><path d="M3 3l8 6M6 2l6 5M2 7l7 4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/>',
  tornado: '<path d="M3 4h18M5 8h14M7 12h10M9 16h6M11 20h3" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/>',
  plague: '<circle cx="12" cy="12" r="5"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4M5 5l3 3M16 16l3 3M19 5l-3 3M8 16l-3 3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  bless: '<path d="M12 2l2.4 6.2L21 9l-5 4.3L17.6 20L12 16.4L6.4 20L8 13.3L3 9l6.6-.8z"/>',
  raise: '<path d="M2 19l7-11l4 5l2-3l7 9z"/><path d="M12 6V1m-3 3l3-3l3 3" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round"/>',
  lower: '<path d="M2 9h5l5 9l5-9h5v11H2z"/><path d="M12 2v6m-3-3l3 3l3-3" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round"/>',
  herd: '<path d="M4 10h11l3-4h2v4l-2 2v7h-2v-5H8v5H6v-6z"/>',
  drought: '<circle cx="12" cy="12" r="4.5"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  storm: '<path d="M7 12a4 4 0 0 1 .6-8A5 5 0 0 1 17 5.2A3.5 3.5 0 0 1 17 12z"/><path d="M12 13l-3 5h3l-1 4l4-6h-3l1-3z"/>',
  war: '<path d="M4 3l9 9l-2 2l-9-9zM20 3l-9 9l2 2l9-9zM4 21l4-4M20 21l-4-4" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/>',
};
const GEAR = '<path d="M19.4 13a7.5 7.5 0 0 0 0-2l2-1.6l-2-3.4l-2.4 1a7.6 7.6 0 0 0-1.7-1L15 3.5h-4l-.3 2.5a7.6 7.6 0 0 0-1.7 1l-2.4-1l-2 3.4l2 1.6a7.5 7.5 0 0 0 0 2l-2 1.6l2 3.4l2.4-1c.5.4 1.1.8 1.7 1l.3 2.5h4l.3-2.5c.6-.2 1.2-.6 1.7-1l2.4 1l2-3.4zM13 15.2a3.2 3.2 0 1 1 0-6.4a3.2 3.2 0 0 1 0 6.4z" transform="translate(-1 0)"/>';
const AREA_TOOLS = ['rain', 'lightning', 'meteor', 'tornado', 'plague', 'bless', 'raise', 'lower', 'herd'];
const RADIUS = { rain: 24, lightning: 2.5, meteor: 13, tornado: 3, plague: 14, bless: 26, raise: 12, lower: 12, herd: 6 };

export function createUI(G, lang) {
  const L = STR[lang] || STR.en;
  const { stage, terrain: T } = G;
  const root = document.getElementById('ui');
  const U = { tool: 'hand', L };
  const el = (tag, cls, html = '') => { const e = document.createElement(tag); e.className = cls; e.innerHTML = html; return e; };

  const head = el('div', 'head', `<h1>${L.title}</h1><p>${L.sub}</p><div class="day"></div>`);
  const cards = el('div', 'cards');
  const cardEls = [0, 1].map((i) => {
    const c = el('div', 'card', `<div class="dot" style="background:${TRIBES[i].cloth}"></div><div class="name">${L.tribes[i]}</div><div class="era"></div>
      <div class="row"><span>${L.pop}</span><b class="pop"></b></div><div class="row"><span>${L.food}</span><b class="food"></b></div>
      <div class="row"><span>${L.wood}</span><b class="wood"></b></div><div class="row"><span>${L.stone}</span><b class="stone"></b></div>
      <div class="row"><span>${L.towns}</span><b class="towns"></b></div>`);
    c.style.cursor = 'pointer';
    c.onclick = () => { const t = G.tribes.tribes.filter(v => v.color === i).sort((a, b) => b.people.length - a.people.length)[c.dataset.n = ((+c.dataset.n || 0) + 1) % G.tribes.tribes.filter(v => v.color === i).length]; if (t) { stage.cam.tx = t.x; stage.cam.tz = t.z; } };
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
      G.sfx('click');
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
  const gear = el('button', 'spd gear', `<svg viewBox="0 0 24 24" fill="currentColor">${GEAR}</svg>`);
  gear.title = L.settings;
  speed.appendChild(gear);

  // ---- settings
  const o = G.opts, st = L.set;
  const panel = el('div', 'panel', `<h2>${L.settings}</h2>
    <div class="grp"><label>${st.day}</label><div class="seg" data-k="dayMode">${Object.keys(st.dayOpts).map(k => `<button data-v="${k}">${st.dayOpts[k]}</button>`).join('')}</div></div>
    <div class="grp"><label>${st.sound}</label><div class="line"><input type="checkbox" data-k="sound"><input type="range" min="0" max="100" data-k="volume"></div></div>
    ${['predators', 'nature', 'colonies', 'haze', 'labels'].map(k => `<label class="chk"><input type="checkbox" data-k="${k}"><span>${st[k]}</span></label>`).join('')}`);
  panel.hidden = true;
  gear.onclick = () => { panel.hidden = !panel.hidden; gear.classList.toggle('on', !panel.hidden); };
  const sync = () => {
    panel.querySelectorAll('.seg button').forEach(b => b.classList.toggle('on', b.dataset.v === o.dayMode));
    panel.querySelectorAll('input[type=checkbox]').forEach(i => { i.checked = !!o[i.dataset.k]; });
    panel.querySelector('input[type=range]').value = Math.round(o.volume * 100);
    hint.style.display = o.labels ? '' : 'none';
  };
  panel.addEventListener('click', e => { const b = e.target.closest('.seg button'); if (b) { G.setOpt('dayMode', b.dataset.v); sync(); } });
  panel.addEventListener('input', e => {
    const i = e.target; if (!i.dataset || !i.dataset.k) return;
    G.setOpt(i.dataset.k, i.type === 'checkbox' ? i.checked : i.value / 100);
    sync();
  });

  const toasts = el('div', 'toasts');
  const hint = el('div', 'hint', L.hint);
  root.append(head, cards, bar, speed, panel, toasts, hint);
  const flash = (b) => { b.classList.add('hit'); setTimeout(() => b.classList.remove('hit'), 350); };
  sync();

  U.setTool = (k) => {
    U.tool = k;
    if (k === 'hand') stage.dragMode = 'pan';
    if (k === 'rotate') stage.dragMode = 'orbit';
    for (const n in buttons) buttons[n].classList.toggle('on', n === k);
    ring.visible = false;
  };

  U.toast = (kind, tribe) => {
    let text = L.toast[kind];
    const name = tribe ? L.tribes[tribe.color] : null;
    if (kind === 'era') text = L.toast.era(name, L.eras[tribe.era]);
    if (kind === 'peace') text = L.toast.peace(name);
    if (kind === 'colony') text = L.toast.colony(name);
    const t = el('div', 'toast', text);
    if (tribe) t.style.borderColor = TRIBES[tribe.color].cloth;
    toasts.appendChild(t);
    setTimeout(() => t.classList.add('out'), 3600);
    setTimeout(() => t.remove(), 4300);
  };

  // brush ring that hugs the terrain
  const SEG = 48;
  const ringGeo = new THREE.BufferGeometry();
  ringGeo.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array((SEG + 1) * 3), 3));
  const ring = new THREE.Line(ringGeo, new THREE.LineBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.9, depthTest: false, fog: false }));
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
    G.tribes.summary().forEach((s, i) => {
      const c = cardEls[i];
      c.querySelector('.era').textContent = L.eras[s.era];
      c.querySelector('.pop').textContent = s.pop;
      c.querySelector('.food').textContent = s.food;
      c.querySelector('.wood').textContent = s.wood;
      c.querySelector('.stone').textContent = s.stone;
      c.querySelector('.towns').textContent = s.villages;
    });
    wild.querySelector('.n').textContent = G.animals.all.length + G.animals.crocs.length;
    for (const [s, b] of speedBtns) b.classList.toggle('on', G.paused ? s === 0 : s === G.speed);
    buttons.drought.classList.toggle('on', G.env.drought > 0);
    buttons.war.classList.toggle('on', !!G.tribes.war);
    buttons.storm.classList.toggle('on', G.env.storm > 0);
  };
  U.setTool('hand');
  return U;
}
