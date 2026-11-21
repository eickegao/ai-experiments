// Interface text: English.
export default {
  title: 'Savanna Sandbox', sub: 'You are the god of this grassland', day: n => `Day ${n}`,
  tribes: ['Redrock', 'Blueriver'], eras: ['', 'Camp', 'Village', 'Town', 'Kingdom', 'Industrial city', 'Metropolis'], trees: 'Trees', pop: 'People', food: 'Food', wood: 'Wood', stone: 'Stone', towns: 'Towns',
  tools: { hand: 'Move', rotate: 'Rotate', rain: 'Rain', lightning: 'Lightning', meteor: 'Meteor', tornado: 'Tornado', plague: 'Plague', bless: 'Bless', raise: 'Raise', lower: 'Lower', herd: 'Herd', drought: 'Drought', storm: 'Storm', war: 'War drum' },
  toast: {
    era: (t, e) => `${t} enters the ${e} age`, war: 'War drums: the two peoples march', peace: t => (t ? `${t} wins the war` : 'The war ends in a draw'),
    drought: 'Drought. The river is falling', storm: 'A storm rolls in', plague: 'A plague is spreading', colony: t => `${t} sends settlers out to found a new town`,
  },
  hint: 'Drag to move the map · Scroll to zoom · Right-drag to rotate · WASD also moves',
  animals: 'Animals', settings: 'Settings',
  set: {
    lang: 'Language / 语言', day: 'Day and night', dayOpts: { cycle: 'Day and night', day: 'Always day', night: 'Always night' }, sound: 'Sound', volume: 'Volume',
    predators: 'Predators eat people', nature: 'Nature strikes on its own (storms, drought)', colonies: 'Big towns found new ones', haze: 'Distance haze', labels: 'Show the hint line',
  },
};
