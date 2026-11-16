"""A stratified sample of the Lichess puzzle database (CC0) for calibrating
our engine rating: well-measured puzzles only (low rating deviation, many
plays, liked), the same number in each rating band.

zstd -dc lichess_db_puzzle.csv.zst | python3 tools/lichess_sample.py 1000 > sample.csv
"""
import csv
import random
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
LO, HI, BINS = 600, 2600, 20
PER = N // BINS
rng = random.Random(7)
reader = csv.reader(sys.stdin)
header = next(reader)
col = {name: i for i, name in enumerate(header)}
bins = [[] for _ in range(BINS)]
seen = [0] * BINS
for row in reader:
    try:
        rating, dev, plays, pop = int(row[col["Rating"]]), int(row[col["RatingDeviation"]]), int(row[col["NbPlays"]]), int(row[col["Popularity"]])
    except (ValueError, KeyError, IndexError):
        continue
    if dev > 80 or plays < 1000 or pop < 80 or not (LO <= rating < HI):
        continue
    b = (rating - LO) * BINS // (HI - LO)
    seen[b] += 1
    # выборка-резервуар в каждой полосе рейтинга
    if len(bins[b]) < PER:
        bins[b].append(row)
    else:
        j = rng.randrange(seen[b])
        if j < PER:
            bins[b][j] = row
out = csv.writer(sys.stdout)
out.writerow(["PuzzleId", "FEN", "Moves", "Rating", "RatingDeviation", "NbPlays", "Themes"])
for b in bins:
    for row in b:
        out.writerow([row[col[k]] for k in ("PuzzleId", "FEN", "Moves", "Rating", "RatingDeviation", "NbPlays", "Themes")])
print("bins:", [len(b) for b in bins], "seen:", seen, file=sys.stderr)
