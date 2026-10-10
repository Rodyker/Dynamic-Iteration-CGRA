#!/usr/bin/env python3
# Written by Claude.
"""
Place-and-route search for the 4x4 array: given a kernel as a list of cells,
find a grid position and operand sources for every cell, or report that none
exists. The search is exhaustive, so "no placement" is a real answer for that
cell list (but not for other ways of writing the same computation).

A kernel is an ordered dict  name -> (OP, a, b)  in dependency order, where
each operand is one of

    ('in', j)         input j     (only readable by the row-0 cell of column j)
    ('const', value)  row constant X, hex Q3.13 (one value per row)
    ('node', name)    another cell's output

A unary cell (PASS) repeats its operand. Relays must be listed as PASS cells;
with_relays() generates the variants that add them.

Run this file to see the example: it re-derives the layout of configs/median3.csv.
"""

import itertools

N = 4


def node(name):
    return ('node', name)


def solve(nodes, output, limit=1):
    """Return up to `limit` solutions: (pos, src, row_bus, col_bus, row_const).

    Rules modelled (see top.sv): N/S/E/W neighbours with wrap-around, except
    that row 0's North is the input; a row bus per row and a column bus per
    column, each with one driver; one constant per row; the output cell must
    drive its column bus, since output[j] is column bus j.
    """
    names = list(nodes)
    sols = []
    pos, used, src = {}, {}, {}
    row_bus, col_bus, row_const = [None] * N, [None] * N, [None] * N

    def options(cell, operand):
        r, c = cell
        kind, val = operand
        if kind == 'in':
            return [('N', None)] if (r == 0 and c == val) else []
        if kind == 'const':
            return [('X', (row_const, r, val))] if row_const[r] in (None, val) else []
        pr, pc = pos[val]
        out = []
        if r > 0 and (pr, pc) == (r - 1, c): out.append(('N', None))
        if (pr, pc) == ((r + 1) % N, c): out.append(('S', None))
        if (pr, pc) == (r, (c + 1) % N): out.append(('E', None))
        if (pr, pc) == (r, (c - 1) % N): out.append(('W', None))
        if pr == r and pc != c and row_bus[r] in (None, pc): out.append(('R', (row_bus, r, pc)))
        if pc == c and pr != r and col_bus[c] in (None, pr): out.append(('C', (col_bus, c, pr)))
        return out

    def claim(effect):
        """Reserve a bus or constant; return what to undo, if anything changed."""
        if effect is None:
            return None
        arr, i, v = effect
        if arr[i] is None:
            arr[i] = v
            return (arr, i)
        return None

    def rec(k):
        if len(sols) >= limit:
            return
        if k == len(names):
            r, c = pos[output]
            if col_bus[c] in (None, r):
                cb = col_bus[:]
                cb[c] = r
                sols.append((dict(pos), dict(src), row_bus[:], cb, row_const[:]))
            return
        name = names[k]
        op, a, b = nodes[name]
        if a[0] == 'in':
            cells = [(0, a[1])]
        elif b[0] == 'in':
            cells = [(0, b[1])]
        else:
            cells = [(r, c) for r in range(N) for c in range(N)]
        for cell in cells:
            if cell in used:
                continue
            for sa, ea in options(cell, a):
                ua = claim(ea)
                for sb, eb in (options(cell, b) if b != a else [(sa, None)]):
                    ub = claim(eb)
                    pos[name], used[cell], src[name] = cell, name, (sa, sb)
                    rec(k + 1)
                    del pos[name], used[cell], src[name]
                    if ub: ub[0][ub[1]] = None
                if ua: ua[0][ua[1]] = None
                if len(sols) >= limit:
                    return

    rec(0)
    return sols


def with_relays(nodes, budget):
    """Yield (label, nodes) with up to `budget` relays added. Each relay copies
    one cell's output and takes over some of the places that output is used."""
    yield "", nodes
    if budget <= 0:
        return
    for p in list(nodes):
        uses = [(name, i) for name, (op, a, b) in nodes.items()
                for i, x in ((0, a), (1, b)) if x == node(p)]
        for k in range(1, len(uses) + 1):
            for sub in itertools.combinations(uses, k):
                relay, new = p + "~", {}
                while relay in nodes:
                    relay += "~"
                for name, (op, a, b) in nodes.items():
                    if (name, 0) in sub: a = node(relay)
                    if (name, 1) in sub: b = node(relay)
                    new[name] = (op, a, b)
                    if name == p:
                        new[relay] = ('PASS', node(p), node(p))
                label = f"relay({p} -> {', '.join(c for c, _ in sub)})"
                # The recursion yields `new` itself first, then `new` plus more relays.
                for deeper_label, deeper in with_relays(new, budget - 1):
                    yield (label + " " + deeper_label).strip(), deeper


def to_csv(nodes, solution, lcu_row):
    """Return (cell-name map as comment lines, config CSV body)."""
    pos, src, row_bus, col_bus, row_const = solution
    grid = [["PASS F"] * N for _ in range(N)]
    where = [[""] * N for _ in range(N)]
    for name, (op, a, b) in nodes.items():
        r, c = pos[name]
        sa, sb = src[name]
        grid[r][c] = f"{op} {sa}" if op == "PASS" else f"{op} {sa} {sb}"
        where[r][c] = name
    lines = [", ".join(f"{x:<9}" for x in row).rstrip() for row in grid]
    lines.append(lcu_row)
    lines.append(", ".join(str(x or 0) for x in row_bus))
    lines.append(", ".join(str(x or 0) for x in col_bus))
    lines.append(", ".join(f"{(x or 0):04X}" for x in row_const))
    names = "\n".join("#   " + "  ".join(f"{x:<6}" for x in row).rstrip() for row in where)
    return names, "\n".join(lines)


def median3_cells():
    """The cells of configs/median3.csv, relays included."""
    relay = lambda x: ('PASS', node(x), node(x))
    nd = {}
    nd['a'] = ('PASS', ('in', 0), ('in', 0))
    nd['m1'] = ('MAX', ('in', 1), node('a'))          # max(a, b)
    nd['s1'] = ('ADD', ('in', 2), node('a'))          # a + b
    nd['c'] = ('PASS', ('in', 3), ('in', 3))
    nd['m1r'] = relay('m1')
    nd['c1'] = relay('c')
    nd['s2'] = ('ADD', node('m1r'), node('c1'))       # m1 + c
    nd['lo'] = ('SUB', node('s1'), node('m1r'))       # min(a, b)
    nd['s2r'] = relay('s2')
    nd['c2'] = relay('c1')
    nd['m2'] = ('MAX', node('m1r'), node('c2'))       # max(m1, c)
    nd['lor'] = relay('lo')
    nd['s2rr'] = relay('s2r')
    nd['mid'] = ('SUB', node('s2rr'), node('m2'))     # min(m1, c)
    nd['out'] = ('MAX', node('lor'), node('mid'))
    return nd


if __name__ == "__main__":
    cells = median3_cells()
    found = solve(cells, 'out')
    if not found:
        raise SystemExit("no placement found")
    names, csv = to_csv(cells, found[0], "0, GT, 7FFF, 0, 0008")
    print(names)
    print(csv)
