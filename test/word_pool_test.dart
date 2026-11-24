import 'package:english/dicts/reader.dart';
import 'package:english/service/word/word.dart';
import 'package:flutter_test/flutter_test.dart';

Word _word(String id, String spelling, {String means = '释义'}) {
  return Word(id: id, word: spelling, means: means);
}

void main() {
  group('WordPoolSnapshot', () {
    test('keeps pools overlapping and includes difficult words in ordinary',
        () {
      final snapshot = WordPoolSnapshot.fromWords(
        sourceWords: <Word>[
          _word('a', 'apple'),
          _word('b', 'banana'),
          _word('c', 'cherry'),
          _word('d', 'date'),
          _word('e', 'elder'),
        ],
        familiarKeys: const <String>['B', 'c'],
        difficultSpellings: const <String>['apple', 'BANANA'],
        deletedKeys: const <String>['elder'],
      );

      expect(
        snapshot.ordinaryWords.map((word) => word.word),
        <String>['apple', 'banana', 'date'],
      );
      expect(
        snapshot.familiarWords.map((word) => word.word),
        <String>['banana', 'cherry'],
      );
      expect(
        snapshot.difficultWords.map((word) => word.word),
        <String>['apple', 'banana'],
      );
      expect(snapshot.countFor(WordPoolType.ordinary), 3);
      expect(snapshot.countFor(WordPoolType.familiar), 2);
      expect(snapshot.countFor(WordPoolType.difficult), 2);
    });

    test('deduplicates source words by spelling', () {
      final snapshot = WordPoolSnapshot.fromWords(
        sourceWords: <Word>[
          _word('one', 'same'),
          _word('two', 'Same'),
          _word('three', 'other'),
        ],
      );

      expect(
        snapshot.ordinaryWords.map((word) => word.word),
        <String>['same', 'other'],
      );
    });
  });

  group('DifficultWordStore migration', () {
    test('migrates legacy global words once into the active book', () {
      final migrated = DifficultWordStore.migrateLegacy(
        byBook: <String, List<String>>{
          '2': <String>[' Beta ', 'alpha', 'alpha'],
        },
        legacyWords: const <String>['Old', 'old'],
        activeBookId: '1',
        alreadyMigrated: false,
      );

      expect(migrated['1'], <String>['old']);
      expect(migrated['2'], <String>['alpha', 'beta']);

      final alreadyMigrated = DifficultWordStore.migrateLegacy(
        byBook: migrated,
        legacyWords: const <String>['ignored'],
        activeBookId: '3',
        alreadyMigrated: true,
      );
      expect(alreadyMigrated.containsKey('3'), isFalse);
      expect(alreadyMigrated['1'], <String>['old']);
    });

    test('does not overwrite a book that already has scoped words', () {
      final migrated = DifficultWordStore.migrateLegacy(
        byBook: <String, List<String>>{
          '1': <String>['scoped'],
        },
        legacyWords: const <String>['legacy'],
        activeBookId: '1',
        alreadyMigrated: false,
      );

      expect(migrated['1'], <String>['scoped']);
    });
  });

  test('TXT export uses spelling and normalized meaning columns', () {
    final content = DifficultWordStore.buildTxt(<Word>[
      _word('a', 'apple', means: '苹果\n水果'),
      _word('b', 'banana', means: ' '),
    ]);

    expect(content, 'apple\t苹果 水果\nbanana\t暂无释义\n');
  });
}
