# 雾里倒水

[English](README.md) · 中文说明

四个大模型各自打 PlayDoz 倒水的同一个雾关（第 286 关），全程一个对话，允许撤销和重来。给 [**Build with AI**](https://www.youtube.com/@buildwithai2027) 和 [**独立营业中**](https://www.youtube.com/@独立营业中) 做的实验，更多内容见 [videodoz.com](https://videodoz.com)。

状态：程序已就绪，付费对局还没开跑（2026-11-17）。

## 做什么，为什么

雾关里每根管只露最上面的颜色，下面全是问号。开局没法把整关算出来，只能倒一步看一步，走进死路要退回来，还得记住之前揭开过什么。所以它考的是信息不全时怎么试探、会不会用记忆，而不是跑搜索算法。

我们只列数据，不给模型排名。

## 关卡

第 286 关：14 根管，每管 5 层，12 种颜色各 5 层，12 管满、2 管空。盘面全部可见时最短解是 **50 步**（`solve.py`，A* 加不高估的启发函数，50 步是证明过的最优）。

## 给模型的规则

- `MOVE a b`：把 a 管顶上连续同色的一段倒进 b 管（b 是空管或顶色相同；装不下就倒一部分）。
- 雾：每管只露顶上那一段，其余显示 `?`，倒走后揭开下面的。
- `UNDO` 撤销上一步（雾也盖回去，和游戏一致）。`RESTART` 回到开局、雾重新盖上。每一局的关卡完全相同。
- 整场是一个对话，之前看到的、试过的都留在模型的上下文里。
- 上限：总共 500 步。不合法或读不懂的指令不改变盘面，记一次犯规。

完整的系统提示词在 `arena/prompt.py`，四家一字不差：只讲规则和我们记录什么，不教策略。

## 记录什么

| 数字 | 含义 |
|---|---|
| 总步数 | 整场倒水的次数，含后来撤销的和放弃的那几局 |
| 撤销、重来、局数 | 来回折腾了多少 |
| 通关步数 | 通关那一局的步数，撤销掉的不算 |
| 比最优多几步 | 通关步数减 50 |
| 犯规 | 不合法或读不懂的指令 |
| 耗时、token、美元 | 每次调用和合计 |

## 怎么验证

规则是照游戏自己的逻辑用 Python 重写的（倒水看 `nutssort_logic.lua`，雾看 `watersort_game.gui_script`），`tests/` 里有单元测试。通关的对局会在一块新盘面上把解法重放一遍核对。模型的每句回复原样保存。

## 模型

| 厂商 | 模型 ID |
|---|---|
| Anthropic | `claude-fable-5-2` |
| OpenAI | `gpt-6.2-astra` |
| Google | `gemini-4-carbon` |
| DeepSeek | `deepseek-v4-pro` |

四家用同一个思考档位，正式用哪一档等一次短的计时试跑后再定。价格表在 `arena/prices.py`。

## 怎么跑

```bash
pip install -r requirements.txt
python3 -m pytest -q tests                      # 规则、解析、对局、续跑
python3 solve.py 286 --out results/solver_286.json
python3 run_game.py --player random:1           # 免费试跑，不需要密钥
python3 run_game.py --player claude --effort medium --budget-usd 30
```

密钥放仓库根目录的 `.env`。关卡数据从本地的游戏工程读（`arena/game.py` 的 `LEVELS_LUA`），关卡本身也存在 `results/solver_286.json` 里。用同一个 `--out` 再跑会从日志续上，已经付过钱的回合不会重跑。

## 输出文件

- `results/<玩家>-<档位>/turns.jsonl`：文件头（关卡、模型、系统提示词），之后每回合一行：发给模型的内容、原始回复、解析出的指令、是否接受、盘面、各项计数、耗时、token、费用。
- `results/<玩家>-<档位>/summary.json`：上表的各项数字和解法。
- `results/solver_286.json`：盘面全可见时的参考解。

## 结果

还没跑。
