#!/usr/bin/env python3
import os
import sys
import argparse
import subprocess
from datetime import datetime

# ANSI Colors for premium styling
VIOLET = "\033[38;5;99m"
BOLD_VIOLET = "\033[1;38;5;99m"
CYAN = "\033[96m"
BOLD_CYAN = "\033[1;96m"
GREEN = "\033[92m"
BOLD_GREEN = "\033[1;92m"
YELLOW = "\033[93m"
GREY = "\033[90m"
BOLD = "\033[1m"
RESET = "\033[0m"

def get_human_size(num_bytes):
    for unit in ['B', 'KB', 'MB', 'GB']:
        if num_bytes < 1024.0:
            return f"{num_bytes:.2f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.2f} TB"

def get_container_files():
    """Queries the running Docker container for the file list in /downloads"""
    try:
        # Run find in the api container
        cmd = [
            "docker", "compose", "exec", "api", 
            "find", "/downloads", "-maxdepth", "1", "-type", "f", "-printf", "%P\\t%s\\t%T@\\n"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        files = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) >= 3:
                name = parts[0]
                if name.startswith('.'):
                    continue
                try:
                    size = int(parts[1])
                    modified = float(parts[2])
                except ValueError:
                    continue
                files.append({
                    'name': name,
                    'size': size,
                    'modified': modified,
                    'location': 'container'
                })
        return files
    except Exception:
        # Failed to query container (either container is not running or command failed)
        return None

def get_local_files():
    """Queries the local ./downloads directory as a fallback"""
    local_dir = "./downloads"
    if not os.path.exists(local_dir) or not os.path.isdir(local_dir):
        return []
    
    files = []
    try:
        for entry in os.scandir(local_dir):
            if entry.is_file() and not entry.name.startswith('.'):
                stat = entry.stat()
                files.append({
                    'name': entry.name,
                    'size': stat.st_size,
                    'modified': stat.st_mtime,
                    'location': 'local'
                })
    except Exception:
        pass
    return files

def main():
    parser = argparse.ArgumentParser(
        description="List downloaded music files beautifully.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--sort", choices=["date", "size", "name"], default="date",
        help="Sort field (default: date)\n  date: newest first\n  size: largest first\n  name: alphabetical"
    )
    parser.add_argument(
        "--filter", choices=["all", "mp3", "flac"], default="all",
        help="Filter by file type (default: all)"
    )
    parser.add_argument(
        "--search", type=str, default=None,
        help="Search query to filter files by name"
    )
    parser.add_argument(
        "--limit", type=int, default=None,
        help="Limit the number of files displayed"
    )
    args = parser.parse_args()

    # 1. Fetch file list
    files = get_container_files()
    source_desc = f"{BOLD_CYAN}API Container (/downloads){RESET}"
    
    if files is None:
        # Container query failed, fallback to local directory
        files = get_local_files()
        source_desc = f"{YELLOW}Local Host Host-Sync Folder (./downloads){RESET}"
        if not files:
            print(f"\n{YELLOW}⚠️  Note: Docker API container is offline, and local host directory './downloads' is empty/missing.{RESET}")
            print(f"Run {BOLD}make up{RESET} to start the services, or run {BOLD}make copy-downloads{RESET} to sync them locally.\n")
            return

    # 2. Filter files
    if args.filter != "all":
        target_ext = f".{args.filter}"
        files = [f for f in files if f['name'].lower().endswith(target_ext)]

    if args.search:
        query = args.search.lower()
        files = [f for f in files if query in f['name'].lower()]

    # 3. Stats calculation before sorting & limiting
    total_count = len(files)
    total_size = sum(f['size'] for f in files)
    mp3_count = sum(1 for f in files if f['name'].lower().endswith('.mp3'))
    flac_count = sum(1 for f in files if f['name'].lower().endswith('.flac'))

    # 4. Sort files
    if args.sort == "date":
        files.sort(key=lambda x: x['modified'], reverse=True)
    elif args.sort == "size":
        files.sort(key=lambda x: x['size'], reverse=True)
    elif args.sort == "name":
        files.sort(key=lambda x: x['name'].lower())

    # 5. Apply Limit
    if args.limit and args.limit > 0:
        files = files[:args.limit]

    # 6. Render interface
    print(f"\n{BOLD_VIOLET}┌──────────────────────────────────────────────────────────────────────────────┐{RESET}")
    print(f"{BOLD_VIOLET}│ 🎵  {RESET}{BOLD}CONVERT & INVERT — DOWNLOADED TRACKS BROWSER{RESET}{BOLD_VIOLET}                        │{RESET}")
    print(f"{BOLD_VIOLET}└──────────────────────────────────────────────────────────────────────────────┘{RESET}")
    
    print(f" Source:  {source_desc}")
    print(f" Active Filters: Sort={args.sort.capitalize()} | Type={args.filter.upper()} " + 
          (f"| Search='{args.search}' " if args.search else "") + 
          (f"| Limit={args.limit}" if args.limit else ""))
    
    # Statistics cards
    stats_border = f"{GREY}├────────────────────────┬────────────────────────┬───────────┬───────────┤{RESET}"
    stats_header = f"{GREY}│{RESET} {BOLD}TOTAL DOWNLOADED{RESET}       {GREY}│{RESET} {BOLD}CUMULATIVE SIZE{RESET}        {GREY}│{RESET} {BOLD}FLAC (HQ){RESET} {GREY}│{RESET} {BOLD}MP3 (SQ){RESET}  {GREY}│{RESET}"
    
    total_size_str = get_human_size(total_size)
    stats_data   = f"{GREY}│{RESET} {total_count:<22} {GREY}│{RESET} {total_size_str:<22} {GREY}│{RESET} {flac_count:<9} {GREY}│{RESET} {mp3_count:<9} {GREY}│{RESET}"
    
    print(f"{GREY}┌────────────────────────┬────────────────────────┬───────────┬───────────┐{RESET}")
    print(stats_header)
    print(stats_border)
    print(stats_data)
    print(f"{GREY}└────────────────────────┴────────────────────────┴───────────┴───────────┘{RESET}\n")

    if not files:
        print(f" {YELLOW}Empty View: No files matched your active filters.{RESET}\n")
        return

    # File Table Headers
    # Col widths: IDX (4), FORMAT (8), FILENAME (42), SIZE (11), MODIFIED (19) -> Total 84 chars
    tbl_top =    f"{GREY}┌──────┬────────┬────────────────────────────────────────────┬─────────────┬─────────────────────┐{RESET}"
    tbl_header = f"{GREY}│{RESET} {BOLD}IDX{RESET}  {GREY}│{RESET} {BOLD}FORMAT{RESET} {GREY}│{RESET} {BOLD}TRACK FILE NAME{RESET}                            {GREY}│{RESET} {BOLD}FILE SIZE{RESET}   {GREY}│{RESET} {BOLD}LAST MODIFIED{RESET}       {GREY}│{RESET}"
    tbl_mid =    f"{GREY}├──────┼────────┼────────────────────────────────────────────┼─────────────┼─────────────────────┤{RESET}"
    tbl_bot =    f"{GREY}└──────┴────────┴────────────────────────────────────────────┴─────────────┴─────────────────────┘{RESET}"

    print(tbl_top)
    print(tbl_header)
    print(tbl_mid)

    for idx, f in enumerate(files, 1):
        name = f['name']
        ext = name.split('.')[-1].lower() if '.' in name else ''
        
        # Color coding based on extensions
        if ext == 'flac':
            format_str = f"{CYAN}FLAC{RESET}"
            name_colored = f"{BOLD_CYAN}{name[:40]:<42}{RESET}" if len(name) > 40 else f"{CYAN}{name:<42}{RESET}"
        elif ext == 'mp3':
            format_str = f"{GREEN}MP3{RESET}"
            name_colored = f"{BOLD_GREEN}{name[:40]:<42}{RESET}" if len(name) > 40 else f"{GREEN}{name:<42}{RESET}"
        else:
            format_str = f"{YELLOW}{ext[:6].upper():<6}{RESET}"
            name_colored = f"{name[:40]:<42}"

        # Clean overflow dots
        if len(name) > 40:
            # Re-construct display name with trailing dots
            trunc_name = name[:37] + "..."
            if ext == 'flac':
                name_colored = f"{CYAN}{trunc_name:<42}{RESET}"
            elif ext == 'mp3':
                name_colored = f"{GREEN}{trunc_name:<42}{RESET}"
            else:
                name_colored = f"{trunc_name:<42}"

        size_str = get_human_size(f['size'])
        
        # Try to format datetime
        try:
            dt_str = datetime.fromtimestamp(f['modified']).strftime('%Y-%m-%d %H:%M:%S')
        except Exception:
            dt_str = "Unknown"

        print(f"{GREY}│{RESET} {idx:<4} {GREY}│{RESET} {format_str:<6} {GREY}│{RESET} {name_colored} {GREY}│{RESET} {size_str:<11} {GREY}│{RESET} {dt_str:<19} {GREY}│{RESET}")

    print(tbl_bot)
    print(f" Showing {len(files)} items. Use flags to search, sort or filter. (e.g. {BOLD}make downloads -- --sort size --filter flac{RESET})\n")

if __name__ == "__main__":
    main()
