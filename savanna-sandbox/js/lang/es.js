// Interface text: Spanish.
export default {
  title: 'Sabana en miniatura', sub: 'Eres el dios de esta pradera', day: n => `Día ${n}`,
  tribes: ['Rocarroja', 'Ríoazul'], eras: ['', 'Campamento', 'Aldea', 'Villa', 'Reino', 'Ciudad industrial', 'Metrópolis'], trees: 'Árboles', pop: 'Gente', food: 'Comida', wood: 'Madera', stone: 'Piedra', towns: 'Poblados',
  tools: { hand: 'Mover', rotate: 'Girar', rain: 'Lluvia', lightning: 'Rayo', meteor: 'Meteoro', tornado: 'Tornado', plague: 'Peste', bless: 'Bendecir', raise: 'Elevar', lower: 'Hundir', herd: 'Manada', drought: 'Sequía', storm: 'Tormenta', war: 'Guerra' },
  toast: {
    era: (t, e) => `${t} entra en una nueva era: ${e}`, war: 'Suenan los tambores de guerra: los dos pueblos marchan', peace: t => (t ? `${t} gana la guerra` : 'La guerra termina en tablas'),
    drought: 'Sequía. El río empieza a bajar', storm: 'Se acerca una tormenta', plague: 'Una peste se extiende', colony: t => `${t} envía colonos a fundar un nuevo poblado`,
  },
  hint: 'Arrastra para mover el mapa · Rueda para acercar · Arrastra con el botón derecho para girar · WASD también mueve',
  animals: 'Animales', settings: 'Ajustes',
  set: {
    lang: 'Idioma', day: 'Día y noche', dayOpts: { cycle: 'Día y noche', day: 'Siempre de día', night: 'Siempre de noche' }, sound: 'Sonido', volume: 'Volumen',
    predators: 'Las fieras se comen a la gente', nature: 'La naturaleza castiga por su cuenta (tormentas, sequía)', colonies: 'Los poblados grandes fundan otros', haze: 'Bruma a lo lejos', labels: 'Mostrar la línea de ayuda',
  },
};
