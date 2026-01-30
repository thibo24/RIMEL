#!/usr/bin/env python3
"""
Compute repo groups (1..3) based on contributor counts so that the three groups
are balanced in number of repos. Repos with the same contributor count are
kept in the same group.
Writes CSV `2-nombre-contributeurs/repos_groups.csv` with columns: repo_name,repo_group
"""
import csv
from collections import defaultdict
from pathlib import Path

CONTRIB_CSV = Path("2-nombre-contributeurs/data/contributors.csv")
OUT_CSV = Path("2-nombre-contributeurs/repos_groups.csv")

if not CONTRIB_CSV.exists():
    print(f"[ERROR] {CONTRIB_CSV} not found")
    raise SystemExit(1)

# Read contributors
repos = []  # list of (repo, count)
with open(CONTRIB_CSV, newline='', encoding='utf-8') as f:
    r = csv.reader(f)
    header = next(r, None)
    for row in r:
        if not row:
            continue
        repo = row[0].strip()
        try:
            count = int(row[1])
        except Exception:
            count = 0
        repos.append((repo, count))

if not repos:
    print("No repos found in contributors.csv")
    OUT_CSV.write_text("repo_name,repo_group\n")
    raise SystemExit(0)

# Build buckets by contributor count (sorted ascending)
buckets = defaultdict(list)
for repo, c in repos:
    buckets[c].append(repo)

sorted_counts = sorted(buckets.keys())

# Create list of (count, list_of_repos) in order
items = [(c, buckets[c]) for c in sorted_counts]

# Total repos
total = sum(len(lst) for _, lst in items)
if total == 0:
    print("No repos to group")
    OUT_CSV.write_text("repo_name,repo_group\n")
    raise SystemExit(0)

# targets
import math
first_target = math.ceil(total / 3)
second_target = math.ceil(2 * total / 3)

# Find split indices ensuring buckets remain intact
groups = {}  # repo -> group_num
cum = 0
i_cut = None
j_cut = None
for idx, (cnt, lst) in enumerate(items):
    cum += len(lst)
    if i_cut is None and cum >= first_target:
        i_cut = idx
    if j_cut is None and cum >= second_target:
        j_cut = idx

# Assign groups by bucket index
for idx, (cnt, lst) in enumerate(items):
    if i_cut is None:
        g = 1
    elif j_cut is None:
        g = 1 if idx <= i_cut else 2
    else:
        if idx <= i_cut:
            g = 1
        elif idx <= j_cut:
            g = 2
        else:
            g = 3
    for repo in lst:
        groups[repo] = g

# Write output CSV (ensure deterministic order)
with open(OUT_CSV, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['repo_name', 'repo_group'])
    for repo, _ in sorted(repos, key=lambda x: x[0]):
        w.writerow([repo, groups.get(repo, 1)])

print(f"Wrote {OUT_CSV} ({len(groups)} repos grouped into 3 groups)")
