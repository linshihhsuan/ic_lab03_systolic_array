#!/usr/bin/env python3
"""
Stage13.11 Rev.B
Golden-vector generator for systolic_top verification.

Responsibilities of this script:
  1. Generate signed 32-bit A/B matrices.
  2. Compute C = A x B with Python integer arithmetic.
  3. Export A/B/C in row-major .hex format.

Intentionally NOT implemented here:
  - S_opt selection
  - tiling
  - FIFO scheduling
  - input skew
  - output-drain ordering

Those remain DUT / SystemVerilog testbench responsibilities.
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path
from typing import Iterable

DATA_WIDTH = 32
ACC_WIDTH = 71

MAX_M = 256
MAX_K = 108
MAX_N = 64

DEFAULT_CASES = (
    ("case_small",     4,  5,  3, 0x1301),
    ("case_full32",   32, 32, 32, 0x1302),
    ("case_multitile",35, 37, 34, 0x1303),
)


def signed_limits(width: int) -> tuple[int, int]:
    return -(1 << (width - 1)), (1 << (width - 1)) - 1


def to_twos_complement(value: int, width: int) -> int:
    lo, hi = signed_limits(width)
    if not (lo <= value <= hi):
        raise OverflowError(
            f"value {value} does not fit in signed {width}-bit range [{lo}, {hi}]"
        )
    return value & ((1 << width) - 1)


def write_hex(path: Path, values: Iterable[int], width: int) -> None:
    digits = (width + 3) // 4
    mask = (1 << width) - 1

    with path.open("w", encoding="ascii", newline="\n") as f:
        for value in values:
            encoded = to_twos_complement(value, width)
            f.write(f"{encoded & mask:0{digits}X}\n")


def matmul(
    a: list[list[int]],
    b: list[list[int]],
    m_dim: int,
    k_dim: int,
    n_dim: int,
) -> list[list[int]]:
    c = [[0 for _ in range(n_dim)] for _ in range(m_dim)]

    for m in range(m_dim):
        for n in range(n_dim):
            acc = 0
            for k in range(k_dim):
                acc += a[m][k] * b[k][n]

            # Check against the RTL full-ACC interface width.
            to_twos_complement(acc, ACC_WIDTH)
            c[m][n] = acc

    return c


def flatten_row_major(matrix: list[list[int]]) -> list[int]:
    return [value for row in matrix for value in row]


def generate_matrix(
    rows: int,
    cols: int,
    rng: random.Random,
    value_min: int,
    value_max: int,
) -> list[list[int]]:
    return [
        [rng.randint(value_min, value_max) for _ in range(cols)]
        for _ in range(rows)
    ]


def validate_dimensions(m_dim: int, k_dim: int, n_dim: int) -> None:
    if not (1 <= m_dim <= MAX_M):
        raise ValueError(f"M must be 1..{MAX_M}, got {m_dim}")
    if not (1 <= k_dim <= MAX_K):
        raise ValueError(f"K must be 1..{MAX_K}, got {k_dim}")
    if not (1 <= n_dim <= MAX_N):
        raise ValueError(f"N must be 1..{MAX_N}, got {n_dim}")


def generate_case(
    outdir: Path,
    name: str,
    m_dim: int,
    k_dim: int,
    n_dim: int,
    seed: int,
    value_min: int,
    value_max: int,
) -> None:
    validate_dimensions(m_dim, k_dim, n_dim)

    data_lo, data_hi = signed_limits(DATA_WIDTH)
    if value_min < data_lo or value_max > data_hi:
        raise ValueError(
            f"input range [{value_min}, {value_max}] exceeds signed "
            f"{DATA_WIDTH}-bit range [{data_lo}, {data_hi}]"
        )
    if value_min > value_max:
        raise ValueError("value_min must be <= value_max")

    rng = random.Random(seed)

    a = generate_matrix(m_dim, k_dim, rng, value_min, value_max)
    b = generate_matrix(k_dim, n_dim, rng, value_min, value_max)
    c = matmul(a, b, m_dim, k_dim, n_dim)

    a_path = outdir / f"{name}_A.hex"
    b_path = outdir / f"{name}_B.hex"
    c_path = outdir / f"{name}_golden.hex"
    info_path = outdir / f"{name}_info.txt"

    write_hex(a_path, flatten_row_major(a), DATA_WIDTH)
    write_hex(b_path, flatten_row_major(b), DATA_WIDTH)
    write_hex(c_path, flatten_row_major(c), ACC_WIDTH)

    info_path.write_text(
        "\n".join(
            (
                f"name={name}",
                f"M={m_dim}",
                f"K={k_dim}",
                f"N={n_dim}",
                f"seed={seed}",
                f"DATA_WIDTH={DATA_WIDTH}",
                f"ACC_WIDTH={ACC_WIDTH}",
                "layout_A=row-major, index=m*K+k",
                "layout_B=row-major, index=k*N+n",
                "layout_C=row-major, index=m*N+n",
                f"A_words={m_dim * k_dim}",
                f"B_words={k_dim * n_dim}",
                f"C_words={m_dim * n_dim}",
                "",
            )
        ),
        encoding="utf-8",
    )

    print(
        f"[GEN] {name}: M={m_dim} K={k_dim} N={n_dim} seed={seed} "
        f"-> {a_path.name}, {b_path.name}, {c_path.name}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate Stage13.11 Rev.B systolic-array golden vectors."
    )

    parser.add_argument(
        "--outdir",
        type=Path,
        default=Path("vectors"),
        help="output directory (default: vectors)",
    )

    parser.add_argument(
        "--m",
        type=int,
        help="custom-case M dimension",
    )
    parser.add_argument(
        "--k",
        type=int,
        help="custom-case K dimension",
    )
    parser.add_argument(
        "--n",
        type=int,
        help="custom-case N dimension",
    )
    parser.add_argument(
        "--name",
        default="case_custom",
        help="custom-case file prefix (default: case_custom)",
    )
    parser.add_argument(
        "--seed",
        type=lambda x: int(x, 0),
        default=0x130B,
        help="custom-case RNG seed; decimal or 0x... (default: 0x130B)",
    )
    parser.add_argument(
        "--value-min",
        type=int,
        default=-8,
        help="minimum generated matrix value (default: -8)",
    )
    parser.add_argument(
        "--value-max",
        type=int,
        default=8,
        help="maximum generated matrix value (default: 8)",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)

    custom_dims = (args.m, args.k, args.n)
    any_custom = any(v is not None for v in custom_dims)
    all_custom = all(v is not None for v in custom_dims)

    if any_custom and not all_custom:
        raise SystemExit(
            "For a custom case, --m, --k and --n must all be provided."
        )

    if all_custom:
        generate_case(
            outdir=args.outdir,
            name=args.name,
            m_dim=args.m,
            k_dim=args.k,
            n_dim=args.n,
            seed=args.seed,
            value_min=args.value_min,
            value_max=args.value_max,
        )
    else:
        for name, m_dim, k_dim, n_dim, seed in DEFAULT_CASES:
            generate_case(
                outdir=args.outdir,
                name=name,
                m_dim=m_dim,
                k_dim=k_dim,
                n_dim=n_dim,
                seed=seed,
                value_min=args.value_min,
                value_max=args.value_max,
            )


if __name__ == "__main__":
    main()
