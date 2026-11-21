// Interface text: French.
export default {
  title: 'Savane miniature', sub: 'Vous êtes le dieu de cette savane', day: n => `Jour ${n}`,
  tribes: ['Rocherouge', 'Rivebleue'], eras: ['', 'Campement', 'Village', 'Bourg', 'Royaume', 'Ville industrielle', 'Métropole'], trees: 'Arbres', pop: 'Habitants', food: 'Vivres', wood: 'Bois', stone: 'Pierre', towns: 'Villages',
  tools: { hand: 'Déplacer', rotate: 'Pivoter', rain: 'Pluie', lightning: 'Foudre', meteor: 'Météore', tornado: 'Tornade', plague: 'Peste', bless: 'Bénir', raise: 'Élever', lower: 'Creuser', herd: 'Troupeau', drought: 'Sécheresse', storm: 'Orage', war: 'Guerre' },
  toast: {
    era: (t, e) => `${t} entre dans une nouvelle ère : ${e}`, war: 'Les tambours de guerre résonnent : les deux peuples se mettent en marche', peace: t => (t ? `${t} remporte la guerre` : 'La guerre s’achève sans vainqueur'),
    drought: 'Sécheresse. La rivière commence à baisser', storm: 'Un orage approche', plague: 'Une peste se répand', colony: t => `${t} envoie des colons fonder un nouveau village`,
  },
  hint: 'Glisser pour déplacer la carte · Molette pour zoomer · Glisser avec le bouton droit pour pivoter · WASD ou les flèches déplacent aussi',
  animals: 'Animaux', settings: 'Réglages',
  set: {
    lang: 'Langue', day: 'Jour et nuit', dayOpts: { cycle: 'Jour et nuit', day: 'Toujours le jour', night: 'Toujours la nuit' }, sound: 'Son', volume: 'Volume',
    predators: 'Les fauves mangent les gens', nature: 'La nature frappe d’elle-même (orages, sécheresse)', colonies: 'Les grands villages en fondent de nouveaux', haze: 'Brume au loin', labels: 'Afficher la ligne d’aide',
  },
};
