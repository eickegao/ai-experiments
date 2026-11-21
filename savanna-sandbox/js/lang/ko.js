// Interface text: Korean.
export default {
  title: '사바나 모래상자', sub: '당신은 이 초원의 신입니다', day: n => `${n}일째`,
  tribes: ['붉은바위족', '푸른강족'], eras: ['', '야영지', '마을', '읍', '왕국', '공업 도시', '현대 도시'], trees: '나무', pop: '인구', food: '식량', wood: '목재', stone: '돌', towns: '정착지',
  tools: { hand: '이동', rotate: '회전', rain: '비', lightning: '번개', meteor: '운석', tornado: '토네이도', plague: '역병', bless: '축복', raise: '융기', lower: '침하', herd: '짐승 떼', drought: '가뭄', storm: '폭풍우', war: '전쟁 북' },
  toast: {
    era: (t, e) => `${t}, 새 시대에 들어섰습니다: ${e}`, war: '전쟁 북이 울리고 두 부족이 싸움을 시작합니다', peace: t => (t ? `${t}, 전쟁에서 승리했습니다` : '전쟁이 무승부로 끝났습니다'),
    drought: '가뭄이 들었습니다. 강물이 줄어들기 시작합니다', storm: '폭풍우가 몰려옵니다', plague: '역병이 퍼지기 시작합니다', colony: t => `${t}, 사람들을 보내 새 정착지를 세웠습니다`,
  },
  hint: '드래그로 지도 이동 · 휠로 확대/축소 · 오른쪽 버튼 드래그로 회전 · WASD로도 이동',
  animals: '동물', settings: '설정',
  set: {
    lang: '언어', day: '낮과 밤', dayOpts: { cycle: '낮과 밤', day: '항상 낮', night: '항상 밤' }, sound: '소리', volume: '음량',
    predators: '맹수가 사람을 잡아먹음', nature: '자연이 스스로 재해를 일으킴 (뇌우, 가뭄)', colonies: '사람이 많아지면 새 정착지를 세움', haze: '먼 곳의 안개', labels: '조작 안내 표시',
  },
};
