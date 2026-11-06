import 'dart:io';

import 'package:chessanalyst/analysis/eval.dart';
import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/kinds.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _e = Eval(cp: 30, wdl: (400, 300, 300));

List<String> k(String fen, String uci, [List<String>? pv]) =>
    kindsOf(Pos.fromFen(fen), Pos.move(uci), pv ?? [uci], _e, const Settings());

void main() {
  test('kinds of moves', () {
    // вилка конём: Nc7+ по королю и ладье
    expect(k('r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1', 'b5c7'), contains('fork'));
    // развитие в дебюте и рокировка
    expect(k('rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2', 'g1f3'), contains('development'));
    expect(k('r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4', 'e1g1'), contains('king_safety'));
    // пешечный ход без контакта — push; в контакт с пешкой — break
    expect(k('4k3/8/8/8/8/8/4P3/4K3 w - - 0 1', 'e2e4'), contains('push'));
    // в дебюте: пешка в центре и на фланге
    expect(k('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'e2e4'), contains('push_center'));
    expect(k('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'h2h3'), contains('push_flank'));
    expect(k('4k3/8/8/3p4/8/4P3/8/4K3 w - - 0 1', 'e3e4'), contains('break'));
    // ладья на открытую линию
    expect(k('4k3/8/8/8/8/8/PP4PP/R3K3 w - - 0 1', 'a1d1'), contains('open_file'));
    // слон открывает линию ладьи на короля — вскрытый шах
    expect(k('4k3/8/8/8/4B3/8/8/4R1K1 w - - 0 1', 'e4b7'), contains('discovered_check'));
    expect(k('4q1k1/8/8/8/4B3/8/8/4R1K1 w - - 0 1', 'e4b7'), contains('discovered_queen'));
    // выход из-под шаха
    expect(k('4k3/8/8/8/8/8/8/r3K3 w - - 0 1', 'e1e2'), contains('check_escape'));
    // конь под ударом пешки уходит — отступление
    expect(k('4k3/8/3p4/4N3/8/8/8/R3K3 w - - 0 1', 'e5f3'), contains('retreat'));
    expect(k('4k3/8/3p4/4N3/8/8/8/R3K3 w - - 0 1', 'a1a5'), isNot(contains('retreat')));
    // взятие незащищённой фигуры — свободный материал
    expect(k('4k3/8/8/3n4/8/8/8/3RK3 w - - 0 1', 'd1d5'), contains('free'));
    // ладьи встают друг против друга, обе защищены — предложение размена;
    // против коня — предложение обмена
    expect(k('3rk3/8/8/8/8/8/8/R3K3 w - - 0 1', 'a1d1'), contains('offer_exchange'));
    expect(k('3nk3/8/8/8/8/8/8/R3K3 w - - 0 1', 'a1d1'), isNot(contains('offer_exchange')));
    expect(k('4k3/8/8/2b5/8/8/8/B3K2N w - - 0 1', 'h1f2'), isNot(contains('offer_barter')));
    // перегрузка: конь e6 — единственный защитник d8 и f8, ладья бьёт d8
    expect(k('3r1b1k/6pp/4n3/8/8/8/6PP/3R1RK1 w - - 0 1', 'd1d8'), contains('overload'));
  });

  test('played kinds: wrong piece', () {
    final b = Pos.fromFen('4k3/8/8/3p4/2P1P3/8/8/4K3 w - - 0 1');
    expect(playedKinds(b, Pos.move('c4d5'), ['c4d5'], _e, Pos.move('e4d5'), const Settings()), contains('wrong_piece'));
  });

  test('every move of the showcase games gets a kind', () {
    final g = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());
    for (final p in g.plies) {
      final b = Pos.fromFen(p.fenBefore);
      expect(kindsOf(b, Pos.move(p.uci), p.played.pv, p.played.eval, const Settings()), isNotEmpty);
    }
  });
}
