# I implemented the infinite undo enhancement. The character reader is underneath branch 2 in game loop
# where if user inputs 'U' it will do the pop_state at branch .do_undo. it will then do the
# push_state (method) which saves a snapshot of that move each loop that happens, so that if
# 'U' pressed it can revert to the previous snapshot. whether or not U is pressed, after the inputs
# are taken it will then run the push state which handles saving all the data into undo_buf, and then 
# undo_top is made to point at the next free slot for the next snapshot. each snapshot is 8 bytes with
# a total space of 4096 bytes. This deems the undo as "virtually infinite" as it allows for a total of 
# 512 snapshots to be saved. 

# I also implemented the multiplayer competitive mode enhancement, at the beginning of the game
# loop, the user is prompted for how many players (1-8). this is controlled by 
# read_players branch which ensures that the inputted number is correct.
# Depending on the input, this branch will jump to one of three other branches.
# This number is used to update playersCount and playerIndex in .data. Once that is done, it leads to
# reset_for_player branch which resets the board so that that each player plays on the same random
# instance of the board. It tracks stats and also sends a message with the player numbers turn as well
# as a "press q t0 forfeit" message. then game loop runs which is unchanged. at the end of each players
# turn it then moves to the exit which saves fearfactor to scores[playerIndex] and then increments to
# the next player. this loops until playerIndex < playersCount is not satisfied. When thats the case,
# the exit branch goes to the last case which allows for the leaderboard to show with all of the players
# scores and final rankings. this leads to the init of order_idx[i] for i till N-1. this is then selection
# sorted with the lower fear being better, which finally prints the leaderboard.

.data
gridsize:         .byte 8,8
character:        .byte 0,0
match:            .byte 0,0
stick:            .byte 0,0
shadowMonster:    .byte 0,0
fearFactor:       .byte 0
used_cells:       .byte 0,0,0,0,0,0,0,0

board:
    .ascii "  0 1 2 3 4 5 6 7   \n"
    .ascii "<| | | | | | | | |>0\n"
    .ascii "<| | | | | | | | |>1\n"
    .ascii "<| | | | | | | | |>2\n"
    .ascii "<| | | | | | | | |>3\n"
    .ascii "<| | | | | | | | |>4\n"
    .ascii "<| | | | | | | | |>5\n"
    .ascii "<| | | | | | | | |>6\n"
    .ascii "<| | | | | | | | |>7\n"
    .byte 0

frame:           .space 200

matchPicked:     .byte 0
stickPicked:     .byte 0

msg_wall:        .ascii "Can't walk into a wall!\n"   # 0-terminated for syscall 4
                 .byte 0
msg_pick_match:  .ascii "Picked up a match!\n"
                 .byte 0
msg_fear_up:     .ascii "Fear factor increased!\n"
                 .byte 0
msg_fear_lose:   .ascii "Fear reached 100. You lose.\n"
                 .byte 0
msg_game_over:   .ascii "The monster got you! Game over.\n"
                 .byte 0
msg_fear_to:     .ascii "Fear factor increased to "
                 .byte 0
msg_newline:     .ascii "\n"
                 .byte 0

stickLit:        .byte 0

msg_need_match:  .ascii "You need a match to light the stick!\n"
                 .byte 0
msg_win:         .ascii "You lit the stick! You win.\n"
                 .byte 0

# --- Multiplayer additions (prompts/labels) ---
msg_players_prompt: .ascii "Enter number of players (1-8): "
                    .byte 0
msg_player_label:   .ascii "Player "
                    .byte 0
msg_turn_descr:     .ascii " turn. Press q to forfeit.\n"
                    .byte 0
msg_leaderboard:    .ascii "Leaderboard (lower fear is better):\n"
                    .byte 0
msg_colon_space:    .ascii ": "
                    .byte 0

# --- Multiplayer state ---
playersCount:    .byte 1
playerIndex:     .byte 0
scores:          .space 8          # fear result per player (max 8)
order_idx:       .space 8          # indices for sorting

# --- Initial map snapshot (to reuse same map each round) ---
init_character:  .byte 0,0
init_match:      .byte 0,0
init_stick:      .byte 0,0
init_monster:    .byte 0,0

# undo buffer
.equ UNDO_ENT, 8
.equ UNDO_CAP, 4096
.balign 4
undo_buf:        .space UNDO_CAP
.balign 4
undo_top:        .word 0

.equ HEADER_LEN, 21
.equ ROW_LEN,   21

.text
.global _start

_start:
    la   t0, character
    jal  ra, alloc_unique_xy
    sb   a0, 0(t0)
    sb   a1, 1(t0)
    mv   s0, t0

    la   t0, match
    jal  ra, alloc_unique_xy
    sb   a0, 0(t0)
    sb   a1, 1(t0)
    mv   s1, t0

    la   t0, stick
    jal  ra, alloc_unique_xy
    sb   a0, 0(t0)
    sb   a1, 1(t0)
    mv   s2, t0

    la   t0, shadowMonster
    jal  ra, alloc_unique_xy
    sb   a0, 0(t0)
    sb   a1, 1(t0)
    mv   s3, t0

    la   s4, frame
    addi s4, s4, HEADER_LEN

    # --- Save initial map so every player plays the same map ---
    la   t0, init_character
    lbu  t1, 0(s0)
    lbu  t2, 1(s0)
    sb   t1, 0(t0)
    sb   t2, 1(t0)
    la   t0, init_match
    lbu  t1, 0(s1)
    lbu  t2, 1(s1)
    sb   t1, 0(t0)
    sb   t2, 1(t0)
    la   t0, init_stick
    lbu  t1, 0(s2)
    lbu  t2, 1(s2)
    sb   t1, 0(t0)
    sb   t2, 1(t0)
    la   t0, init_monster
    lbu  t1, 0(s3)
    lbu  t2, 1(s3)
    sb   t1, 0(t0)
    sb   t2, 1(t0)

    # --- Prompt for number of players (single digit 1..8) ---
    la   a0, msg_players_prompt
    li   a7, 4
    ecall
.read_players:
    li   a7, 12
    ecall
    mv   t0, a0           # ASCII
    addi t0, t0, -48      # to number
    li   t1, 1
    blt  t0, t1, .set1
    li   t1, 8
    bgt  t0, t1, .set8
    j    .okN
.set1:
    li   t0, 1
    j    .okN
.set8:
    li   t0, 8
.okN:
    la   t1, playersCount
    sb   t0, 0(t1)
    la   t1, playerIndex
    sb   x0, 0(t1)

# --- Prepare first player from initial map snapshot ---
reset_for_player:
    # Restore initial positions
    la   t0, init_character
    lbu  t1, 0(t0)
    lbu  t2, 1(t0)
    sb   t1, 0(s0)
    sb   t2, 1(s0)
    la   t0, init_match
    lbu  t1, 0(t0)
    lbu  t2, 1(t0)
    sb   t1, 0(s1)
    sb   t2, 1(s1)
    la   t0, init_stick
    lbu  t1, 0(t0)
    lbu  t2, 1(t0)
    sb   t1, 0(s2)
    sb   t2, 1(s2)
    la   t0, init_monster
    lbu  t1, 0(t0)
    lbu  t2, 1(t0)
    sb   t1, 0(s3)
    sb   t2, 1(s3)
    # Reset per-run flags and gauges
    la   t0, matchPicked
    sb   x0, 0(t0)
    la   t0, stickLit
    sb   x0, 0(t0)
    la   t0, fearFactor
    sb   x0, 0(t0)
    # Reset undo stack
    la   t0, undo_top
    sw   x0, 0(t0)

    # Announce current player
    la   a0, msg_player_label
    li   a7, 4
    ecall
    la   t0, playerIndex
    lbu  t1, 0(t0)
    addi t1, t1, 1        # 1-based for printing
    mv   a0, t1
    li   a7, 1
    ecall
    la   a0, msg_turn_descr
    li   a7, 4
    ecall

game:
    # rebuild frame from template
    la   a0, frame
    la   a1, board
    jal  ra, copy_z

    # place all objects
    # character
    mv   a0, s4
    lbu  a1, 0(s0)
    lbu  a2, 1(s0)
    li   a3, 'C'
    jal  ra, add_char_obj

    # match (only if not picked)
    la   s5, matchPicked
    lbu  s5, 0(s5)
    bnez s5, 1f
    mv   a0, s4
    lbu  a1, 0(s1)
    lbu  a2, 1(s1)
    li   a3, '!'
    jal  ra, add_char_obj
1:
    # stick (only if not lit)
    la   s5, stickLit
    lbu  s5, 0(s5)
    bnez s5, 2f
    mv   a0, s4
    lbu  a1, 0(s2)
    lbu  a2, 1(s2)
    li   a3, '1'
    jal  ra, add_char_obj
2:
    # monster
    mv   a0, s4
    lbu  a1, 0(s3)
    lbu  a2, 1(s3)
    li   a3, 'M'
    jal  ra, add_char_obj

    # print this frame
    la   a0, frame
    li   a7, 4
    ecall

    # read one key
    li   a7, 12
    ecall
    mv   t6, a0

    # undo key (handle both 'U' and 'u')
    li   t3, 'U'
    beq  t6, t3, .do_undo
    li   t3, 'u'
    beq  t6, t3, .do_undo

    # snapshot before applying move
    jal  ra, push_state

    # handle input
    la   t0, character
    lbu  t1, 0(t0)
    lbu  t2, 1(t0)

    li   t3, 'w'
    bne  t6, t3, 1f
    beqz t1, .wall_msg
    addi t1, t1, -1
    j    3f
1:
    li   t3, 's'
    bne  t6, t3, 2f
    li   t4, 7
    beq  t1, t4, .wall_msg
    addi t1, t1, 1
    j    3f
2:
    li   t3, 'a'
    bne  t6, t3, 4f
    beqz t2, .wall_msg
    addi t2, t2, -1
    j    3f
4:
    li   t3, 'd'
    bne  t6, t3, 5f
    li   t4, 7
    beq  t2, t4, .wall_msg
    addi t2, t2, 1
    j    3f
5:
    li   t3, 'q'
    bne  t6, t3, 3f
    j    exit

.wall_msg:
    la   a0, msg_wall
    li   a7, 4
    ecall
    # fall through

3:
    sb   t1, 0(t0)
    sb   t2, 1(t0)

    # --- Pick up match if on it (first time only) ---
    la   s5, matchPicked
    lbu  s5, 0(s5)
    bnez s5, 6f
    lbu  s6, 0(s1)        # match row
    lbu  s7, 1(s1)        # match col
    bne  t1, s6, 6f
    bne  t2, s7, 6f
    li   s5, 1
    la   s6, matchPicked
    sb   s5, 0(s6)
    la   a0, msg_pick_match
    li   a7, 4
    ecall

6:
    # --- Try to light stick if standing on it and have match ---
    lbu  s6, 0(s2)        # stick row
    lbu  s7, 1(s2)        # stick col
    bne  t1, s6, 7f
    bne  t2, s7, 7f
    # on stick: check if already lit
    la   s5, stickLit
    lbu  s5, 0(s5)
    bnez s5, 7f
    # need a match?
    la   s5, matchPicked
    lbu  s5, 0(s5)
    beqz s5, .need_match
    # light it -> win
    li   s5, 1
    la   s6, stickLit
    sb   s5, 0(s6)
    la   a0, msg_win
    li   a7, 4
    ecall
    j    exit

.need_match:
    la   a0, msg_need_match
    li   a7, 4
    ecall

7:
    # monster chases by one step
    la   a0, shadowMonster
    la   a1, character
    jal  ra, move_shadow_towards

    # Fresh positions
    la   t0, character
    lbu  t1, 0(t0)        # cr
    lbu  t2, 1(t0)        # cc
    la   t0, shadowMonster
    lbu  t3, 0(t0)        # mr
    lbu  t4, 1(t0)        # mc

    # --- Fear factor: +10 if within 1-cell radius (Chebyshev <= 1) ---
    sub  t5, t3, t1       # dr
    blt  t5, x0, 9f
    j    10f
9:
    neg  t5, t5
10:
    sub  t6, t4, t2       # dc
    blt  t6, x0, 11f
    j    12f
11:
    neg  t6, t6
12:
    li   t0, 1
    bgt  t5, t0, 15f
    bgt  t6, t0, 15f

    # fearFactor += 10
    la   s5, fearFactor
    lbu  s6, 0(s5)
    addi s6, s6, 10
    sb   s6, 0(s5)

    # print "Fear factor increased to <val>\n"
    la   a0, msg_fear_to
    li   a7, 4
    ecall
    mv   a0, s6           # print_int expects value in a0
    li   a7, 1            # print_int
    ecall
    la   a0, msg_newline
    li   a7, 4
    ecall

    # relocate monster to a random non-colliding cell
    jal  ra, relocate_monster_unique

    # Lose if fear >= 100
    li   t0, 100
    blt  s6, t0, 15f
    la   a0, msg_fear_lose
    li   a7, 4
    ecall
    j    exit

15:
    j    game

.do_undo:
    jal  ra, pop_state
    j    game

# --- End of a player's run: record fear and move to next player or show leaderboard ---
exit:
    # Save current fear to scores[playerIndex]
    la   t0, playerIndex
    lbu  t1, 0(t0)              # t1 = idx
    la   t2, scores
    add  t2, t2, t1
    la   t3, fearFactor
    lbu  t4, 0(t3)
    sb   t4, 0(t2)

    # Advance playerIndex
    addi t1, t1, 1
    sb   t1, 0(t0)

    # If more players left -> reset and start next player
    la   t5, playersCount
    lbu  t6, 0(t5)
    blt  t1, t6, reset_for_player

    # Otherwise, show leaderboard and quit
    jal  ra, show_leaderboard
    li   a7, 10
    ecall


# --- HELPER FUNCTIONS ---

# a0 = &dst, a1 = &src; copy bytes from src to dst until 0x00 (inclusive)
.global copy_z
copy_z:
    addi sp, sp, -12
    sw   ra, 8(sp)
    sw   t0, 4(sp)
    sw   t1, 0(sp)
.cpy:
    lbu  t0, 0(a1)        # read src byte
    sb   t0, 0(a0)        # write to dst
    addi a0, a0, 1        # dst++
    addi a1, a1, 1        # src++
    bnez t0, .cpy         # stop when byte == 0
    lw   t1, 0(sp)
    lw   t0, 4(sp)
    lw   ra, 8(sp)
    addi sp, sp, 12
    ret

# Rebuilds used_cells from CURRENT state, then calls alloc_unique_xy.
# Picks a random (row,col) not on/adjacent to character and not on match/stick (when present).
# Writes into shadowMonster.
relocate_monster_unique:
    addi sp, sp, -24
    sw   ra, 20(sp)
    sw   t0, 16(sp)
    sw   t1, 12(sp)
    sw   t2, 8(sp)
    sw   t3, 4(sp)
    sw   t4, 0(sp)

    # cache character row/col
    lbu  t3, 0(s0)        # cr
    lbu  t4, 1(s0)        # cc

.pick:
    # random cell -> t0=row, t1=col
    li   a0, 64
    jal  ra, notrand
    srli t0, a0, 3
    andi t1, a0, 7

    # reject if on/adjacent to character: max(|dr|,|dc|) <= 1
    sub  t2, t0, t3       # dr
    blt  t2, x0, 1f
    j    2f
1:
    neg  t2, t2
2:
    sub  t5, t1, t4       # dc
    blt  t5, x0, 3f
    j    4f
3:
    neg  t5, t5
4:
    li   t6, 1
    ble  t2, t6, .adj_chk_dc
    j    .chk_match
.adj_chk_dc:
    ble  t5, t6, .pick    # within radius 1 -> try again

.chk_match:
    # if match not picked, reject if equals match
    la   t6, matchPicked
    lbu  t6, 0(t6)
    bnez t6, .chk_stick
    lbu  a0, 0(s1)        # match row
    lbu  a1, 1(s1)        # match col
    beq  t0, a0, 5f
    j    .chk_stick
5:
    beq  t1, a1, .pick

.chk_stick:
    # if stick not lit, reject if equals stick
    la   t6, stickLit
    lbu  t6, 0(t6)
    bnez t6, .ok
    lbu  a0, 0(s2)        # stick row
    lbu  a1, 1(s2)        # stick col
    beq  t0, a0, 6f
    j    .ok
6:
    beq  t1, a1, .pick

.ok:
    la   a0, shadowMonster
    sb   t0, 0(a0)
    sb   t1, 1(a0)

    lw   t4, 0(sp)
    lw   t3, 4(sp)
    lw   t2, 8(sp)
    lw   t1, 12(sp)
    lw   t0, 16(sp)
    lw   ra, 20(sp)
    addi sp, sp, 24
    ret

# a0 = ptr to monster coords [row, col] (bytes)
# a1 = ptr to character coords [row, col] (bytes)
move_shadow_towards:
    addi sp, sp, -24
    sw   ra, 20(sp)
    sw   t0, 16(sp)
    sw   t1, 12(sp)
    sw   t2, 8(sp)
    sw   t3, 4(sp)
    sw   t4, 0(sp)

    # load row/col
    lbu  t0, 0(a0)        # mr
    lbu  t1, 1(a0)        # mc
    lbu  t2, 0(a1)        # cr
    lbu  t3, 1(a1)        # cc

    # row step
    sub  t4, t2, t0
    beq  t4, x0, .do_col
    slt  t5, x0, t4
    beqz t5, .dec_row
    addi t0, t0, 1
    j    .clamp_row
.dec_row:
    addi t0, t0, -1
.clamp_row:
    # clamp mr into [0,7]
    li   t6, 255
    bne  t0, t6, .chk_hi_r
    li   t0, 0
.chk_hi_r:
    sltiu t6, t0, 8
    bnez t6, .write_back
    li   t0, 7
    j    .write_back

.do_col:
    sub  t4, t3, t1       # dc = cc - mc
    beq  t4, x0, .write_back
    slt  t5, x0, t4
    beqz t5, .dec_col
    addi t1, t1, 1
    j    .clamp_col
.dec_col:
    addi t1, t1, -1
.clamp_col:
    # clamp mc into [0,7]
    li   t6, 255
    bne  t1, t6, .chk_hi_c
    li   t1, 0
.chk_hi_c:
    sltiu t6, t1, 8
    bnez t6, .write_back
    li   t1, 7

    # prevent stepping onto the character cell
    lbu  t2, 0(a1)        # cr
    lbu  t3, 1(a1)        # cc
    bne  t0, t2, 90f
    bne  t1, t3, 90f
    # cancel move: reload original mr,mc from a0
    lbu  t0, 0(a0)
    lbu  t1, 1(a0)
90:
.write_back:
    sb   t0, 0(a0)
    sb   t1, 1(a0)

    lw   t4, 0(sp)
    lw   t3, 4(sp)
    lw   t2, 8(sp)
    lw   t1, 12(sp)
    lw   t0, 16(sp)
    lw   ra, 20(sp)
    addi sp, sp, 24
    ret

# a0 = pointer to the first row's first char
# a1 = row
# a2 = col
# a3 = character to write
# each row is 21 bytes long; content starts 2 bytes in; each column shifts 2 bytes
# row = x, x*21 = x*(16 + 4 + 1)
# col = y, y*2
add_char_obj:
    # row calculations
    slli t0, a1, 4
    slli t1, a1, 2
    add  t0, t0, t1
    add  t0, t0, a1

    addi t0, t0, 2
    slli t2, a2, 1
    add  t0, t0, t2

    # final: base + row + col
    add  t0, t0, a0

    # store char
    sb   a3, 0(t0)
    ret

# Return:
# a0 = x in [0,7]
# a1 = y in [0,7]
alloc_unique_xy:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   t0, 8(sp)
    sw   t1, 4(sp)
    sw   t2, 0(sp)
Pick:
    li   a0, 64
    jal  ra, notrand
    mv   t0, a0

    srli t1, t0, 3
    andi t2, t0, 7

    la   t3, used_cells
    add  t3, t3, t1

    lbu  t4, 0(t3)
    li   t5, 1
    sll  t5, t5, t2

    and  t6, t4, t5
    bnez t6, Pick

    or   t4, t4, t5
    sb   t4, 0(t3)

    srli a0, t0, 3
    andi a1, t0, 7

    lw   t2, 0(sp)
    lw   t1, 4(sp)
    lw   t0, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# Arguments: MAX in a0
# Return: 0 <= a0 < MAX
notrand:
    mv   t0, a0
    li   a7, 30
    ecall                 # time syscall (ms)
    remu a0, a0, t0       # modulus on bottom bits
    li   a7, 32
    ecall                 # tiny sleep
    jr   ra

# push state
push_state:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   t0, 8(sp)
    sw   t1, 4(sp)
    sw   t2, 0(sp)

    la   t0, undo_top
    lw   t1, 0(t0)
    li   t2, UNDO_CAP - UNDO_ENT
    bleu t1, t2, 1f
    li   t1, UNDO_CAP - UNDO_ENT
1:
    la   t2, undo_buf
    add  t2, t2, t1

    lbu  a0, 0(s0)
    lbu  a1, 1(s0)
    lbu  a2, 0(s3)
    lbu  a3, 1(s3)
    sb   a0, 0(t2)
    sb   a1, 1(t2)
    sb   a2, 2(t2)
    sb   a3, 3(t2)

    la   a0, matchPicked
    lbu  a0, 0(a0)
    la   a1, stickLit
    lbu  a1, 0(a1)
    la   a2, fearFactor
    lbu  a2, 0(a2)
    sb   a0, 4(t2)
    sb   a1, 5(t2)
    sb   a2, 6(t2)
    sb   x0, 7(t2)

    addi t1, t1, UNDO_ENT
    sw   t1, 0(t0)

    lw   t2, 0(sp)
    lw   t1, 4(sp)
    lw   t0, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# pop state
pop_state:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   t0, 8(sp)
    sw   t1, 4(sp)
    sw   t2, 0(sp)

    la   t0, undo_top
    lw   t1, 0(t0)
    beqz t1, 2f
    addi t1, t1, -UNDO_ENT
    sw   t1, 0(t0)

    la   t2, undo_buf
    add  t2, t2, t1

    lbu  a0, 0(t2)
    lbu  a1, 1(t2)
    lbu  a2, 2(t2)
    lbu  a3, 3(t2)
    sb   a0, 0(s0)
    sb   a1, 1(s0)
    sb   a2, 0(s3)
    sb   a3, 1(s3)

    lbu  a0, 4(t2)
    lbu  a1, 5(t2)
    lbu  a2, 6(t2)
    la   t2, matchPicked
    sb   a0, 0(t2)
    la   t2, stickLit
    sb   a1, 0(t2)
    la   t2, fearFactor
    sb   a2, 0(t2)
2:
    lw   t2, 0(sp)
    lw   t1, 4(sp)
    lw   t0, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# --- Leaderboard: sort ascending fear and print ---
# Uses selection sort on order_idx[0..N-1] keyed by scores[]
show_leaderboard:
    addi sp, sp, -32
    sw   ra, 28(sp)
    sw   t0, 24(sp)
    sw   t1, 20(sp)
    sw   t2, 16(sp)
    sw   t3, 12(sp)
    sw   t4, 8(sp)
    sw   t5, 4(sp)
    sw   t6, 0(sp)

    la   t0, playersCount
    lbu  t1, 0(t0)          # t1 = N

    # init order_idx[i] = i
    la   t2, order_idx
    li   t3, 0
.init_loop:
    bge  t3, t1, .sort_start
    add  t4, t2, t3
    sb   t3, 0(t4)
    addi t3, t3, 1
    j    .init_loop

.sort_start:
    la   t2, order_idx
    la   t5, scores
    li   t3, 0              # i
.outer:
    bge  t3, t1, .print_board
    mv   t6, t3             # minIdx = i
    addi t4, t3, 1          # j = i+1
.inner:
    bge  t4, t1, .swap_if
    # if scores[order[j]] < scores[order[minIdx]] -> minIdx = j
    add  a0, t2, t4
    lbu  a0, 0(a0)          # ord_j
    add  a0, t5, a0
    lbu  a0, 0(a0)          # score_j

    add  a1, t2, t6
    lbu  a1, 0(a1)          # ord_min
    add  a1, t5, a1
    lbu  a1, 0(a1)          # score_min
    bge  a0, a1, .no_min
    mv   t6, t4
.no_min:
    addi t4, t4, 1
    j    .inner

.swap_if:
    beq  t6, t3, .next_i
    # swap order[i] and order[minIdx]
    add  a0, t2, t3
    lbu  a1, 0(a0)
    add  a2, t2, t6
    lbu  a3, 0(a2)
    sb   a3, 0(a0)
    sb   a1, 0(a2)
.next_i:
    addi t3, t3, 1
    j    .outer

.print_board:
    la   a0, msg_leaderboard
    li   a7, 4
    ecall
    # print each: "Player <n>: <fear>\n"
    li   t3, 0
.print_loop:
    bge  t3, t1, .done_board

    # t4 = idx (0-based), t5 = display number (1-based)
    add  t4, t2, t3
    lbu  t4, 0(t4)          # idx
    addi t5, t4, 1          # 1-based player number

    # "Player "
    la   a0, msg_player_label
    li   a7, 4
    ecall

    # print the saved number (not the pointer)
    mv   a0, t5
    li   a7, 1
    ecall

    # ": "
    la   a0, msg_colon_space
    li   a7, 4
    ecall

    # fear value for that player
    la   a3, scores
    add  a3, a3, t4        # use idx to index scores
    lbu  a0, 0(a3)
    li   a7, 1
    ecall

    # newline
    la   a0, msg_newline
    li   a7, 4
    ecall

    addi t3, t3, 1
    j    .print_loop

.done_board:
    lw   t6, 0(sp)
    lw   t5, 4(sp)
    lw   t4, 8(sp)
    lw   t3, 12(sp)
    lw   t2, 16(sp)
    lw   t1, 20(sp)
    lw   t0, 24(sp)
    lw   ra, 28(sp)
    addi sp, sp, 32
    ret

