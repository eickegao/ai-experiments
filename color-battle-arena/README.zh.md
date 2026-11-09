# Color Battle 四家 AI 对战：四个顶级大模型同场玩实时抢地盘

[English](README.md) · 中文说明

四个大语言模型各自遥控一颗球，在 [PlayDoz](https://playdoz.com) 的 **Color Battle**（60 秒、四人抢地盘）里对战。游戏引擎就是裁判和沙盒：所有动作都走游戏自己的 `command()` 接口，不合法的指令由引擎直接拒绝，世界只通过游戏的定步长模拟推进。模型碰不到状态，只能读一份文字版棋盘、回一条指令。

状态：**框架已就绪，实验尚未跑**（2026-11-09）。结果会补在下面。

## 游戏规则

- 32×32 棋盘，四队从四个象限出发（各 256 格），每队一颗球，速度 22 格/秒。
- 球在自己颜色上畅通无阻；碰到别的颜色就把那格染成自己的颜色并反弹，碰到棋盘边也反弹。
- 60 秒，格子最多的赢。
- 可以让球朝任意点转向（冷却 1 秒）；技能轮每队有三个一级技能：**火焰**（在一点染半径 2 的圆，冷却 12 秒）、**闪电**（从球所在格向四边画十字，冷却 14 秒）、**传送**（球瞬移到任意点，冷却 28 秒）。

## 实验设计

- **选手**：四个模型各占一个象限；另外免费跑一组游戏自带脚本电脑（`cd_ai.lua`）作基准。
- **决策节奏**：每 2 秒游戏时间决策一次（每局 30 次）。模型思考时游戏时间冻结，思考时长只记录、不占比赛时间。每次决策四个模型并行请求。
- **模型看到什么**：32 行字符的棋盘（`.` 中立，`A`–`D` 归属，小写字母是该队的球，`@` 是自己的球）、格子数、自己球的位置和朝向、冷却、上一条指令的裁定。没有历史、没有提示；每次决策都是全新的无状态请求，系统提示词四家完全一样（`arena/prompt.py`）。
- **模型回答什么**：最多两行，`CMD: TURN x y`、`CMD: CAST 槽位 [x y]` 或 `CMD: WAIT`。被引擎拒绝的（冷却中、出界、被冻结）直接忽略，下一回合告诉它；回复里没有合法指令行就什么都不做。
- **两轮**：第一轮只能转向；第二轮带上面三个技能，四队完全相同。每轮四局、固定种子，第 g 局把第 k 个模型放到第 (k + g) mod 4 个象限，保证每个模型每个角落都开一次；同一次决策里指令的执行顺序也轮换。
- **推理强度**：四家都开到各自的"high"（Anthropic `effort`、OpenAI `reasoning.effort`、Gemini `thinking_level`、DeepSeek 开启 thinking 并设 `reasoning_effort`）。
- **每次调用记录**：发出去的原文、收回的原文、耗时秒数、token 数、美元成本（DeepSeek 按高峰/空闲时段的人民币价换算）、每条指令是否被接受。
- **可复现回放**：模拟在种子、技能配置、指令日志给定后是确定性的，`replay.py` 只凭 JSON 就能重建每局每一帧，并校验最终格子数与记录一致。

## 模型

| 选手 | 模型 ID | 厂商 | 价格（美元 / 百万 token，输入 / 输出） | 说明 |
|---|---|---|---|---|
| Claude | `claude-fable-5-1` | Anthropic | 10 / 50 | Anthropic 最高一档 |
| GPT | `gpt-6-astra` | OpenAI | 10 / 50 | OpenAI 旗舰 |
| Gemini | `gemini-4-argon` | Google | 2 / 10（2026-12-01 起翻倍） | Google **公开 API 里能调用的**旗舰。Gemini 4 Carbon 榜单第一，但 2026-11-09 还没有公开 API 模型 ID（只给预发布测试者）。 |
| DeepSeek | `deepseek-v4-pro` | DeepSeek | 高峰约 1.27 / 3.80，空闲减半（人民币 9 / 27 与 4.5 / 13.5，按 7.1 换算） | 实际服务 DeepSeek-V4-Pro-0813，开启 thinking |

价格 2026-11-09 读自各家定价页，见 `arena/prices.py`。

## 怎么跑

```sh
pip install -r requirements.txt            # lupa（Python 里跑 Lua）、四家 SDK、pillow、matplotlib
cp ../.env.example ../.env                 # ANTHROPIC_API_KEY、OPENAI_API_KEY、GEMINI_API_KEY、DEEPSEEK_API_KEY
export PLAYDOZ_DIR=~/Projects/PlayDoz/PlayDozDefold   # games/clashdoz/cd_sim.lua 所在目录（默认值如上）

python3 run_match.py --players random,random,bot,bot --games 1 --skills on --out results/dry   # 免费试跑
./run_experiment.sh                        # 第一轮（只转向）、第二轮（带技能）、电脑基准、回放校验
python3 replay.py results/<目录>           # 出视频用的帧 + 格子数随时间曲线
```

模拟源码（`cd_sim.lua`、`cd_ai.lua`、`cd_config.lua`、`cd_rng.lua`）就是 PlayDoz 正式上线的游戏代码，从 `PLAYDOZ_DIR` 读取；框架只加了两行 Defold 的 `vmath` 桩。

## 输出文件

在 `results/<时间戳>_<轮次>/` 下：

- `game_N.json`：每次决策（棋盘快照、每个模型的提示词原文、回复原文、解析出的指令和裁定、秒数、token、成本）、带 tick 序号的完整指令日志、10 Hz 的格子数时间线、技能事件、最终排名。
- `game_N.md`：每次交流的可读记录。
- `summary.json` / `summary.md`：各模型跨局汇总（胜场、平均名次、格子数、每次决策秒数、被拒 / 缺失指令数、token、成本）。
- `timeline.png`：每局格子数随时间曲线；`frames/game_N/`（不入库，用 `replay.py` 重新生成）：1920×1080、30 fps 的帧。

## 结果

尚未运行。

## 致谢

游戏：[PlayDoz](https://playdoz.com) 的 Color Battle，模拟代码同一作者。视频：[**独立营业中**](https://www.youtube.com/@独立营业中) · [**Build with AI**](https://www.youtube.com/@buildwithai2027)。许可证：MIT（见仓库根目录）。
