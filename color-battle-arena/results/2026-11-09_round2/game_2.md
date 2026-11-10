# Game 2 (seed 1002)

Seats: **B** Claude (claude-fable-5-1) [teleport, shatter, giant], **C** GPT (gpt-6-astra) [teleport, shatter, accel], **D** Gemini (gemini-4-argon) [teleport, shatter, accel], **A** DeepSeek (deepseek-v4-pro) [shatter, teleport, fire]

Result: A > D > C > B  (cells A 314, B 134, C 277, D 299)

## Draft
**A** picked shatter, teleport, fire (fixed loadout (per seat))

**B** picked teleport, shatter, giant (fixed loadout (per seat))

**C** picked teleport, shatter, accel (fixed loadout (per seat))

**D** picked teleport, shatter, accel (fixed loadout (per seat))

## Decision 1 — t = 0 s — cells A 256 B 256 C 256 D 256
**B** (2.7 s): `CAST 1 30.5 1.5` ✓; `CAST 2` ✓

> Start: teleport into enemy territory isn't a pocket yet, but a teleport deep into D's block near a corner (e.g., top-right corner) gives bounces between wall and D cells, plus Shatter to snowball. Aim ball toward D block and cast both.
> 
> CMD: TELEPORT 30.5 1.5
> CMD: CAST 2

**C** (3.6 s): `CAST 1 24.5 24.5` ✓; `CAST 2` ✓

> Teleport into B’s center to create an enclosed foothold, then use Shatter to rapidly spread through foreign cells.
> CMD: CAST 1 24.5 24.5
> CMD: CAST 2

**D** (13.7 s): `CAST 1 8 8` ✓; `CAST 2` ✓

> I will use the Teleport + Shatter combo immediately into the middle of C's territory (x=8, y=8). Surrounded by enemy cells, the ball will bounce rapidly and spawn extra balls on every bounce, quickly collapsing C's block.
> 
> CMD: CAST 1 8 8
> CMD: CAST 2

**A** (2.1 s): `CAST 3 24 8` ✓

> I'll fire into the densest enemy area (C or D) to gain immediate cells. Since all counts are equal, I'll hit the top-right D block.
> 
> CMD: FIRE 24 8

## Decision 2 — t = 3 s — cells A 265 B 190 C 256 D 313
**B** (2.0 s): `TURN 22 14` ✓

> Shatter is active (cast last turn); my ball is in my own territory heading down-right. Better to turn it into D's big block below-left so each flip spawns balls. Aim at D mass around (22, 14).
> 
> CMD: TURN 22 14

**C** (3.9 s): `TURN 22 10` ✓; `CAST 3` ✓

> Accelerate the active Shatter swarm and steer into D’s leading territory to flip their cells and spawn more balls.
> CMD: TURN 22 10
> CMD: CAST 3

**D** (10.8 s): `CAST 3` ✓; `TURN 8 24` ✓

> Shatter is active with 16 balls in the top-left. I will cast ACCEL (slot 3) to double the speed of all my balls while Shatter lasts, and turn my main ball toward the bottom-left to attack A's territory (265 cells, currently second place).
> 
> CMD: CAST 3
> CMD: TURN 8 24

**A** (3.9 s): `CAST 2 26.5 3.5` ✓; `CAST 1` ✓

> Reasoning: You're in third place. TELEPORT is ready and can be combined with SHATTER to collapse a small enemy pocket. The board shows a compact D region around (24,4)-(28,7), but teleporting into a D pocket is risky. Better target is B’s top block around x=25-28, y=2-5, which is dense and enclosed. Teleport to (26.5, 3.5), then SHATTER immediately to maximize flips.
> 
> CMD: TELEPORT 26.5 3.5
> CMD: CAST 1

## Decision 3 — t = 6 s — cells A 263 B 102 C 312 D 347
**B** (2.7 s): `TURN 2 12` ✓; `CAST 3` ✓

> Ball is in my own corner, heading down toward D territory at rows 14-17 (cols 29-32). GIANT pierces for 3s; better aim toward big D block to the left. Turn ball left into D mass and cast Giant to plough a wide trail.
> 
> CMD: TURN 2 12
> CMD: CAST 3

**C** (3.9 s): `TURN 11 14` ✓

> Aim up the contested left boundary to chip away at D’s lead rather than bounce along the bottom.
> CMD: TURN 11 14

**D** (5.8 s): `TURN 16 20` ✓

> All skills are on cooldown. We lead with 347 cells, while C is second with 312. Our ball is at (0.6, 11.8) at the left edge. Let's aim toward the border between A and C around (16, 20) so our ball breaks into C's massive bottom-right territory while cutting through A's border.
> 
> CMD: TURN 16 20

**A** (4.8 s): `CAST 3 26 20` ✗ rejected; `WAIT` ✓

> Reasoning: We need to flip C's and D's territory. Our ball is heading down-left into area with some D/C cells. Teleport is ready and can put us into a pocket—ideally small pocket of C's territory to shatter. But we have no ready Shatter (cooldown 12s). Instead, consider Teleport to center of D/C border region with dense enemy cells, then wait for Shatter. Fire is also ready—use it on a dense enemy block now for immediate gain. Since decision every 3s, use FIRE on C's dense area around (26, 20) immediately. Then Teleport next to enclosed C pocket if possible.
> 
> CMD: CAST 3 26 20
> CMD: WAIT

## Decision 4 — t = 9 s — cells A 322 B 130 C 292 D 280
**B** (3.2 s): `TURN 20 6` ✓

> Ball is at the C/B border heading left into C territory. A is leader but C block is right here and large. Point ball into A's big block upper area? A is at top-middle; from (25.8,21.7) heading toward (20,5) crosses C then A cells, bouncing along borders. Better: aim at A's dense block to chip the leader.
> 
> CMD: TURN 20 6

**C** (2.7 s): `TURN 6 25` ✓

> Aim into A’s lower-left block to cut into the leader while skills recharge.
> CMD: TURN 6 25

**D** (6.2 s): `TURN 20 6` ✓

> All skills are on cooldown. My ball is at (1.3, 5.3) deep in our top-left territory. Leader A has a massive block to the right (x=15..28, y=1..14). I will turn towards (20, 6) to break straight into A's main territory and start chipping away at the leader.
> 
> CMD: TURN 20 6

**A** (2.7 s): `TURN 16 20` ✓

> You're in first place with 322 cells. Your ball is heading down-left through your own territory, not into enemy territory yet. Skills are on cooldown, so this is a positioning turn.
> 
> I'll point the ball toward the large enemy block of C/D to the south to set up future painting.
> 
> CMD: TURN 16 20

## Decision 5 — t = 12 s — cells A 367 B 137 C 252 D 268
**B** (2.9 s): `TURN 18 12` ✓

> Ball is heading up through my own B column; it'll hit A territory near row 14-17 and bounce around the A/B border. Better to aim it into A's big block to the left so it keeps flipping A cells. Shatter ready in 3 s; teleport in 8 s.
> 
> CMD: TURN 18 12

**C** (3.5 s): `TURN 4 23` ✓; `CAST 3` ✓

> Drive diagonally into A’s lower-left block, using acceleration to increase border flips before Shatter becomes ready.
> CMD: TURN 4 23
> CMD: CAST 3

**D** (13.2 s): `TURN 16 7` ✓; `CAST 3` ✓

> Our ball at (9.6, 7.9) is heading left toward the B pocket around rows 11-15, cols 1-8. However, team A is leading with 367 cells directly to our right (cols 15-30, rows 1-14). Let's turn right toward A's border and activate ACCEL to chew into the leader's territory before SHATTER comes off cooldown next turn.
> 
> CMD: TURN 16 7
> CMD: CAST 3

**A** (5.3 s): `CAST 3 15 17` ✗ rejected

> You're in the lead with 367 cells, B is weakest at 137, C and D are close behind you. Your ball is heading down along the right edge of your territory, near B and D territory.
> 
> Best move: Use FIRE on the dense D block on the left side, or on B's territory to cement your lead. FIRE is ready and can paint a radius-3 circle immediately. Target the biggest cluster of enemy cells that you can convert. The D block top-left is large but far from the ball; targeting B's area (rows 14-20, columns 28-32) is smaller but closer and directly contested.
> 
> Given your lead, focus on reducing C or D, not B, who is already weak. C is at 252 and spread widely in the middle-lower right. Fire at (15, 17) area or (10, 17) to hit dense C cells.
> 
> Let's target (15, 17) since it's in the middle of C's cluster, maximizing paint gained.
> 
> CMD: FIRE 15 17

## Decision 6 — t = 15 s — cells A 361 B 144 C 246 D 273
**B** (1.7 s): `TURN 20 8` ✓; `CAST 2` ✓

> Ball at right edge, about to bounce. Turn it into A's big block (leader) heading up-left, and cast Shatter as it enters A territory.
> 
> CMD: TURN 20 8
> CMD: CAST 2

**C** (4.1 s): `TURN 5 28` ✓; `CAST 2` ✓

> Shatter now at the contested edge; angle southwest to spread into A’s territory and cut the leader’s count.
> CMD: TURN 5 28
> CMD: CAST 2

**D** (7.4 s): `TURN 16 12` ✓

> Team A is leading with 361 cells in the top-right and bottom-left. Teleport and Accel are on a 5s cooldown, so I will save Shatter to combo with them next turn. For now, I'll turn the ball toward the enemy border with A and B around (16, 12) to keep flipping cells.
> 
> CMD: TURN 16 12

**A** (3.2 s): `TURN 24 18` ✓

> We're ahead (361 cells) but Shatter is ready in 3s. Our ball is heading up into our own territory, so Shatter now would be wasted. We need to redirect toward enemy cells—C is the biggest threat (246) and has a dense block to our right/below. Teleport is on cooldown, so we should turn our ball toward C's territory now, then cast Shatter when it reaches enemy color.
> 
> CMD: TURN 24 18

## Decision 7 — t = 18 s — cells A 249 B 182 C 337 D 256
**B** (2.3 s): `TURN 20 6` ✓

> Ball is deep in my own colour heading right toward the edge. I should point it into A's block to the upper-left to flip cells while shatter is still active (small balls visible). Teleport nearly ready; next turn I'll use it into C.
> 
> CMD: TURN 20 6

**C** (2.9 s): `TURN 30 17` ✓

> Aim into B’s dense right flank while Shatter is still active, keeping new balls on contested ground.
> CMD: TURN 30 17

**D** (8.6 s): `TURN 14 15` ✓

> C is leading with 337 cells, while Teleport and Accel are on cooldown for 2 more seconds. I will save Shatter to combo with Teleport into C's territory next turn. For now, I'll turn my ball toward the contested border with C and B around (14, 15) so it chips away at enemy cells in the meantime.
> 
> CMD: TURN 14 15

**A** (3.8 s): `TURN 16 12` ✓; `CAST 1` ✓

> We're in 2nd place (249), leader C has 337. My ball is in my own territory heading up-left. Shatter is ready and best used when entering enemy territory. TELEPORT on 5s cooldown, FIRE 2s cooldown.
> 
> The ball is at (22.4,7.2) heading up-left toward the A/C boundary around rows 1-3. It will bounce off the top edge and keep working along the border. Best to TURN the ball toward C's territory to maximize Shatter value, then cast Shatter.
> 
> CMD: TURN 16 12
> CMD: CAST 1

## Decision 8 — t = 21 s — cells A 262 B 201 C 354 D 207
**B** (3.8 s): `CAST 1 20.5 19.5` ✓; `TURN 15 32` ✓

> C leads with 354. Teleport ready; Shatter not for 9s. Teleport into a pocket in C territory? Pockets: B cell at row 20 col 21 ("BCCBB") — small B pocket enclosed by C. Teleport there, ball bounces around inside C flipping cells. Better to save teleport for shatter combo in 9s? Teleport cooldown 20s; using now, it'd be ready at ~19s left, when shatter also ready. Use now and aim down into C.
> 
> CMD: TELEPORT 20.5 19.5
> CMD: TURN 15 32

**C** (4.6 s): `CAST 1 18.5 6.5` ✓; `CAST 3` ✓

> Teleport into A’s dense interior to cut down the closest rival; acceleration will rapidly expand the landing pocket.
> CMD: CAST 1 18.5 6.5
> CMD: CAST 3

**D** (3.9 s): `CAST 1 18.5 26.5` ✓; `CAST 2` ✓

> Team C is leading with 354 cells in the bottom half. I will teleport deep into the middle of C's territory and trigger Shatter immediately so the bounces multiply and carve out a massive chunk of their lead.
> 
> CMD: CAST 1 18.5 26.5
> CMD: CAST 2

**A** (2.7 s): `CAST 3 22 27` ✓

> Reasoning: You lead C by 92 cells (C is leader at 354, you 262). FIRE is ready and can flip ~29 cells in C's dense block. Aim FIRE at a dense C area around rows 25-30, columns 17-27 to maximize gain.  
> 
> CMD: CAST 3 22 27

## Decision 9 — t = 24 s — cells A 309 B 178 C 251 D 286
**B** (2.3 s): `TURN 12 10` ✓

> Ball is in my own corner heading up; it'll bounce off the top edge. Turn it toward A's big block to the left so it flips cells on the way; shatter/giant become ready in 6 s while the ball is in A territory.
> 
> CMD: TURN 12 10

**C** (4.3 s): `TURN 12.5 12.5` ✓

> Aim diagonally across A’s surrounding territory to widen our pocket while acceleration remains active.
> CMD: TURN 12.5 12.5

**D** (4.8 s): `CAST 3` ✓; `TURN 15 10` ✓

> We currently have many extra balls ('d') active from our recent Shatter cast at the bottom, and our main ball '@' is at (14.7, 21.5). Team A is in the lead with 309 cells directly above us. I will cast ACCEL to double the speed of all our balls while Shatter is active, and turn the main ball up into A's large territory.
> 
> CMD: CAST 3
> CMD: TURN 15 10

**A** (4.8 s): `CAST 2 26.5 29.5` ✓

> Looking at the board state: I'm A with 309 cells, leading D (286). D has a large contiguous block in the bottom half. My ball is in A territory near the top, moving up-left. SHATTER is on cooldown for 9s, FIRE on cooldown for 17s, but TELEPORT is ready.
> 
> Best move: Teleport into D's territory to start converting their cells, then next turn SHATTER will be ready to snowball. Looking at D's bottom block, there's a good pocket around row 28-32, columns 24-27 where D cells are clustered tightly. I'll teleport my ball to x=26.5, y=29.5 (center of that D-dense area).
> 
> Reasoning: Teleport gains +18 instant/+32 after 6s when aimed well. I target D (the leader threat behind me), and set up for SHATTER combo when cooldown expires in 9s to maximize painting inside D territory.
> 
> CMD: CAST 2 26.5 29.5

## Decision 10 — t = 27 s — cells A 317 B 119 C 155 D 433
**B** (2.6 s): `TURN 20 20` ✓

> My ball is in my own corner heading to the top edge. D leads massively; their block is south. Turn the ball down-left toward A/D territory so it reaches foreign cells; Shatter/Giant come off cooldown next turn.
> 
> CMD: TURN 20 20

**C** (3.6 s): `TURN 10 13` ✓

> Aim diagonally across the surrounding enemy border to expand the pocket while Shatter and Accel recharge.
> CMD: TURN 10 13

**D** (7.9 s): `TURN 16 10` ✓

> All skills are on cooldown. We lead with 433 cells, while Team A is second with 317. Our main ball at (24.8, 19.7) is heading down into our own territory. Let's redirect it up and left toward Team A's massive territory block in the upper-center to chip away at their lead.
> 
> CMD: TURN 16 10

**A** (3.1 s): `TURN 15 20` ✓

> Our ball is at (26.5, 29.5) heading up-left. We need to target team D (433 cells) since they are the leader. SHATTER has 6 s left on cooldown, TELEPORT and FIRE also on cooldown. Best move is to point the ball toward the dense D territory ahead-left (around x=15, y=20) so it will bounce through their area when skills come off cooldown.
> 
> CMD: TURN 15 20

## Decision 11 — t = 30 s — cells A 282 B 118 C 142 D 482
**B** (2.1 s): `TURN 24 16` ✓; `CAST 2` ✓

> Ball at (26.9,9.9) heading down-right through my own territory toward the D mass below. It will reach D cells around row 14-15 at column ~30. Cast Shatter now so bounces into D territory spawn balls; aim ball at the big D block.
> 
> CMD: TURN 24 16
> CMD: CAST 2

**C** (3.4 s): `CAST 2` ✓; `CAST 3` ✓

> Trigger Shatter and Accel together to rapidly expand from this pocket into surrounding territory while teleport recharges.
> CMD: CAST 2
> CMD: CAST 3

**D** (8.3 s): `TURN 15 10` ✓

> All skills are on cooldown. We lead with 482 cells, while A is second with 282 cells. Our ball is at (11.6, 23.9) heading down-left toward the C/A cluster on the bottom-left. Turning up toward A's huge main block at (15, 10) will let us chip away at the second-place team while waiting for Shatter and Accel to come off cooldown.
> 
> CMD: TURN 15 10

**A** (2.3 s): `TURN 20 18` ✓

> Reasoning:  
> We are behind D by 200 cells; need to hit D’s territory. SHATTER is almost ready but not yet. I’ll aim toward D’s dense area and prepare to use SHATTER next turn.  
> 
> CMD: TURN 20 18

## Decision 12 — t = 33 s — cells A 154 B 156 C 335 D 379
**B** (1.9 s): `TURN 18 28` ✓; `CAST 3` ✓

> Ball at (30.2,19.7) heading down-left into D's big block below. GIANT pierces for 3s through D territory. Aim at the D mass (down-left) and cast now.
> 
> CMD: TURN 18 28
> CMD: CAST 3

**C** (3.4 s): `TURN 15.5 25.5` ✓

> Shatter is still active; drive into D’s southern border to steal from the leader and spawn more balls.
> CMD: TURN 15.5 25.5

**D** (4.4 s): `TURN 20 17` ✓; `CAST 3` ✓

> We lead with 379 cells, while C is a close second with 335. Our ball is at (30.6, 23.8) heading up-left directly toward C's massive central territory around (20, 17). Casting ACCEL now and aiming into C's pocket at (20, 17) will let us chew into C's lead before SHATTER comes off cooldown next turn.
> 
> CMD: TURN 20 17
> CMD: CAST 3

**A** (2.8 s): `TURN 16 10` ✓

> Reasoning: C (335) and D (379) are the clear leaders. My ball is heading down-right into my own territory, which is safe but unproductive. SHATTER is ready and can snowball if I turn toward enemy/neutral area first. I'll turn toward C's large block above-left.
> CMD: TURN 16 10

## Decision 13 — t = 36 s — cells A 101 B 268 C 425 D 230
**B** (1.9 s): `TURN 12 14` ✓

> C leads with 425. My ball is at (24.2,3.2) heading up-right into C territory near top. Turn it toward the big C mass in the middle-left so it bounces repeatedly along C cells. Aim down-left into C's center.
> 
> CMD: TURN 12 14

**C** (3.8 s): `TURN 25.5 19.5` ✓

> Pressure B’s right-side border while teleport and shatter recharge.
> CMD: TURN 25.5 19.5

**D** (15.3 s): `TURN 19 20` ✓

> Team C leads with 425 cells. My Teleport and Accel are on a 5s cooldown, while Shatter is ready. I will save Shatter to combo with Teleport + Shatter into C's territory on the next turn. For now, I'll turn up towards C's central block to start chipping away at their lead.
> 
> CMD: TURN 19 20

**A** (3.0 s): `TURN 7 22` ✓

> Reasoning: I'm down badly on cells. Shatter is ready and could give a big boost if I can get my ball into dense enemy territory or along a contested border. I should aim my ball toward the biggest enemy region—team C's large central block—then trigger Shatter next turn when it enters. For now, set a path into that area.
> 
> CMD: TURN 7 22

## Decision 14 — t = 39 s — cells A 106 B 296 C 407 D 215
**B** (1.8 s): `TURN 12 14` ✓

> My ball is deep in my own territory heading down-right. C leads with a huge block to the left. Turn the ball left toward C's mass so it starts flipping cells; teleport and shatter come off cooldown soon for a combo into C's area.
> 
> CMD: TURN 12 14

**C** (3.7 s): `TURN 23.5 15.5` ✓; `CAST 3` ✓

> Accelerate while steering along B’s boundary to gain cells before teleport and shatter recharge.
> CMD: TURN 23.5 15.5
> CMD: CAST 3

**D** (6.9 s): `TURN 16 15` ✓; `CAST 2` ✓

> Teleport and Accel are on cooldown for 2s, while Shatter (15s cd) is ready. Our ball is at (22.8, 24.5) right next to the huge C/B border at row 21-22. Casting Shatter now while aiming into C's massive territory will let us paint a lot of cells and still have Shatter come off cooldown for the final 6 seconds!
> 
> CMD: TURN 16 15
> CMD: CAST 2

**A** (2.7 s): `TURN 3 12` ✓; `CAST 1` ✓

> Reasoning: I'm behind, but my SHATTER is ready and my ball is near the border of enemy territory. The densest enemy area is D's cluster in the lower-left and center. I should turn my ball toward that cluster and then cast SHATTER to maximize converting those cells as it bounces. Fire and teleport are on cooldown.
> 
> CMD: TURN 3 12  
> CMD: CAST 1

## Decision 15 — t = 42 s — cells A 162 B 214 C 345 D 303
**B** (3.7 s): `CAST 1 12.5 10.5` ✓; `TURN 10 8` ✓

> C leads with 345. Teleport into C territory pocket. Shatter is on cooldown for 3 s; teleport now into C's mass and turn toward C's dense centre, so the ball bounces among C cells; cast Shatter next turn. Pick a spot inside C near the big block, e.g., (12.5, 10.5) heading toward C mass.
> 
> CMD: TELEPORT 12.5 10.5
> CMD: TURN 10 8

**C** (3.0 s): `CAST 1 15.5 27.5` ✓; `TURN 20.5 23.5` ✓

> Teleport into D’s dense lower territory to cut down our closest rival and prepare for Shatter next turn.
> CMD: CAST 1 15.5 27.5
> CMD: TURN 20.5 23.5

**D** (7.2 s): `CAST 1 13.5 7.5` ✓; `CAST 3` ✓

> Shatter is still active for 4 seconds! C is leading with 345 cells. I will teleport deep into the middle of C's massive territory at (13.5, 7.5) and cast ACCEL immediately so my main ball and all existing sub-balls rapidly tear through C's block and spawn max shatter balls.
> 
> CMD: CAST 1 13.5 7.5
> CMD: CAST 3

**A** (2.8 s): `CAST 3 11 16` ✓; `TURN 11 16` ✓

> Reasoning: C leads with 345 cells; I need to target their large central block. My TELEPORT will be ready in 2s, but FIRE is ready now and can hit a dense C area quickly. Aiming FIRE at around x=11, y=16 where C is dense.
> 
> CMD: CAST 3 11 16
> CMD: TURN 11 16

## Decision 16 — t = 45 s — cells A 193 B 176 C 150 D 505
**B** (2.1 s): `CAST 2` ✓; `TURN 8 4` ✓

> My ball is at the edge of a huge D block heading up into it. Cast Shatter now so each bounce into D spawns extra balls; point slightly into dense D area (up-left).
> 
> CMD: CAST 2
> CMD: TURN 8 4

**C** (3.7 s): `TURN 19.5 23.5` ✓; `CAST 2` ✓

> Shatter can snowball from this small C pocket into D’s dominant territory. Aim diagonally into D; add acceleration next turn.
> CMD: TURN 19.5 23.5
> CMD: CAST 2

**D** (9.1 s): `TURN 25 9` ✓

> We are comfortably in the lead (505 cells), while A is second (193) and B is third (176). All skills are on cooldown right now. Our ball at (15.1, 3.6) is already heading down-right toward the large B and C territories in the upper-right and middle-right sections. Turning toward (25.0, 9.0) will drive it directly into the dense B/C cluster.
> 
> CMD: TURN 25.0 9.0

**A** (4.3 s): `CAST 2 5 12` ✓

> Reasoning:
> We're in 4th with 193, leader D has 505. Time is low (15s). TELEPORT is ready and SHATTER has 9s cooldown—can't combo now. Best use TELEPORT into a small D pocket to flip a concentrated enemy region quickly. The D pocket near rows 11-13, columns 3-7 looks enclosed by D cells, ideal for bounce-painting. After teleporting there, ball will bounce within D territory, painting multiple cells fast. FIRE is on cooldown, so only teleport now.
> 
> CMD: TELEPORT 5 12

## Decision 17 — t = 48 s — cells A 180 B 301 C 232 D 311
**B** (2.0 s): `TURN 5 4` ✓

> Shatter is still active briefly; D leads by 10. Ball at (12.9,11.2) heading up-left through my own territory. Turn it toward D's block at top-left to flip D cells with remaining shatter balls.
> 
> CMD: TURN 5 4

**C** (3.8 s): `TURN 21.5 20.5` ✓; `CAST 3` ✓

> Shatter is still active: accelerate the swarm and steer into D’s nearby border to cut down the leader.
> CMD: TURN 21.5 20.5
> CMD: CAST 3

**D** (6.2 s): `TURN 12 10` ✓

> We are leading slightly over B (311 vs 301). All skills are on cooldown. Our ball is at (1.1, 12.2) right next to A and B territory. I will aim right into the dense B cluster around (12, 10) to chip away at B's lead and prepare for Shatter+Accel in 6 seconds.
> 
> CMD: TURN 12 10

**A** (3.4 s): `TURN 27 6` ✓

> Reasoning: I'm trailing badly (180 vs leader 311). My ball is in my own A territory heading down-left. TELEPORT and FIRE are on cooldown, SHATTER ready in 6s but won't help immediately. Best move is to turn the ball toward the largest enemy block to start painting. I'll aim at D's big territory near x=27, y=6 where there's a dense D/B area.
> 
> CMD: TURN 27 6

## Decision 18 — t = 51 s — cells A 145 B 344 C 421 D 114
**B** (2.5 s): `TURN 21 32` ✓

> All skills on cooldown. Ball at (20.1,12.9) heading down-right into C's block starting row 14-15. Point it straight down into the big C mass to keep bouncing on C cells.
> 
> CMD: TURN 21 32

**C** (3.7 s): `TURN 17.5 8.5` ✓

> Aim up-right into B’s large block to reduce the closest rival while maintaining our lead.
> CMD: TURN 17.5 8.5

**D** (13.2 s): `TURN 16 12` ✓; `CAST 3` ✓

> We are at (1.8, 9.4) heading right into B's territory. With 9s left, we should cast ACCEL now to carve rapidly into B and prepare for SHATTER in 3 seconds. Turning slightly downward toward (16, 12) keeps us pushing into the dense B/C center rather than getting stuck at the top wall.
> 
> CMD: TURN 16 12
> CMD: CAST 3

**A** (3.7 s): `TURN 18 20` ✓

> We're far behind. Leader is C with 421. Best shot: TELEPORT into a C pocket then SHATTER, but TELEPORT is on cooldown 14s — too long. SHATTER ready in 3s. FIRE ready in 11s — also too long for remaining 9s.
> 
> Current ball is in our own A area heading down-right into C territory. Best play: aim ball into C block and cast SHATTER when ready to maximize paint.
> 
> CMD: TURN 18 20

## Decision 19 — t = 54 s — cells A 137 B 331 C 462 D 94
**B** (2.9 s): `TURN 24 32` ✓

> Ball heading down toward C's mass at row 14-15 around column 24. Giant is on cooldown for 3 s; next decision at 3 s left could cast it. Keep heading down into C territory; ball reaches row 14 at ~8 cells away (0.4 s), then bounces. Turn slightly to keep hitting C border repeatedly.
> 
> CMD: TURN 24 32

**C** (3.0 s): `TURN 18.5 12.5` ✓

> Aim diagonally into B’s central border to pressure the closest rival while preserving our lead.
> CMD: TURN 18.5 12.5

**D** (4.7 s): `TURN 16 16` ✓; `CAST 2` ✓

> With only 6 seconds left, Shatter is our only ready skill and lasts 7s. Our ball is at (1.0, 8.3) heading down-right towards the border of B and A. I will cast Shatter immediately and aim towards the dense enemy territory around (16, 16) to maximize bounces and spawn extra balls.
> 
> CMD: TURN 16 16
> CMD: CAST 2

**A** (3.0 s): `TURN 16 16` ✓; `CAST 1` ✓

> We're far behind (137 vs 462 for leader C). Only 6 seconds left and SHATTER is ready. My ball is at (2.3, 15.3) heading into my own territory, so SHATTER now would be wasted. I need to turn toward C's dense area and cast SHATTER to maximize painting in the final seconds.
> 
> CMD: TURN 16 16
> CMD: CAST 1

## Decision 20 — t = 57 s — cells A 231 B 211 C 363 D 219
**B** (2.4 s): `TURN 18 32` ✓; `CAST 3` ✗ rejected

> Last 3 seconds: Giant is ready. Point the ball down into C's big block below and cast Giant to pierce a wide trail through C territory.
> 
> CMD: TURN 18 32
> CMD: CAST 3

**C** (3.5 s): `TURN 29.5 26.5` ✓; `CAST 3` ✓

> Accelerate and attack A’s nearby border to extend our lead in the final seconds.
> CMD: TURN 29.5 26.5
> CMD: CAST 3

**D** (6.7 s): `TURN 16 10` ✓

> Shatter is active for 4 more seconds and all skills are on cooldown. Our ball is at (11.8, 7.1) heading right towards B's territory at column 16. Turning slightly down-right towards (16, 10) will hit the corner of A and B's cells, keeping the ball bouncing tightly in enemy territory to spawn more shatter balls in the final 3 seconds.
> 
> CMD: TURN 16 10

**A** (3.1 s): `CAST 3 14 25` ✗ rejected

> Final decision, 3s left. I’m behind leader C by 132 cells; need max instant gain. FIRE is ready (slot 3). Target the densest C area: rows 24-27, cols 10-18 are all C. Cast FIRE at (14, 25) to paint ~29 cells instantly, aiming at C’s core. No time for teleport/shatter (cooldowns).
> 
> CMD: CAST 3 14 25
