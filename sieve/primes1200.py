import math

def is_prime(num):
    if num < 2:
        return False
    if num == 2:
        return True
    if num % 2 == 0:
        return False
    for i in range(3, int(math.isqrt(num)) + 1, 2):
        if num % i == 0:
            return False
    return True

def generate_relatively_prime_numbers(limit, modulus):
    num = 1
    count = 0
    while count < limit:
        if math.gcd(num, modulus) == 1:
            yield num
            count += 1
        num += 1

cols = 20
rows = 24
limit = cols * rows
modulus = 50

with open("primes1200.tex", "w") as f:
    f.write("\\begin{tikzpicture}[scale=0.8, every node/.style={font=\\fontsize{6.4pt}{8pt}\\selectfont}]\n")
    for idx, number in enumerate(generate_relatively_prime_numbers(limit, modulus), start=0):
        x = idx % cols
        y = -(idx // cols)
        if is_prime(number):
            f.write(f"\\node[draw,circle,minimum size=0.6cm,inner sep=0pt] at ({x},{y}) {{{number}}};\n")
        else:
            f.write(f"\\node[draw,circle,fill=black,text=white,minimum size=0.6cm,inner sep=0pt] at ({x},{y}) {{{number}}};\n")
    f.write("\\end{tikzpicture}\n")
