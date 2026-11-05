import chess

from chessanalyst.openings import book_names, build_book, build_weights, load_book, load_weights


def test_book_matches_source_and_names():
    assert load_book() == build_book()          # сгенерированный файл не устарел
    book = load_book()
    assert len(book) > 7000
    b = chess.Board()
    for san in ["e4", "e5", "f4"]:
        b.push_san(san)
    assert book[b.epd()] == "King's Gambit"


def test_book_names_stop_after_leaving_book():
    ucis = ["e2e4", "e7e5", "f2f4", "e5f4", "a2a3", "h7h6", "b2b3"]
    names = book_names(chess.STARTING_FEN, ucis)
    assert names[2] == "King's Gambit" and names[3] == "King's Gambit Accepted"
    assert names[4] is None and names[5] is None and names[6] is None


def test_transpositions_are_book():
    # 1.Nf3 d5 2.d4 и 1.d4 d5 2.Nf3 — одна позиция.
    names = book_names(chess.STARTING_FEN, ["g1f3", "d7d5", "d2d4"])
    assert all(n is not None for n in names)
    assert book_names("8/8/8/8/8/8/8/K6k w - - 0 1", ["a1a2"]) == [None]   # не с начальной позиции


def test_weights_rank_main_moves_first():
    assert load_weights() == build_weights()
    w = load_weights()
    start = chess.Board()
    first = {}
    for m in start.legal_moves:
        b = start.copy()
        b.push(m)
        if b.epd() in w:
            first[start.san(m)] = w[b.epd()]
    top = sorted(first, key=first.get, reverse=True)[:2]
    assert set(top) == {"e4", "d4"}
