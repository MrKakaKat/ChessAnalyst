# Data

`openings.tsv` — opening names and lines (ECO code, name, PGN) from the
[Lichess chess-openings](https://github.com/lichess-org/chess-openings) tables,
released into the public domain (CC0). Extracted from the `chess-openings-graph`
npm package (MIT), which embeds those tables.

The book used by the analysis (`chessanalyst/data/openings_book.json` and the
Flutter asset `app/assets/openings_book.json`) is generated from this file:

    python -c "from chessanalyst.openings import write_book; write_book()"
    python tools/export_flutter_fixture.py ...   # also copies the book into the app
