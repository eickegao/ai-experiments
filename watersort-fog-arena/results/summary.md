# Results: level 286, fogged

Reference: with the whole board visible the shortest solution is **50 pours** (proven optimal).

| Model | Thinking setting sent | Solved | Solution pours | Over optimal | Total pours | Undos | Restarts | Attempts | Fouls | Turns | Minutes | USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gpt-6.2-astra | reasoning.effort=low | yes | 52 | +2 | 348 | 44 | 16 | 17 | 0 | 408 | 40.7 | 11.57 |
| claude-fable-5-2 | output_config.effort=low | no (stopped_by_operator) | - | - | 127 | 11 | 6 | 7 | 17 | 161 | 96.4 | 23.45 |
| gemini-4-carbon | thinking_level=low (Vertex AI) | no (stopped_by_operator) | - | - | 60 | 9 | 2 | 3 | 14 | 85 | 47.1 | 1.59 |
| deepseek-v4-pro | thinking enabled, reasoning_effort=low | no (stopped_by_operator) | - | - | 71 | 22 | 5 | 6 | 9 | 107 | 93.4 | 1.41 |
| deepseek-v4-pro | thinking disabled | no (pour_limit) | - | - | 500 | 166 | 166 | 167 | 6 | 838 | 26.9 | 1.97 |

Total pours counts every pour of the session, including undone ones and abandoned attempts. Solution pours is the length of the attempt that solved the level, undone pours left out. Minutes is model response time only.
