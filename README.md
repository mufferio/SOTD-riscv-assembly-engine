# SOTD — RISC-V Assembly Engine

A terminal-based survival horror game written entirely in **RISC-V assembly**, designed to run in the [RARS](https://github.com/TheThirdOne/rars) (RISC-V Assembler and Runtime Simulator). Navigate an 8×8 grid, collect a match, light the stick, and escape the shadow monster — all before your fear factor reaches 100.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Game Mechanics](#game-mechanics)
  - [Board Layout](#board-layout)
  - [Entities](#entities)
  - [Win & Loss Conditions](#win--loss-conditions)
  - [Fear Factor](#fear-factor)
  - [Undo System](#undo-system)
  - [Multiplayer Competitive Mode](#multiplayer-competitive-mode)
- [Controls](#controls)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Running the Game](#running-the-game)
- [Architecture](#architecture)
  - [Data Segment](#data-segment)
  - [Core Routines](#core-routines)
  - [RARS Syscalls Used](#rars-syscalls-used)
- [Project Structure](#project-structure)
- [Enhancements](#enhancements)

---

## Overview

SOTD (Shadows of the Dark) is a single-file RISC-V assembly project that implements a grid-based stealth-survival game. The player must locate a match, then find and light a stick while avoiding a pursuing shadow monster. Two custom enhancements extend the base game: an **infinite undo stack** and a **multiplayer competitive mode** with an end-of-round leaderboard.

---

## Features

| Feature | Description |
|---|---|
| 8×8 grid world | ASCII-art board rendered each turn |
| Randomized map | Entity positions are seeded from the system clock each new game |
| Monster AI | The shadow monster pursues the player one step per turn (row-first Chebyshev movement) |
| Fear factor | Proximity to the monster increases a 0–100 fear gauge |
| Monster teleport | Each time fear increases, the monster is relocated to a non-adjacent cell |
| Infinite undo | Up to 512 game-state snapshots (8 bytes each) stored in a 4 KB ring buffer |
| Multiplayer mode | 1–8 players compete on the **same** randomly-generated map; final leaderboard ranks by lowest fear |

---

## Game Mechanics

### Board Layout

```
  0 1 2 3 4 5 6 7
<| | | | | | | | |>0
<| | | | | | | | |>1
...
<| | | | | | | | |>7
```

Column indices are shown across the top; row indices down the right side. Each cell is two characters wide in the ASCII frame.

### Entities

| Symbol | Entity | Description |
|---|---|---|
| `C` | Character | The player-controlled entity |
| `!` | Match | Collectible item; disappears when picked up |
| `1` | Stick | Goal object; disappears when lit |
| `M` | Shadow Monster | Pursues the player each turn |

All four entities are placed on unique, non-overlapping cells at the start of each game using a clock-seeded pseudo-random allocator (`alloc_unique_xy`).

### Win & Loss Conditions

| Condition | Outcome |
|---|---|
| Walk onto `!` | Match is collected (flag set, symbol removed) |
| Walk onto `1` while holding match | Stick is lit → **You win** |
| Walk onto `1` without a match | Message displayed; game continues |
| Fear factor reaches 100 | **You lose** |
| Monster occupies same cell as player | **Game over** |
| Press `q` | Forfeit current run |

### Fear Factor

The fear gauge increases by **10 points** whenever the shadow monster is within a **Chebyshev radius of 1** (i.e., any of the 8 immediately surrounding cells, including diagonals). After each fear increase the monster is teleported to a random cell that is:

- More than 1 cell away from the player (Chebyshev distance > 1)
- Not on the match (if not yet picked up)
- Not on the stick (if not yet lit)

### Undo System

Pressing `U` (or `u`) reverts the game to the state before the previous move.

**Implementation details:**

- Each snapshot occupies exactly **8 bytes**:
  - Bytes 0–1: character row/col
  - Bytes 2–3: monster row/col
  - Byte 4: `matchPicked` flag
  - Byte 5: `stickLit` flag
  - Byte 6: `fearFactor`
  - Byte 7: reserved (zero)
- The undo buffer is **4096 bytes**, giving capacity for **512 snapshots**
- The buffer is treated as a FIFO stack via the `undo_top` word pointer; on overflow the pointer is clamped to the last valid slot
- The undo stack is reset at the start of each player's turn in multiplayer mode

### Multiplayer Competitive Mode

At startup the player is prompted: `Enter number of players (1-8):`

- Valid input is clamped to the range [1, 8]
- All players compete on the **identical** randomly-generated map (initial positions are saved before the first player's turn and restored for each subsequent player)
- After each player's run ends (win, loss, or forfeit) their `fearFactor` score is recorded
- Once all players have played, a leaderboard is displayed:

```
Leaderboard (lower fear is better):
Player 2: 10
Player 1: 40
Player 3: 70
```

The leaderboard is sorted in ascending order by fear score using an in-place **selection sort** on an `order_idx` array.

---

## Controls

| Key | Action |
|---|---|
| `w` | Move up (decrease row) |
| `s` | Move down (increase row) |
| `a` | Move left (decrease column) |
| `d` | Move right (increase column) |
| `U` / `u` | Undo last move |
| `q` | Quit / forfeit current run |

Movement into a wall boundary prints `Can't walk into a wall!` and does not consume the turn's snapshot.

---

## Getting Started

### Prerequisites

- **Java 8+** (required to run RARS)
- **RARS** — download the latest JAR from [https://github.com/TheThirdOne/rars/releases](https://github.com/TheThirdOne/rars/releases)

### Running the Game

1. Clone or download this repository.
2. Launch RARS:
   ```bash
   java -jar rars.jar
   ```
3. Open `sotd-engine.s` via **File → Open**.
4. Click **Assemble** (F3), then **Run** (F5).
5. Interact with the game through the RARS console/terminal panel.

> **Tip:** RARS must be run with its default I/O mode. The game uses the `read char` syscall (ecall 12), which requires the RARS console to have focus when entering a key.

---

## Architecture

### Data Segment

| Label | Size | Purpose |
|---|---|---|
| `gridsize` | 2 bytes | Board dimensions (8×8) |
| `character` | 2 bytes | Player row/col |
| `match` | 2 bytes | Match row/col |
| `stick` | 2 bytes | Stick row/col |
| `shadowMonster` | 2 bytes | Monster row/col |
| `fearFactor` | 1 byte | Current fear level (0–100) |
| `used_cells` | 8 bytes | Bitmask of occupied cells for unique placement |
| `board` | ~189 bytes | ASCII art template (null-terminated) |
| `frame` | 200 bytes | Mutable working copy of the board for each render |
| `matchPicked` | 1 byte | Flag: match has been collected |
| `stickPicked` | 1 byte | Flag: player is on stick (unused in display logic) |
| `stickLit` | 1 byte | Flag: stick has been lit (win condition met) |
| `undo_buf` | 4096 bytes | Circular undo snapshot buffer |
| `undo_top` | 4 bytes (word) | Index of next free undo slot |
| `playersCount` | 1 byte | Total number of players (1–8) |
| `playerIndex` | 1 byte | Current player index (0-based) |
| `scores` | 8 bytes | Fear score recorded for each player |
| `order_idx` | 8 bytes | Sorted player indices for leaderboard |
| `init_*` | 2 bytes × 4 | Snapshot of initial entity positions for map reuse |

### Core Routines

| Routine | Description |
|---|---|
| `_start` | Entry point; allocates entity positions, saves initial map, prompts for player count |
| `reset_for_player` | Restores entity positions and resets per-run state for the next player |
| `game` | Main game loop: renders frame, reads input, processes movement, checks win/loss |
| `exit` | Records fear score, advances player index, shows leaderboard or exits |
| `push_state` | Saves an 8-byte snapshot to `undo_buf` |
| `pop_state` | Restores the most recent snapshot from `undo_buf` |
| `move_shadow_towards` | Moves monster one step toward the player (row-first, clamped) |
| `relocate_monster_unique` | Teleports monster to a random non-adjacent, non-item cell |
| `alloc_unique_xy` | Allocates a unique (row, col) using the `used_cells` bitmask |
| `notrand` | Pseudo-random number in `[0, MAX)` using the RARS time syscall |
| `add_char_obj` | Writes a single character into the correct cell of `frame` |
| `copy_z` | Copies a null-terminated string (used to reset `frame` from `board` template) |
| `show_leaderboard` | Selection-sorts `order_idx` by `scores`, then prints ranked results |

### RARS Syscalls Used

| Ecall # | Service | Usage |
|---|---|---|
| 1 | Print Integer | Display fear value, player number |
| 4 | Print String | Display board frame and messages |
| 10 | Exit | Terminate after leaderboard |
| 12 | Read Character | Capture single-key player input |
| 30 | Time (ms) | Seed for `notrand` pseudo-RNG |
| 32 | Sleep | Brief pause inside `notrand` to improve randomness |

---

## Project Structure

```
SOTD-riscv-assembly-engine/
├── sotd-engine.s   # Complete RISC-V assembly source (game engine + enhancements)
├── User Guide.pdf  # Detailed user-facing documentation
└── README.md       # This file
```

---

## Enhancements

Two major enhancements were added on top of the base game specification:

### 1. Infinite Undo
A stack-based undo mechanism stores up to **512 game-state snapshots** (effectively infinite for a typical session). Each snapshot packs all mutable per-turn state into 8 bytes. Pressing `U` or `u` pops the most recent snapshot and restores the game exactly as it was before that move, including the monster position, item pickup flags, and fear level.

### 2. Multiplayer Competitive Mode
Up to **eight players** can compete sequentially on the same map instance. All players start with identical entity positions, ensuring a fair comparison. At the end of all turns, a **selection-sort leaderboard** ranks players from lowest (best) to highest fear score, rewarding skilful play.
