"""Plays a game between two Stockfish settings from a given opening, for the
showcase games ("bot games"). The stronger side plays at full skill, the
weaker one at a lower Skill Level, so the game is decisive and tactical.

  python3 tools/engine_game.py "1. e4 e5 2. f4 exf4" out.pgn --white-skill 20 --black-skill 8 --seed 1
"""

from __future__ import annotations

import argparse
import io
import random

import chess
import chess.engine
import chess.pgn


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("opening")
    ap.add_argument("out")
    ap.add_argument("--engine", default="/usr/games/stockfish")
    ap.add_argument("--white-skill", type=int, default=20)
    ap.add_argument("--black-skill", type=int, default=20)
    ap.add_argument("--movetime", type=float, default=0.3)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--event", default="Engine game")
    args = ap.parse_args()

    random.seed(args.seed)
    start = chess.pgn.read_game(io.StringIO(args.opening)) if args.opening.strip() else None
    board = start.end().board() if start is not None else chess.Board()
    game = chess.pgn.Game.from_board(board)
    node = game.end()
    names = {chess.WHITE: f"Stockfish 16 (skill {args.white_skill})", chess.BLACK: f"Stockfish 16 (skill {args.black_skill})"}
    with chess.engine.SimpleEngine.popen_uci(args.engine) as eng:
        while not board.is_game_over(claim_draw=True) and board.ply() < 200:
            skill = args.white_skill if board.turn == chess.WHITE else args.black_skill
            eng.configure({"Skill Level": skill, "Threads": 1, "Hash": 64})
            res = eng.play(board, chess.engine.Limit(time=args.movetime * random.uniform(0.8, 1.2)))
            board.push(res.move)
            node = node.add_variation(res.move)
    game.headers["Event"] = args.event
    game.headers["Site"] = "ChessAnalyst"
    game.headers["Date"] = "2026.11.04"
    game.headers["White"] = names[chess.WHITE]
    game.headers["Black"] = names[chess.BLACK]
    game.headers["Result"] = board.result(claim_draw=True)
    if board.is_checkmate():
        game.headers["Termination"] = "Normal"
    with open(args.out, "w", encoding="utf-8") as f:
        print(game, file=f)
    print(args.out, game.headers["Result"], board.ply(), "plies")


if __name__ == "__main__":
    main()
