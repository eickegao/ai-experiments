// Interface text: Chinese.
export default {
  title: '草原沙盘', sub: '你是这片草原的神', day: n => `第 ${n} 天`,
  tribes: ['赤岩人', '蓝河人'], eras: ['', '营地', '村落', '城寨', '王城', '工业城', '现代都市'], trees: '树木', pop: '人口', food: '粮食', wood: '木头', stone: '石头', towns: '聚落',
  tools: { hand: '移动', rotate: '旋转', rain: '降雨', lightning: '闪电', meteor: '陨石', tornado: '龙卷风', plague: '瘟疫', bless: '祝福', raise: '隆起', lower: '下陷', herd: '兽群', drought: '干旱', storm: '暴雨', war: '战鼓' },
  toast: {
    era: (t, e) => `${t}进入「${e}」时代`, war: '战鼓响起，两族开战', peace: t => (t ? `${t}赢得了这场战争` : '战争结束，双方退兵'),
    drought: '大旱降临，河水开始退去', storm: '暴雨来了', plague: '瘟疫开始蔓延', colony: t => `${t}派人外出，建立了新的聚落`,
  },
  hint: '拖动移动地图 · 滚轮缩放 · 右键拖动旋转 · WASD 也能移动',
  animals: '动物', settings: '设置',
  set: {
    lang: '语言 / Language', day: '昼夜', dayOpts: { cycle: '昼夜交替', day: '永远白天', night: '永远黑夜' }, sound: '声音', volume: '音量',
    predators: '猛兽会吃人', nature: '大自然自己降灾（雷雨、干旱）', colonies: '人多了外出建新聚落', haze: '远处起雾', labels: '显示界面文字提示',
  },
};
