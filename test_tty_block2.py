import sys
import os
import tty
import termios
import selectors

if sys.stdin.isatty():
    old_termios = termios.tcgetattr(sys.stdin.fileno())
    tty.setcbreak(sys.stdin.fileno())

sel = selectors.DefaultSelector()
sel.register(sys.stdin, selectors.EVENT_READ, data='stdin')

print("Press a key (q to quit)")
try:
    while True:
        events = sel.select(timeout=0.1)
        for key, _ in events:
            if key.data == 'stdin':
                c = os.read(sys.stdin.fileno(), 1).decode('utf-8', 'ignore')
                print(f"Got {repr(c)}")
                if c == 'q':
                    sys.exit(0)
finally:
    if sys.stdin.isatty():
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_termios)
