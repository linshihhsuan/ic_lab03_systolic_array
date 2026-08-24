# File Name:
#   generate_tile_controller_vectors.py
#
# Description:
#   Generate input and golden vectors for tile_controller.sv
#
# Output:
#   tile_controller_input.hex
#   tile_controller_golden.hex
#
# Verification Rule:
#   Python generates all expected/golden results.
#   SystemVerilog testbench only applies stimulus and compares.

INPUT_FILE = "tile_controller_input.hex"
GOLDEN_FILE = "tile_controller_golden.hex"

# tile_controller Reference Model


class TileControllerModel:
    ST_IDLE = 0
    ST_PREP_TILE = 1
    ST_CLEAR_ACC = 2
    ST_START_COMPUTE = 3
    ST_WAIT_COMPUTE = 4
    ST_START_DRAIN = 5
    ST_WAIT_DRAIN = 6
    ST_DONE = 7

    def __init__(self):

        self.state = self.ST_IDLE

        # Configuration registers
        self.m_size = 0
        self.k_size = 0
        self.n_size = 0
        self.s_active = 0

        # Tile position
        self.m_base = 0
        self.n_base = 0

        # Current active tile size
        self.active_rows = 0
        self.active_cols = 0

    # Last Tile Detection
    def last_m_tile(self):

        if self.s_active == 0:
            return True

        return (self.m_size - self.m_base) <= self.s_active

    def last_n_tile(self):

        if self.s_active == 0:
            return True

        return (self.n_size - self.n_base) <= self.s_active

    # One Clock Cycle
    def step(
        self, rst_n, start, m_size, k_size, n_size, s_active, compute_done, drain_done
    ):

        # Save old state because RTL nonblocking assignment behavior
        old_state = self.state

        old_last_m_tile = self.last_m_tile()
        old_last_n_tile = self.last_n_tile()

        # FSM Next-State Logic
        next_state = old_state

        if old_state == self.ST_IDLE:
            if start:
                next_state = self.ST_PREP_TILE

        elif old_state == self.ST_PREP_TILE:
            next_state = self.ST_CLEAR_ACC

        elif old_state == self.ST_CLEAR_ACC:
            next_state = self.ST_START_COMPUTE

        elif old_state == self.ST_START_COMPUTE:
            next_state = self.ST_WAIT_COMPUTE

        elif old_state == self.ST_WAIT_COMPUTE:
            if compute_done:
                next_state = self.ST_START_DRAIN

        elif old_state == self.ST_START_DRAIN:
            next_state = self.ST_WAIT_DRAIN

        elif old_state == self.ST_WAIT_DRAIN:
            if drain_done:
                if old_last_m_tile and old_last_n_tile:
                    next_state = self.ST_DONE

                else:
                    next_state = self.ST_PREP_TILE

        elif old_state == self.ST_DONE:
            next_state = self.ST_IDLE

        else:
            next_state = self.ST_IDLE

        # Sequential Logic
        if not rst_n:
            self.state = self.ST_IDLE

            self.m_size = 0
            self.k_size = 0
            self.n_size = 0
            self.s_active = 0

            self.m_base = 0
            self.n_base = 0

            self.active_rows = 0
            self.active_cols = 0

        else:
            # Capture GEMM configuration

            if old_state == self.ST_IDLE and start:
                self.m_size = m_size
                self.k_size = k_size
                self.n_size = n_size
                self.s_active = s_active

                self.m_base = 0
                self.n_base = 0

            # Prepare current tile
            #
            # active_rows = min(S, M - m_base)
            # active_cols = min(S, N - n_base)

            if old_state == self.ST_PREP_TILE:
                remaining_rows = self.m_size - self.m_base

                remaining_cols = self.n_size - self.n_base

                self.active_rows = min(self.s_active, remaining_rows)

                self.active_cols = min(self.s_active, remaining_cols)

            # Advance tile
            #
            # N dimension = inner loop
            # M dimension = outer loop

            if (
                old_state == self.ST_WAIT_DRAIN
                and drain_done
                and not (old_last_m_tile and old_last_n_tile)
            ):
                if old_last_n_tile:
                    self.m_base += self.s_active
                    self.n_base = 0

                else:
                    self.n_base += self.s_active

            # Update FSM state
            self.state = next_state

        # Combinational Outputs
        acc_clear = 0
        compute_start = 0
        drain_start = 0

        busy = 0
        done = 0

        if self.state == self.ST_IDLE:
            busy = 0

        elif self.state == self.ST_CLEAR_ACC:
            busy = 1
            acc_clear = 1

        elif self.state == self.ST_START_COMPUTE:
            busy = 1
            compute_start = 1

        elif self.state == self.ST_START_DRAIN:
            busy = 1
            drain_start = 1

        elif self.state == self.ST_DONE:
            busy = 0
            done = 1

        else:
            busy = 1

        return {
            "acc_clear": acc_clear,
            "compute_start": compute_start,
            "drain_start": drain_start,
            "m_base": self.m_base,
            "n_base": self.n_base,
            "active_rows": self.active_rows,
            "active_cols": self.active_cols,
            "k_size": self.k_size,
            "busy": busy,
            "done": done,
        }


# Vector Storage
input_vectors = []
golden_vectors = []

model = TileControllerModel()


# Add One Test Cycle
def add_cycle(rst_n, start, m_size, k_size, n_size, s_active, compute_done, drain_done):

    # Input Vector
    input_vector = [
        rst_n,
        start,
        m_size,
        k_size,
        n_size,
        s_active,
        compute_done,
        drain_done,
    ]

    # Python Golden Model
    result = model.step(
        rst_n, start, m_size, k_size, n_size, s_active, compute_done, drain_done
    )

    # Golden Vector
    golden_vector = [
        result["acc_clear"],
        result["compute_start"],
        result["drain_start"],
        result["m_base"],
        result["n_base"],
        result["active_rows"],
        result["active_cols"],
        result["k_size"],
        result["busy"],
        result["done"],
    ]

    input_vectors.append(input_vector)
    golden_vectors.append(golden_vector)


# Testcase Generator
def run_testcase(name, m_size, k_size, n_size, s_active, inject_busy_start=False):

    print(f"{name}: M={m_size}, K={k_size}, N={n_size}, S={s_active}")

    # Reset
    add_cycle(
        rst_n=0,
        start=0,
        m_size=0,
        k_size=0,
        n_size=0,
        s_active=0,
        compute_done=0,
        drain_done=0,
    )

    add_cycle(
        rst_n=0,
        start=0,
        m_size=0,
        k_size=0,
        n_size=0,
        s_active=0,
        compute_done=0,
        drain_done=0,
    )

    # Release Reset

    add_cycle(
        rst_n=1,
        start=0,
        m_size=0,
        k_size=0,
        n_size=0,
        s_active=0,
        compute_done=0,
        drain_done=0,
    )

    # Start
    add_cycle(
        rst_n=1,
        start=1,
        m_size=m_size,
        k_size=k_size,
        n_size=n_size,
        s_active=s_active,
        compute_done=0,
        drain_done=0,
    )

    compute_wait_count = 0
    drain_wait_count = 0

    busy_start_injected = False

    # Execute Until DONE
    while True:
        start = 0

        current_m = m_size
        current_k = k_size
        current_n = n_size
        current_s = s_active

        compute_done = 0
        drain_done = 0

        # WAIT_COMPUTE
        #
        # Hold for 2 cycles, then assert compute_done
        if model.state == model.ST_WAIT_COMPUTE:
            compute_wait_count += 1

            if compute_wait_count >= 3:
                compute_done = 1
                compute_wait_count = 0

            # Busy START test
            #
            # Send incorrect new configuration while DUT busy.
            # DUT should ignore it.
            if inject_busy_start and not busy_start_injected:
                start = 1

                current_m = 3
                current_k = 5
                current_n = 7
                current_s = 2

                busy_start_injected = True

        else:
            compute_wait_count = 0

        # WAIT_DRAIN
        #
        # Hold for 2 cycles, then assert drain_done
        if model.state == model.ST_WAIT_DRAIN:
            drain_wait_count += 1

            if drain_wait_count >= 3:
                drain_done = 1
                drain_wait_count = 0

        else:
            drain_wait_count = 0

        # Add this cycle
        add_cycle(
            rst_n=1,
            start=start,
            m_size=current_m,
            k_size=current_k,
            n_size=current_n,
            s_active=current_s,
            compute_done=compute_done,
            drain_done=drain_done,
        )

        # Stop when ST_DONE is reached
        if model.state == model.ST_DONE:
            break

    # DONE -> IDLE
    add_cycle(
        rst_n=1,
        start=0,
        m_size=m_size,
        k_size=k_size,
        n_size=n_size,
        s_active=s_active,
        compute_done=0,
        drain_done=0,
    )

    # One extra IDLE cycle
    add_cycle(
        rst_n=1,
        start=0,
        m_size=0,
        k_size=0,
        n_size=0,
        s_active=0,
        compute_done=0,
        drain_done=0,
    )


# Data Patterns
# ------------------------------------------------
# T01
# Single full tile
#
# 32 x 32
# ------------------------------------------------
run_testcase(name="T01_SINGLE_FULL_TILE", m_size=32, k_size=108, n_size=32, s_active=32)

# ------------------------------------------------
# T02
# Four full tiles
#
# Tile:
# (0,0)
# (0,32)
# (32,0)
# (32,32)
#
# Also test i_start while busy.
# ------------------------------------------------

run_testcase(
    name="T02_FOUR_FULL_TILES",
    m_size=64,
    k_size=108,
    n_size=64,
    s_active=32,
    inject_busy_start=True,
)


# ------------------------------------------------
# T03
# Edge tile
#
# (0,0)   = 32 x 32
# (0,32)  = 32 x 18
# (32,0)  = 13 x 32
# (32,32) = 13 x 18
# ------------------------------------------------

run_testcase(name="T03_EDGE_TILE", m_size=45, k_size=108, n_size=50, s_active=32)


# ------------------------------------------------
# T04
# Matrix smaller than S
#
# active_rows = 10
# active_cols = 9
# ------------------------------------------------

run_testcase(name="T04_SMALL_MATRIX", m_size=10, k_size=7, n_size=9, s_active=32)


# ------------------------------------------------
# T05
# S_active = 16
#
# Verify controller is not hard-coded to 32
# ------------------------------------------------

run_testcase(name="T05_S_ACTIVE_16", m_size=33, k_size=17, n_size=20, s_active=16)


# Write Input HEX File

with open(INPUT_FILE, "w") as file:
    for vector in input_vectors:
        file.write(" ".join(f"{value:X}" for value in vector) + "\n")


# Write Golden HEX File

with open(GOLDEN_FILE, "w") as file:
    for vector in golden_vectors:
        file.write(" ".join(f"{value:X}" for value in vector) + "\n")


# Summary

print()
print("=============================================")
print(" Tile Controller Vector Generation Done ")
print("=============================================")

print(f"Input File  : {INPUT_FILE}")

print(f"Golden File : {GOLDEN_FILE}")

print(f"Total Cycle : {len(input_vectors)}")

print("=============================================")
