# Color Battle 四家 AI 对战：四个顶级大模型在真实游戏里同场抢地盘

[English](README.md) · 中文说明

四个大语言模型各自遥控一颗球，在 [PlayDoz](https://playdoz.com) 的 **Color Battle**（60 秒、四人抢地盘）里对战。比赛**就在正式游戏里跑**
（Defold 工程精简后编成网页版）：所有动作都走游戏自己的 `command()` 接口，不合法的指令由引擎直接拒绝，世界只通过游戏的定步长模拟推进。
开局前每个模型从游戏的技能表里**自己选技能**。模型碰不到状态，只能读一份文字版棋盘、回一条指令。

状态：**框架已就绪，实验尚未跑**（2026-11-09）。结果会补在下面。

## 游戏规则

- 32×32 棋盘，四队从四个象限出发（各 256 格），每队一颗球，速度 22 格/秒。
- 球在自己颜色上畅通无阻；碰到别的颜色就把那格染成自己的颜色并反弹，碰到棋盘边也反弹。60 秒，格子最多的赢。
- 可以让球朝任意点转向（冷却 1 秒）；技能用自己选的那三个，各有冷却。
- 可选的技能 12 种（都是 1 级）：冰冻、分裂、加速、炸弹、巨球、火焰、闪电、传送、碎裂、冲击波、链式闪电、等离子。每队选 3 个。
  具体数值（半径、时长、冷却）在 `game/games/clashdoz/cd_config.lua`，选技能的提示词里原样告诉模型。

## 实验设计

- **选手**：四个模型各占一个象限；另外免费跑一组游戏自带脚本电脑（`cd_ai.lua`）作基准。
- **选技能**：开局前每个模型看同一份技能表（同样的一句话说明），选三个（`PICK: a, b, c`）。电脑和随机玩家随机抽三个。
- **决策节奏**：每 2 秒游戏时间决策一次（每局 30 次）。模型思考时游戏时间冻结，思考时长只记录、不占比赛时间。每次决策四个模型并行请求。
- **模型看到什么**：32 行字符的棋盘（`.` 中立，`A`–`D` 归属，小写字母是该队的球，`@` 是自己的球）、格子数、自己球的位置和朝向、
  冷却、上一条指令的裁定。没有历史、没有提示；每次决策都是全新的无状态请求，系统提示词四家完全一样，只有"你选的技能"一段不同（`arena/prompt.py`）。
- **模型回答什么**：最多两行，`CMD: TURN x y`、`CMD: CAST 槽位 [x y]` 或 `CMD: WAIT`。被引擎拒绝的（冷却中、出界、被冻结）直接忽略，
  下一回合告诉它；回复里没有合法指令行就什么都不做。
- **四局**、固定种子（1001…1004）；第 g 局把第 k 个模型放到第 (k + g − 1) mod 4 个象限，保证每个模型每个角落都开一次；同一次决策里指令的执行顺序也轮换。
- **推理强度**：四家都开到各自的"high"（Anthropic `effort`、OpenAI `reasoning.effort`、Gemini `thinking_level`、DeepSeek 开启 thinking 并设 `reasoning_effort`）。
- **每次调用记录**：发出去的原文、收回的原文、耗时秒数、token 数、美元成本（DeepSeek 按高峰/空闲时段的人民币价换算）、每条指令是否被接受。
- **可复现回放**：游戏把每条被接受 / 被拒绝的指令连同 tick 记下来；同一个网页包按日志重放（`?arena=replay`），并核对终局格子数
  （控制台打印 `ARENA_REPLAY_OK`）。视频里的画面就是正式游戏逐帧重跑这一局。

## 模型

| 选手 | 模型 ID | 厂商 | 价格（美元 / 百万 token，输入 / 输出） | 说明 |
|---|---|---|---|---|
| Claude | `claude-fable-5-1` | Anthropic | 10 / 50 | Anthropic 最高一档 |
| GPT | `gpt-6-astra` | OpenAI | 10 / 50 | OpenAI 旗舰 |
| Gemini | `gemini-4-argon` | Google | 2 / 10（2026-12-01 起翻倍） | Google **公开 API 里能调用的**旗舰。Gemini 4 Carbon 榜单第一，但 2026-11-09 还没有公开 API 模型 ID（只给预发布测试者）。 |
| DeepSeek | `deepseek-v4-pro` | DeepSeek | 高峰约 1.27 / 3.80，空闲减半（人民币 9 / 27 与 4.5 / 13.5，按 7.1 换算） | 实际服务 DeepSeek-V4-Pro-0813，开启 thinking |

价格 2026-11-09 读自各家定价页，见 `arena/prices.py`。

## 怎么搭的

```
game/                 独立 Defold 工程 = Color Battle 的对局画面（tools/import_game.py 从 PlayDoz 仓库复制；去掉封面、技能商店、
                      关卡、金币、结算页和 12 种语言；只留一首背景乐）
game/games/clashdoz/arena.lua   对战模式（源文件 arena_game/arena.lua）：读 URL 参数、选技能、决策暂停、指令日志、回放
arena_server.py       本机服务：托管网页包，回答 /draft、/decide、/finish；所有模型调用和记录都在这里
arena/                选手（每家一个类）、提示词与解析、价格
record_match.py       Playwright：无头跑一局，再把回放录成 1080×1920 mp4
tools/                import_game.py（从 PlayDoz 重建 game/）、web_smoke.py（无头截图）
docs/                 设计说明
```

## 怎么跑

```sh
pip install -r requirements.txt            # 四家 SDK、playwright（用系统里的 Chrome）、pillow、matplotlib
cp ../.env.example ../.env                 # ANTHROPIC_API_KEY、OPENAI_API_KEY、GEMINI_API_KEY、DEEPSEEK_API_KEY

# 编网页包（Defold 的 bob.jar + Defold 编辑器自带的 JDK；任何 JDK 21+ 都行）
JAVA=$(ls -d /Applications/Defold.app/Contents/Resources/packages/jdk-*/bin/java | tail -1)
(cd game && $JAVA -jar /path/to/bob.jar --platform wasm-web --architectures wasm-web --variant release --archive --bundle-output build_web resolve build bundle)

python3 arena_server.py --players random,random,bot,bot --out results/dry &      # 免费试跑
python3 record_match.py --game 1 --out results/dry                               # 跑一局 + 录回放

./run_experiment.sh                        # 正式：Claude / GPT / Gemini / DeepSeek 四局 + 电脑基准
```

`game/` 是游戏正式代码和美术的副本，放进来是为了可复现；模拟代码（`cd_sim.lua`）和商店版一字不差。

## 输出文件

在 `results/<目录>/` 下：

- `game_N.json`：选技能（提示词、回复、选择）、每次决策（棋盘快照、每个模型的提示词原文、回复原文、解析出的指令和引擎裁定、秒数、token、成本）、
  带 tick 的完整指令日志、10 Hz 的格子数时间线、终局排名、各选手汇总。
- `game_N.md`：每次交流的可读记录。`game_N.mp4`：正式游戏录下的回放（1080×1920）。
- `summary.json` / `summary.md`：各选手跨局汇总（胜场、平均名次、格子数、每次决策秒数、被拒 / 沉默次数、放招数、token、成本、所选技能）。

## 结果

尚未运行。

## 致谢

游戏：[PlayDoz](https://playdoz.com) 的 Color Battle，模拟代码同一作者。视频：[**独立营业中**](https://www.youtube.com/@独立营业中) · [**Build with AI**](https://www.youtube.com/@buildwithai2027)。许可证：MIT（见仓库根目录）。
