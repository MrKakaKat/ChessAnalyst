import chess

from chessanalyst.ideas import extract_signature, reaches, track_back
from chessanalyst.settings import Settings

S = Settings()


def _steps(fen, ucis):
    b = chess.Board(fen)
    out = []
    for u in ucis:
        m = chess.Move.from_uci(u)
        out.append((b.copy(stack=False), m))
        b.push(m)
    return out


def test_track_back_through_moves_and_castling():
    steps = _steps(chess.STARTING_FEN, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1"])
    assert track_back(steps, chess.F3) == chess.G1          # конь
    assert track_back(steps, chess.F1) == chess.H1          # ладья после рокировки
    assert track_back(steps, chess.G1) == chess.E1          # король
    assert track_back(steps, chess.D2) == chess.D2          # не ходила


def test_reaches_capture_check_square():
    b = chess.Board("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 0 1")
    # Ферзь f3 берёт f7 с матом: цель — пешка f7 (взятие) и король e8 (шах).
    assert reaches(b, ["f3f7"], chess.F3, chess.F7, "piece", 4)
    assert reaches(b, ["f3f7"], chess.F3, chess.E8, "king", 4)
    assert not reaches(b, ["c4f7"], chess.F3, chess.F7, "piece", 4)   # взял слон, не ферзь
    assert reaches(b, ["g1e2", "a7a6", "f3g3"], chess.F3, chess.G3, "square", 4)
    assert not reaches(b, ["g1e2", "a7a6", "f3g3"], chess.F3, chess.G3, "square", 2)


def test_signature_fork():
    # Nc7+ — вилка короля и ладьи, затем Nxa8.
    b = chess.Board("r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1")
    sig = extract_signature(b, ["b5c7", "e8d7", "c7a8"], S)
    assert sig is not None
    assert sig.target_kind == "piece" and sig.target_piece == "r"
    assert sig.attacker_square == chess.B5 and sig.target_square == chess.A8
    assert sig.motif == "fork"


def test_signature_mate():
    b = chess.Board("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")
    sig = extract_signature(b, ["d1d8"], S)
    assert sig.motif == "mate" and sig.target_kind == "king" and sig.attacker_square == chess.D1
