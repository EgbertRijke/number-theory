# save as make_pi_data.py
import numpy as np
from sympy import primepi

with open('pi-data.dat','w') as fout:
    for x in range(0, 10001, 1):
        fout.write(f"{x} {primepi(x)}\n")

