// Interface text: Japanese.
export default {
  title: 'サバンナの箱庭', sub: 'あなたはこの草原の神', day: n => `${n}日目`,
  tribes: ['赤岩の民', '青河の民'], eras: ['', '野営地', '村', '町', '王国', '工業都市', '現代都市'], trees: '木', pop: '人口', food: '食料', wood: '木材', stone: '石', towns: '集落',
  tools: { hand: '移動', rotate: '回転', rain: '雨', lightning: '雷', meteor: '隕石', tornado: '竜巻', plague: '疫病', bless: '祝福', raise: '隆起', lower: '沈降', herd: '群れ', drought: '干ばつ', storm: '嵐', war: '戦太鼓' },
  toast: {
    era: (t, e) => `${t}が「${e}」の時代に入った`, war: '戦太鼓が鳴り、二つの民が戦を始めた', peace: t => (t ? `${t}が戦に勝った` : '戦は引き分けに終わった'),
    drought: '干ばつが来た。川の水が引きはじめる', storm: '嵐がやって来た', plague: '疫病が広がりはじめた', colony: t => `${t}が人を送り、新しい集落を築いた`,
  },
  hint: 'ドラッグで地図を移動 · ホイールで拡大縮小 · 右ドラッグで回転 · WASDでも移動',
  animals: '動物', settings: '設定',
  set: {
    lang: '言語', day: '昼と夜', dayOpts: { cycle: '昼夜あり', day: 'ずっと昼', night: 'ずっと夜' }, sound: '音', volume: '音量',
    predators: '猛獣が人を襲う', nature: '自然がひとりでに災いを起こす（雷雨・干ばつ）', colonies: '人が増えると新しい集落を築く', haze: '遠くに霞', labels: '操作ヒントを表示',
  },
};
