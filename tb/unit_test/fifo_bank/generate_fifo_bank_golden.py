from collections import deque
from pathlib import Path

# Configuration

NUM_LANES = 4
DATA_WIDTH = 32
DEPTH = 4
NUM_TESTS = 15
OUTPUT_DIR = Path(__file__).parent / "vectors"

INPUT_FILE = OUTPUT_DIR / "fifo_bank_input.hex"
GOLDEN_FILE = OUTPUT_DIR / "fifo_bank_golden.hex"

# Test vectors
# Each entry:
# (
#     wren_mask,
#     pop_mask,
#     [lane0_data, lane1_data, lane2_data, lane3_data]
# )
# Bit mapping:
#
# bit0 = Lane 0
# bit1 = Lane 1
# bit2 = Lane 2
# bit3 = Lane 3

test_vectors = [

    # Cycle 0
    # Write Lane0 = 0x11
    # Write Lane1 = 0x101
    (
        0b0011,
        0b0000,
        [0x00000011, 0x00000101, 0x00000000, 0x00000000]
    ),

    # Cycle 1
    # Lane0 second word = 0x22
    # Lane2 first word  = 0x201
    (
        0b0101,
        0b0000,
        [0x00000022, 0x00000000, 0x00000201, 0x00000000]
    ),

    # Cycle 2
    # Idle - allow read-ahead
    (
        0b0000,
        0b0000,
        [0, 0, 0, 0]
    ),

    # Cycle 3
    # Write Lane3
    (
        0b1000,
        0b0000,
        [0x00000000, 0x00000000, 0x00000000, 0x00000301]
    ),

    # Cycle 4
    # Pop Lane0 : expect 0x11 consumed
    (
        0b0000,
        0b0001,
        [0, 0, 0, 0]
    ),

    # Cycle 5
    # Idle - Lane0 should refill with 0x22
    (
        0b0000,
        0b0000,
        [0, 0, 0, 0]
    ),

    # Cycle 6
    # Pop Lane1 : consume 0x101
    (
        0b0000,
        0b0010,
        [0, 0, 0, 0]
    ),

    # Cycle 7
    # Write new Lane1 value
    (
        0b0010,
        0b0000,
        [0x00000000, 0x00000102, 0x00000000, 0x00000000]
    ),

    # Cycle 8
    # Pop Lane2 : consume 0x201
    (
        0b0000,
        0b0100,
        [0, 0, 0, 0]
    ),

    # Cycle 9
    # Idle - Lane1 preload 0x102
    (
        0b0000,
        0b0000,
        [0, 0, 0, 0]
    ),

    # Cycle 10
    # Pop Lane3 : consume 0x301
    (
        0b0000,
        0b1000,
        [0, 0, 0, 0]
    ),

    # Cycle 11
    # Pop Lane0 : consume second word 0x22
    (
        0b0000,
        0b0001,
        [0, 0, 0, 0]
    ),

    # Cycle 12
    # Idle
    (
        0b0000,
        0b0000,
        [0, 0, 0, 0]
    ),

    # Cycle 13
    # Pop Lane1 : consume 0x102
    (
        0b0000,
        0b0010,
        [0, 0, 0, 0]
    ),

    # Cycle 14
    # Final idle
    (
        0b0000,
        0b0000,
        [0, 0, 0, 0]
    ),
]


# Reference model state
fifo = [deque() for _ in range(NUM_LANES)]

# sync_fifo registered outputs
fifo_rdata = [0 for _ in range(NUM_LANES)]
fifo_rdata_vld = [0 for _ in range(NUM_LANES)]

# fifo_bank head buffer
head_data = [0 for _ in range(NUM_LANES)]
head_valid = [0 for _ in range(NUM_LANES)]
refill_pending = [0 for _ in range(NUM_LANES)]

golden_vectors = []


# Reference simulation
for cycle, (wren_mask, pop_mask, wdata) in enumerate(test_vectors):

    # State BEFORE positive clock edge
    fifo_empty = [
        len(fifo[lane]) == 0
        for lane in range(NUM_LANES)
    ]

    fifo_full = [
        len(fifo[lane]) == DEPTH
        for lane in range(NUM_LANES)
    ]

    # fifo_bank combinational read-ahead logic
    fifo_rden = [0 for _ in range(NUM_LANES)]

    for lane in range(NUM_LANES):

        pop = (pop_mask >> lane) & 0x1

        if not refill_pending[lane]:

            if (
                not head_valid[lane]
                and not fifo_empty[lane]
            ):
                fifo_rden[lane] = 1

            elif (
                head_valid[lane]
                and pop
                and not fifo_empty[lane]
            ):
                fifo_rden[lane] = 1


    # fifo_bank sequential block
    #
    # Important:
    # It sees OLD fifo_rdata / fifo_rdata_vld values,
    # exactly like nonblocking assignments in RTL.

    next_head_data = head_data.copy()
    next_head_valid = head_valid.copy()
    next_refill_pending = refill_pending.copy()

    for lane in range(NUM_LANES):

        pop = (pop_mask >> lane) & 0x1

        # Consumer pops current head
        if pop and head_valid[lane]:
            next_head_valid[lane] = 0

        # Track FIFO read request
        if fifo_rden[lane]:
            next_refill_pending[lane] = 1

        # FIFO returned previously requested word
        if fifo_rdata_vld[lane]:
            next_head_data[lane] = fifo_rdata[lane]
            next_head_valid[lane] = 1
            next_refill_pending[lane] = 0


    # sync_fifo sequential block

    next_fifo_rdata = fifo_rdata.copy()
    next_fifo_rdata_vld = [0 for _ in range(NUM_LANES)]

    for lane in range(NUM_LANES):

        wren = (wren_mask >> lane) & 0x1

        write_accept = (
            wren
            and not fifo_full[lane]
        )

        read_accept = (
            fifo_rden[lane]
            and not fifo_empty[lane]
        )


        # Read
        if read_accept:

            next_fifo_rdata[lane] = fifo[lane].popleft()
            next_fifo_rdata_vld[lane] = 1


        # Write
        if write_accept:

            fifo[lane].append(
                wdata[lane] & 0xFFFFFFFF
            )


    # Commit registers

    head_data = next_head_data
    head_valid = next_head_valid
    refill_pending = next_refill_pending

    fifo_rdata = next_fifo_rdata
    fifo_rdata_vld = next_fifo_rdata_vld


    # Output status AFTER clock edge

    empty_mask = 0
    full_mask = 0
    head_valid_mask = 0

    for lane in range(NUM_LANES):

        if len(fifo[lane]) == 0:
            empty_mask |= (1 << lane)

        if len(fifo[lane]) == DEPTH:
            full_mask |= (1 << lane)

        if head_valid[lane]:
            head_valid_mask |= (1 << lane)


    golden_vectors.append(
        (
            head_valid_mask,
            full_mask,
            empty_mask,
            head_data.copy()
        )
    )


    # Console display

    head_string = " ".join(
        f"L{lane}=0x{head_data[lane]:08X}"
        for lane in range(NUM_LANES)
    )

    print(
        f"Cycle {cycle:02d} | "
        f"WREN={wren_mask:04b} "
        f"POP={pop_mask:04b} | "
        f"HEAD_VLD={head_valid_mask:04b} | "
        f"{head_string} | "
        f"EMPTY={empty_mask:04b} "
        f"FULL={full_mask:04b}"
    )


# Write input file
#
# 136 bits total:
#
# [135:132] i_wren
# [131:128] i_pop
#
# [127:96]  lane3 wdata
# [95:64]   lane2 wdata
# [63:32]   lane1 wdata
# [31:0]    lane0 wdata

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

with INPUT_FILE.open("w") as f:

    for wren_mask, pop_mask, wdata in test_vectors:

        value = 0

        value |= (wren_mask & 0xF) << 132
        value |= (pop_mask & 0xF) << 128

        value |= (wdata[3] & 0xFFFFFFFF) << 96
        value |= (wdata[2] & 0xFFFFFFFF) << 64
        value |= (wdata[1] & 0xFFFFFFFF) << 32
        value |= (wdata[0] & 0xFFFFFFFF)

        # 136 bits = 34 hex digits
        f.write(f"{value:034X}\n")


# Write golden file
#
# 140 bits total:
#
# [139:136] o_head_valid
# [135:132] o_full
# [131:128] o_empty
#
# [127:96]  head lane3
# [95:64]   head lane2
# [63:32]   head lane1
# [31:0]    head lane0

with GOLDEN_FILE.open("w") as f:

    for (
        head_valid_mask,
        full_mask,
        empty_mask,
        golden_head
    ) in golden_vectors:

        value = 0

        value |= (head_valid_mask & 0xF) << 136
        value |= (full_mask & 0xF) << 132
        value |= (empty_mask & 0xF) << 128

        value |= (golden_head[3] & 0xFFFFFFFF) << 96
        value |= (golden_head[2] & 0xFFFFFFFF) << 64
        value |= (golden_head[1] & 0xFFFFFFFF) << 32
        value |= (golden_head[0] & 0xFFFFFFFF)

        # 140 bits = 35 hex digits
        f.write(f"{value:035X}\n")


print()
print("=============================================")
print("fifo_bank vectors generated successfully")
print("==============================================")
print(f"Input  : {INPUT_FILE}")
print(f"Golden : {GOLDEN_FILE}")
print(f"Cycles : {len(test_vectors)}")