import os
import sys

def f(a, b):
    return {"a": a, "b": b}

print(f(1, 2), os.name, sys.argv)
