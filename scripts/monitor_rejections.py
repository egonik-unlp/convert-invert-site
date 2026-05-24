import subprocess
import re
import sys
import time
from collections import Counter

# Patterns to look for in the logs
PATTERNS = {
    'Rejection': re_rejection := re.compile(r'reject|refused|denied', re.I),
    'Ban': re_ban := re.compile(r'ban|blacklisted', re.I),
    'Timeout': re_timeout := re.compile(r'timeout|timed out', re.I),
    'Disconnect': re_disconnect := re.compile(r'disconnect|closed|eof', re.I),
}

def monitor_logs():
    print("Starting Rejection Monitor...")
    print("Tailing 'api' logs for download rejection events...")
    print("-" * 50)

    counts = Counter()
    
    # Run docker compose logs as a subprocess
    process = subprocess.Popen(
        ['docker', 'compose', 'logs', '-f', 'api'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )

    try:
        last_print = time.time()
        for line in process.stdout:
            # Look for matches
            matched = False
            for label, pattern in PATTERNS.items():
                if pattern.search(line):
                    counts[label] += 1
                    matched = True
            
            # Print the line if it matched something
            if matched:
                print(f"\033[93m{line.strip()}\033[0m")

            # Periodically print a summary
            if time.time() - last_print > 5:
                print_summary(counts)
                last_print = time.time()

    except KeyboardInterrupt:
        print("\nStopping monitor...")
    finally:
        process.terminate()
        print_summary(counts, final=True)

def print_summary(counts, final=False):
    status = "FINAL SUMMARY" if final else "LIVE SUMMARY (Last 5s)"
    print(f"\n--- {status} ---")
    if not counts:
        print("No rejection events detected yet.")
    for label, count in counts.items():
        print(f"{label}: {count}")
    print("-" * 30)

if __name__ == "__main__":
    monitor_logs()
