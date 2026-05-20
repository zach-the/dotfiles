import sys
import time

sys.stdout.write('\033[?1049h\033[H\033[2J')
sys.stdout.write('Hello in alternate screen!\n')
sys.stdout.flush()
time.sleep(2)
sys.stdout.write('\033[?1049l')
sys.stdout.flush()
