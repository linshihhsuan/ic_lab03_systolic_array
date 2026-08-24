from collections import deque
from pathlib import Path

# Configuration
DATA_WIDTH = 32
DEPTH = 8
COUNT_WIDTH = 4  # $clog2(DEPTH + 1) when DEPTH = 8

OUTPUT_DIR = Path(__file__).parent / "vectors"

INPUT_FILE = OUTPUT_DIR / "sync_fifo_input.hex"
GOLDEN_FILE = OUTPUT_DIR / "sync_fifo_golden.hex"

# Test sequence
#
# Each entry:
#   (wren, rden, data)
#
# Goal:
#   1. prove write works
#   2. prove read works
#   3. prove FIFO ordering
#   4. prove simultaneous read/write
#   5. prove read while empty is rejected
test_vectors = [
    # wren rden input_data
    (1, 0, 0x00000011),   # write 0x11
    (1, 0, 0x00000022),   # write 0x22
    (1, 0, 0x00000033),   # write 0x33
    (0, 1, 0x00000000),   # read -> 0x11
    (1, 1, 0x00000044),   # read 0x22 + write 0x44
    (0, 1, 0x00000000),   # read -> 0x33
    (0, 1, 0x00000000),   # read -> 0x44
    (0, 1, 0x00000000),   # FIFO empty -> read rejected
    (1, 0, 0x000000AA),   # write 0xAA
    (0, 1, 0x00000000),   # read -> 0xAA
]


# Reference FIFO model
fifo = deque()
golden_vectors = []
last_output_data = 0

for cycle, (wren, rden, input_data) in enumerate(test_vectors):

    # Status BEFORE clock edge
    full_before = (len(fifo) == DEPTH)
    empty_before = (len(fifo) == 0)

    write_accept = bool(wren and not full_before)
    read_accept = bool(rden and not empty_before)

    # RTL performs read and write based on pre-edge status.
    #
    # For simultaneous read/write:
    #   read old head
    #   append new write data
    #   count unchanged
    if read_accept:
        last_output_data = fifo.popleft()
        data_vld = 1
    else:
        data_vld = 0

    if write_accept:
        fifo.append(input_data & 0xFFFFFFFF)

    # Status AFTER clock edge
    count = len(fifo)
    empty = int(count == 0)
    full = int(count == DEPTH)

    golden_vectors.append(
        (
            data_vld,
            last_output_data,
            count,
            empty,
            full,
        )
    )

    print(
        f"Cycle {cycle:02d}: "
        f"WR = {wren}, RD = {rden}, "
        f"IN = 0x{input_data:08X} | "
        f"VLD = {data_vld}, "
        f"OUT = 0x{last_output_data:08X}, "
        f"COUNT = {count}, "
        f"EMPTY = {empty}, FULL={full}"
    )

# Encode input vectors
# 34 bits:
# [33]    wren
# [32]    rden
# [31:0]  input data
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

with INPUT_FILE.open("w") as f:

    for wren, rden, data in test_vectors:

        value = (
            ((wren & 0x1) << 33)
            | ((rden & 0x1) << 32)
            | (data & 0xFFFFFFFF)
        )

        # 34 bits -> 9 hex digits
        f.write(f"{value:09X}\n")

# Encode golden vectors
#
# 39 bits:
#
# [38]     o_data_vld
# [37:6]   o_data
# [5:2]    o_count
# [1]      o_empty
# [0]      o_full

with GOLDEN_FILE.open("w") as f:

    for data_vld, data, count, empty, full in golden_vectors:

        value = (
            ((data_vld & 0x1) << 38)
            | ((data & 0xFFFFFFFF) << 6)
            | ((count & 0xF) << 2)
            | ((empty & 0x1) << 1)
            | (full & 0x1)
        )

        # 39 bits -> 10 hex digits
        f.write(f"{value:010X}\n")

print()
print("==============================================")
print("sync_fifo vectors generated successfully")
print("==============================================")
print(f"Input: {INPUT_FILE}")
print(f"Golden: {GOLDEN_FILE}")
print(f"Cycles: {len(test_vectors)}")