#!/usr/bin/env python3

from __future__ import annotations

import argparse
import random
from pathlib import Path

# 全域參數
# 必須與目前 systolic_top.sv / size_selector.sv 規格一致
DATA_WIDTH = 32
ACC_WIDTH = 71
S_MAX = 32
MAX_M = 256
MAX_K = 108
MAX_N = 64

# input.hex 的 magic number
# 0x53595341 = ASCII "SYSA"
MAGIC = 0x53595341


# Function: lim
#
# 功能：
# 計算 signed W-bit 整數可表示的範圍
#
# 例如：
# signed 8-bit
#   min = -128
#   max = +127
def lim(w):
    return (
        -(1 << (w - 1)),
        (1 << (w - 1)) - 1,
    )


# Function: enc
#
# 功能：
# 將 Python signed integer 轉成指定 bit-width 的
# two's complement unsigned representation
#
# 例如：
#   enc(-1, 8) = 0xFF
#
# 此函式同時會檢查數值是否超出 bit-width 可表示範圍
def enc(v, w):

    lo, hi = lim(w)

    if not lo <= v <= hi:
        raise OverflowError(
            f"{v} does not fit signed {w}-bit"
        )

    return v & ((1 << w) - 1)


# Function: wr
#
# 功能：
# 將一筆資料以 hexadecimal 形式寫入 .hex
#
# 會自動根據 bit-width 決定 hex digit 數量
#
# 例如：
#   32-bit -> 8 hex digits
#   71-bit -> 18 hex digits
def wr(f, v, w):

    hex_digits = (w + 3) // 4

    f.write(
        f"{enc(v, w):0{hex_digits}X}\n"
    )


# Function: choose_s
#
# 功能：
# 根據目前 RTL size_selector.sv 的 cost function
# 搜尋最佳 systolic array active size S
#
# 搜尋範圍：
#   S = 1 ~ S_MAX
#
# Cost：
#
#   Tm = ceil(M / S)
#   Tn = ceil(N / S)
#
#   cost =
#       Tm * Tn * (K + 4)
#     + Tn * M
#     + Tm * N
#     + M * N
#
# 注意：
# RTL 使用 strict <
# 因此若 cost 相同，會保留較小的 S
def choose_s(m, k, n):

    best_s = 1
    best = None

    for s in range(1, S_MAX + 1):

        # ceil(M / S)
        tm = (m + s - 1) // s

        # ceil(N / S)
        tn = (n + s - 1) // s

        cost = (
            tm * tn * (k + 4)
            + tn * m
            + tm * n
            + m * n
        )

        # 使用 strict <
        # cost 相同時不更新，因此保留較小 S
        if best is None or cost < best:

            best = cost
            best_s = s

    return best_s, best


# Function: mk
#
# 功能：
# 依指定 pattern 產生矩陣
#
# 支援：
#   random
#   ones
#   checker
#   ramp
#
# Parameters：
#   rows, cols : matrix shape
#   pattern    : 資料 pattern
#   rng        : random generator
#   vmin/vmax  : 數值範圍
#   salt       : 用來讓 A/B checker 或 ramp pattern 不完全相同
def mk(
    rows,
    cols,
    pattern,
    rng,
    vmin,
    vmax,
    salt,
):

    # Random pattern
    if pattern == "random":

        return [
            [
                rng.randint(vmin, vmax)
                for _ in range(cols)
            ]
            for _ in range(rows)
        ]


    # All ones
    if pattern == "ones":

        return [
            [
                1
                for _ in range(cols)
            ]
            for _ in range(rows)
        ]


    # Checkerboard +1 / -1
    if pattern == "checker":

        return [
            [
                1
                if ((r + c + salt) & 1) == 0
                else -1
                for c in range(cols)
            ]
            for r in range(rows)
        ]


    # Ramp pattern
    span = vmax - vmin + 1

    return [
        [
            vmin
            + (
                (r * cols + c + salt)
                % span
            )
            for c in range(cols)
        ]
        for r in range(rows)
    ]


# Function: mm
#
# 功能：
# Python Golden Model
#
# 計算：
#
#   C = A × B
#
# A shape：
#   M × K
#
# B shape：
#   K × N
#
# C shape：
#   M × N
#
# 這裡是整個 verification flow 中唯一真正
# 計算 GEMM golden 的地方
#
# SystemVerilog Testbench 不自行計算 C
def mm(a, b):

    m = len(a)
    k = len(a[0])
    n = len(b[0])

    # 建立 M × N 的 zero matrix
    c = [
        [0] * n
        for _ in range(m)
    ]


    # Matrix Multiplication
    #
    # C[i][j]
    # =
    # Σ A[i][kk] × B[kk][j]
    for i in range(m):

        for j in range(n):

            x = sum(
                a[i][kk] * b[kk][j]
                for kk in range(k)
            )


            # 檢查結果是否可放入 ACC_WIDTH
            enc(x, ACC_WIDTH)

            c[i][j] = x

    return c


# Function: flat
#
# 功能：
# 將 2D matrix 轉成 row-major 1D list
#
# 例如：
#
# [[1, 2],
#  [3, 4]]
#
# ->
#
# [1, 2, 3, 4]
def flat(x):

    return [
        v
        for row in x
        for v in row
    ]


# Function: drain_order
#
# 功能：
# 將完整 C matrix 重新排列成 DUT 真正的輸出順序
#
# DUT output ordering：
#
# M tile
#   -> N tile
#      -> local row
#         -> local column
#
# Tile traversal：
#
# M dimension = outer loop
# N dimension = inner loop
#
# Tile 內部：
#
# row-major
#
# 這個排列方式要與
# tile_controller.sv + result_drain.sv 完全一致
def drain_order(c, m, n, s):

    out = []


    # M tile outer loop

    for mb in range(0, m, s):

        # Edge tile 的有效 row 數
        ar = min(
            s,
            m - mb,
        )


        # N tile inner loop
        for nb in range(0, n, s):

            # Edge tile 的有效 column 數
            ac = min(
                s,
                n - nb,
            )


            # Tile 內使用 row-major order
            for r in range(ar):

                for col in range(ac):

                    out.append(
                        c[
                            mb + r
                        ][
                            nb + col
                        ]
                    )

    return out


# Main
def main():

    # Command-line arguments
    ap = argparse.ArgumentParser()


    # Matrix dimensions
    ap.add_argument(
        "--m",
        type=int,
        default=4,
    )

    ap.add_argument(
        "--k",
        type=int,
        default=5,
    )

    ap.add_argument(
        "--n",
        type=int,
        default=3,
    )


    # Random seed
    # 支援：
    #   4883
    #   0x1313
    ap.add_argument(
        "--seed",
        type=lambda x: int(x, 0),
        default=0x1313,
    )


    # Data pattern
    ap.add_argument(
        "--pattern",
        choices=[
            "random",
            "ones",
            "checker",
            "ramp",
        ],
        default="random",
    )


    # Input data range
    ap.add_argument(
        "--value-min",
        type=int,
        default=-8,
    )

    ap.add_argument(
        "--value-max",
        type=int,
        default=8,
    )


    # Output directory
    ap.add_argument(
        "--outdir",
        type=Path,
        default=Path("vectors"),
    )


    # Parse arguments
    args = ap.parse_args()

    m = args.m
    k = args.k
    n = args.n


    # 檢查 Matrix Dimension 是否符合 RTL 規格
    if not (
        1 <= m <= MAX_M
        and 1 <= k <= MAX_K
        and 1 <= n <= MAX_N
    ):

        raise SystemExit(
            "dimensions out of range"
        )


    # 建立 deterministic random generator
    #
    # 相同 seed 可以產生完全相同的 testcase
    rng = random.Random(
        args.seed
    )


    # 產生 A Matrix
    #
    # Shape：
    #   M × K
    A = mk(
        m,
        k,
        args.pattern,
        rng,
        args.value_min,
        args.value_max,
        0,
    )


    # 產生 B Matrix
    #
    # Shape：
    #   K × N
    #
    # salt = 17
    # 用來讓 deterministic pattern 與 A 有差異
    B = mk(
        k,
        n,
        args.pattern,
        rng,
        args.value_min,
        args.value_max,
        17,
    )


    # 計算 RTL 對應的最佳 S
    s, cost = choose_s(
        m,
        k,
        n,
    )


    # Python Golden Model
    #
    # C = A × B
    C = mm(
        A,
        B,
    )


    # 將 A/B 轉為 row-major 1D vector
    Af = flat(A)
    Bf = flat(B)


    # 將 C 依 DUT output order 排列
    G = drain_order(
        C,
        m,
        n,
        s,
    )


    # 建立 output directory
    args.outdir.mkdir(
        parents=True,
        exist_ok=True,
    )


    # 產生 input.hex
    #
    # File format：
    #
    # word 0 : MAGIC
    # word 1 : M
    # word 2 : K
    # word 3 : N
    # word 4 : S_opt
    # word 5 : len(A)
    # word 6 : len(B)
    #
    # 接著：
    #
    # A row-major
    # B row-major
    input_path = (
        args.outdir
        / "input.hex"
    )

    with input_path.open(
        "w",
        encoding="ascii",
    ) as f:

        # Header
        for x in [
            MAGIC,
            m,
            k,
            n,
            s,
            len(Af),
            len(Bf),
        ]:

            wr(
                f,
                x,
                DATA_WIDTH,
            )


        # A / B Matrix
        for x in Af + Bf:

            wr(
                f,
                x,
                DATA_WIDTH,
            )


    # 產生 golden.hex
    #
    # 每一筆為 signed ACC_WIDTH = 71-bit
    #
    # golden ordering：
    #
    # M-tile
    #   -> N-tile
    #      -> local-row
    #         -> local-col
    golden_path = (
        args.outdir
        / "golden.hex"
    )


    with golden_path.open(
        "w",
        encoding="ascii",
    ) as f:

        for x in G:

            wr(
                f,
                x,
                ACC_WIDTH,
            )


    # 顯示 testcase 資訊
    print(
        f"[GEN] M={m} "
        f"K={k} "
        f"N={n} "
        f"S_opt={s} "
        f"cost={cost}"
    )

    print(
        f"[GEN] "
        f"{input_path} "
        f"words={7 + len(Af) + len(Bf)}"
    )

    print(
        f"[GEN] "
        f"{golden_path} "
        f"words={len(G)}"
    )

    print(
        "[GEN] golden order: "
        "M-tile -> "
        "N-tile -> "
        "local-row -> "
        "local-col"
    )


# Python Entry Point
if __name__ == "__main__":
    main()