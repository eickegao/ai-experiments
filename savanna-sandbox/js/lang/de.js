// Interface text: German.
export default {
  title: 'Savannen-Sandkasten', sub: 'Du bist der Gott dieser Savanne', day: n => `Tag ${n}`,
  tribes: ['Rotfels', 'Blaufluss'], eras: ['', 'Lager', 'Dorf', 'Stadt', 'Königreich', 'Industriestadt', 'Metropole'], trees: 'Bäume', pop: 'Menschen', food: 'Nahrung', wood: 'Holz', stone: 'Stein', towns: 'Siedlungen',
  tools: { hand: 'Bewegen', rotate: 'Drehen', rain: 'Regen', lightning: 'Blitz', meteor: 'Meteor', tornado: 'Tornado', plague: 'Seuche', bless: 'Segnen', raise: 'Heben', lower: 'Senken', herd: 'Herde', drought: 'Dürre', storm: 'Unwetter', war: 'Krieg' },
  toast: {
    era: (t, e) => `${t} erreicht ein neues Zeitalter: ${e}`, war: 'Die Kriegstrommeln schlagen: Beide Völker ziehen in den Kampf', peace: t => (t ? `${t} gewinnt den Krieg` : 'Der Krieg endet unentschieden'),
    drought: 'Dürre. Der Fluss beginnt zu sinken', storm: 'Ein Unwetter zieht auf', plague: 'Eine Seuche breitet sich aus', colony: t => `${t} schickt Siedler aus, um eine neue Siedlung zu gründen`,
  },
  hint: 'Ziehen bewegt die Karte · Mausrad zoomt · Rechts ziehen dreht · WASD bewegt ebenfalls',
  animals: 'Tiere', settings: 'Einstellungen',
  set: {
    lang: 'Sprache', day: 'Tag und Nacht', dayOpts: { cycle: 'Tag und Nacht', day: 'Immer Tag', night: 'Immer Nacht' }, sound: 'Ton', volume: 'Lautstärke',
    predators: 'Raubtiere fressen Menschen', nature: 'Die Natur schlägt von selbst zu (Unwetter, Dürre)', colonies: 'Große Siedlungen gründen neue', haze: 'Dunst in der Ferne', labels: 'Hinweiszeile anzeigen',
  },
};
