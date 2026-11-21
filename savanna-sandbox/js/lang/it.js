// Interface text: Italian.
export default {
  title: 'Savana in miniatura', sub: 'Sei il dio di questa savana', day: n => `Giorno ${n}`,
  tribes: ['Roccarossa', 'Fiumeblu'], eras: ['', 'Accampamento', 'Villaggio', 'Borgo', 'Regno', 'Città industriale', 'Metropoli'], trees: 'Alberi', pop: 'Persone', food: 'Cibo', wood: 'Legno', stone: 'Pietra', towns: 'Insediamenti',
  tools: { hand: 'Sposta', rotate: 'Ruota', rain: 'Pioggia', lightning: 'Fulmine', meteor: 'Meteora', tornado: 'Tornado', plague: 'Peste', bless: 'Benedici', raise: 'Alza', lower: 'Abbassa', herd: 'Branco', drought: 'Siccità', storm: 'Tempesta', war: 'Guerra' },
  toast: {
    era: (t, e) => `${t} entra in una nuova era: ${e}`, war: 'Rullano i tamburi di guerra: i due popoli si mettono in marcia', peace: t => (t ? `${t} vince la guerra` : 'La guerra finisce in parità'),
    drought: 'Siccità. Il fiume comincia a calare', storm: 'Arriva una tempesta', plague: 'Una peste si sta diffondendo', colony: t => `${t} manda dei coloni a fondare un nuovo insediamento`,
  },
  hint: 'Trascina per spostare la mappa · Rotella per lo zoom · Trascina con il tasto destro per ruotare · Anche WASD sposta',
  animals: 'Animali', settings: 'Impostazioni',
  set: {
    lang: 'Lingua', day: 'Giorno e notte', dayOpts: { cycle: 'Giorno e notte', day: 'Sempre giorno', night: 'Sempre notte' }, sound: 'Suono', volume: 'Volume',
    predators: 'I predatori mangiano le persone', nature: 'La natura colpisce da sola (tempeste, siccità)', colonies: 'I grandi insediamenti ne fondano di nuovi', haze: 'Foschia in lontananza', labels: 'Mostra la riga di aiuto',
  },
};
