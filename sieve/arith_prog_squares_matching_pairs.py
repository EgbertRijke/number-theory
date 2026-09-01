# Script 2: arith_prog_squares_matching_pairs.py

def d(n):
    return n if n % 2 == 1 else n // 2

rmax = 19
cwidth = 37

# Precompute sumvals
sumvals = dict()
for row in range(1, rmax):
    maxc = cwidth - (row - 1)
    for col in range(1, maxc):
        val = sum(d(col + i) for i in range(row))
        sumvals[(col, row)] = val

with open("matching_pairs.txt", "w") as f:
    for (colone, rowone), Sone in sumvals.items():
        for (coltwo, rowtwo), Stwo in sumvals.items():
            if colone <= coltwo:  # Avoid duplicates and degenerate cases
                continue
            if rowtwo != colone - coltwo:
                continue
            if Sone == Stwo:
                f.write(f"{colone} {rowone} {coltwo} {rowtwo}\n")
