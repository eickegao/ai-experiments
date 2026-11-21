// Interface text: Portuguese.
export default {
  title: 'Savana em miniatura', sub: 'Você é o deus desta savana', day: n => `Dia ${n}`,
  tribes: ['Pedra-Rubra', 'Rio-Azul'], eras: ['', 'Acampamento', 'Aldeia', 'Vila', 'Reino', 'Cidade industrial', 'Metrópole'], trees: 'Árvores', pop: 'Pessoas', food: 'Comida', wood: 'Madeira', stone: 'Pedra', towns: 'Povoados',
  tools: { hand: 'Mover', rotate: 'Girar', rain: 'Chuva', lightning: 'Raio', meteor: 'Meteoro', tornado: 'Tornado', plague: 'Peste', bless: 'Abençoar', raise: 'Elevar', lower: 'Rebaixar', herd: 'Manada', drought: 'Seca', storm: 'Temporal', war: 'Guerra' },
  toast: {
    era: (t, e) => `${t} entra em uma nova era: ${e}`, war: 'Soam os tambores de guerra: os dois povos marcham', peace: t => (t ? `${t} vence a guerra` : 'A guerra termina empatada'),
    drought: 'Seca. O rio começa a baixar', storm: 'Um temporal se aproxima', plague: 'Uma peste está se espalhando', colony: t => `${t} envia colonos para fundar um novo povoado`,
  },
  hint: 'Arraste para mover o mapa · Role para aproximar · Arraste com o botão direito para girar · WASD também move',
  animals: 'Animais', settings: 'Ajustes',
  set: {
    lang: 'Idioma', day: 'Dia e noite', dayOpts: { cycle: 'Dia e noite', day: 'Sempre dia', night: 'Sempre noite' }, sound: 'Som', volume: 'Volume',
    predators: 'As feras comem pessoas', nature: 'A natureza ataca por conta própria (temporais, seca)', colonies: 'Povoados grandes fundam novos', haze: 'Névoa ao longe', labels: 'Mostrar a linha de ajuda',
  },
};
