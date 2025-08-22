# Script 1: arith_prog_squares_sumvals.py

def d(n):
    return n if n % 2 == 1 else n // 2

rmax = 19
cwidth = 2 * rmax - 1

with open("sumvals.txt", "w") as f:
    for row in range(1, rmax):
        maxc = cwidth - (row - 1)
        minc = maxc - cwidth if row % 2 == 1 else maxc - cwidth + 1
        for col in range(minc, maxc):
            sumval = sum(d(col + i) for i in range(row))
            f.write(f"{col} {row} {sumval}\n")
