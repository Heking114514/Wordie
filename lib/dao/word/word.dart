import 'package:english/entity/word/po/word.dart';
import 'package:floor/floor.dart';
import 'package:sqflite/sqflite.dart';

import '../../util/time.dart';

@dao
abstract class WordDao {
  DatabaseExecutor get database;

  QueryAdapter get queryAdapter {
    return QueryAdapter(database);
  }

  WordStatusPO _mapWordStatus(Map<String, Object?> row) {
    return WordStatusPO(
      id: row['id'] as int?,
      word: row['word'] as String?,
      status: row['status'] as int?,
      studyCycle: row['studyCycle'] as int?,
      nextReviewTime: row['nextReviewTime'] as int?,
      createTime: row['createTime'] as int?,
      updateTime: row['updateTime'] as int?,
    );
  }

  @insert
  Future<int?> addWord(WordPO wordPO);

  @Query('''
  select word.* from  word_status status left join word word on status.word = word.book || '_' || word.word
   where status.status = 0
   group by word.word
   limit :count
  ''')
  Future<List<WordPO>> queryStudyingWords(int count);

  @Query('''
  select word.* from  word word left join word_status status on status.word = word.book || '_' || word.word
   where word.book=CAST(:book AS TEXT) and status.id is null
   group by word.word
   order by random()
   limit :count
  ''')
  Future<List<WordPO>> queryNotStudyWords(int book, int count);

  @Query('''
  select word.* from word word left join word_status status on status.word = word.book || '_' || word.word
   where word.book=CAST(:book AS TEXT) and status.id is null
   group by word.word
  ''')
  Future<List<WordPO>> queryAllNotStudyWords(int book);

  Future<void> deleteBookWords(int bookId) async {
    await queryAdapter.queryNoReturn(
        'DELETE FROM word WHERE book=CAST(?1 AS TEXT)',
        arguments: [bookId]);
  }

  Future<void> deleteBookWord(int bookId, String word) async {
    await queryAdapter.queryNoReturn(
      'DELETE FROM word WHERE book=CAST(?1 AS TEXT) AND word=?2',
      arguments: [bookId, word],
    );
  }

  Future<void> clearBookProgress(int bookId) async {
    // 鍙竻闄ゅ涔犱腑鍜屽凡瀹屾垚鐨勮繘搴︼紝淇濈暀鐔熻瘝(status=-1)涓嶈鍒犻櫎
    await queryAdapter.queryNoReturn(
        "DELETE FROM word_status WHERE word LIKE CAST(?1 AS TEXT) || '\\_%' ESCAPE '\\' AND status != -1",
        arguments: [bookId]);
  }

  Future<void> clearBookProgressAll(int bookId) async {
    await queryAdapter.queryNoReturn(
        "DELETE FROM word_status WHERE word LIKE CAST(?1 AS TEXT) || '\\_%' ESCAPE '\\'",
        arguments: [bookId]);
  }

  @Query('''
  select word.* from word_status status
  left join word word on status.word = word.book || '_' || word.word
  where status.status = 1
  group by word.book, word.word
  order by status.updateTime ASC
  limit :count
''')
  Future<List<WordPO>> queryNeedReviewWords(int count);

  Future<List<WordPO>> queryTodayReviewWords() {
    return queryAdapter.queryList(
      '''
      select word.*
      from word_status status
      inner join word word
        on status.word = word.book || '_' || word.word
      where status.status=1
        and status.updateTime>=?1
      group by word.book, word.word
      order by status.updateTime asc
      ''',
      mapper: (Map<String, Object?> row) => WordPO(
        id: row['id'] as int?,
        book: row['book'] as String?,
        word: row['word'] as String?,
      ),
      arguments: [getDayStartTime()],
    );
  }

  @insert
  Future<int> createWordStatus(WordStatusPO status);

  @Query('''
  select * from word_status where word=:word
  ''')
  Future<WordStatusPO?> queryWordStatus(String word);

  @update
  Future<int> updateStatus(WordStatusPO status);

  Future<void> upsetWordStatusById(
      String? wordId, int status, int bookId) async {
    if (wordId == null || wordId.isEmpty) return;
    String wordKey = "${bookId}_${wordId}";
    var wordStatus = await queryWordStatus(wordKey);
    if (wordStatus == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await createWordStatus(WordStatusPO(
        word: wordKey,
        status: status,
        studyCycle: 0,
        nextReviewTime: 0,
        createTime: now,
        updateTime: now,
      ));
      return;
    }
    await queryAdapter.queryNoReturn('''
    update word_status set status=?1, updateTime=?2 where word=?3
    ''', arguments: [
      status,
      DateTime.now().millisecondsSinceEpoch,
      wordKey,
    ]);
  }

  Future<void> markWordFamiliarById(String? wordId, int bookId) async {
    if (wordId == null || wordId.isEmpty) return;
    final wordKey = '${bookId}_$wordId';
    final now = DateTime.now().millisecondsSinceEpoch;
    final wordStatus = await queryWordStatus(wordKey);
    if (wordStatus == null) {
      await createWordStatus(WordStatusPO(
        word: wordKey,
        status: -1,
        studyCycle: 0,
        nextReviewTime: 0,
        createTime: now,
        updateTime: now,
      ));
      return;
    }
    wordStatus.status = -1;
    wordStatus.nextReviewTime = 0;
    wordStatus.updateTime = now;
    await updateStatus(wordStatus);
  }

  Future<void> restoreWordForStudy(String? wordId, int bookId) async {
    if (wordId == null || wordId.isEmpty) return;
    final wordKey = '${bookId}_$wordId';
    final now = DateTime.now().millisecondsSinceEpoch;
    final wordStatus = await queryWordStatus(wordKey);
    if (wordStatus == null) {
      await createWordStatus(WordStatusPO(
        word: wordKey,
        status: 0,
        studyCycle: 0,
        nextReviewTime: 0,
        createTime: now,
        updateTime: now,
      ));
      return;
    }
    wordStatus.status = 0;
    wordStatus.studyCycle = 0;
    wordStatus.nextReviewTime = 0;
    wordStatus.updateTime = now;
    await updateStatus(wordStatus);
  }

  Future<void> resetStudyCycle(int bookId) async {
    await queryAdapter.queryNoReturn(
      "UPDATE word_status SET studyCycle = 1 WHERE status = 1 AND word LIKE CAST(?1 AS TEXT) || '\\_%' ESCAPE '\\'",
      arguments: [bookId],
    );
  }

  Future<int?> queryWordCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct w.word) as count from word w
           left join word_status s on s.word = w.book || '_' || w.word
           where w.book=CAST(?1 AS TEXT) and (s.status is null or s.status != -1)''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments: [wordBook]);
    return count;
  }

  Future<int?> queryProgressWordCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct word.word) as count from word_status status
        left join word word on status.word = word.book || '_' || word.word
         where word.book=CAST(?1 AS TEXT) and status.status != -1 and (status.status=1 or (status.studyCycle>0))
        ''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments: [wordBook]);
    return count;
  }

  Future<int?> queryDailyBookPassWordCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct word.word) as count from  word_status status
        left join  word word  on status.word = word.book || '_' || word.word
         where word.book=CAST(?1 AS TEXT) and status.status!=-1
         and (status.status=1 or status.studyCycle>0)
         and createTime > ${getDayStartTime()}
        ''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments: [wordBook]);
    return count;
  }

  Future<List<String>> queryBookPassWord(int wordBook) async {
    var wordList = await queryAdapter.queryList(
        '''select distinct word.word as word from  word_status status
        left join  word word  on status.word = word.book || '_' || word.word
         where word.book=CAST(?1 AS TEXT) and status.status!=-1
         and (status.status=1 or status.studyCycle>0)
        ''',
        mapper: (Map<String, Object?> row) => row['word'] as String,
        arguments: [wordBook]);
    return wordList;
  }

  Future<List<String>> queryBookDeleteWord(int wordBook) async {
    var wordList = await queryAdapter.queryList(
        '''select distinct word.word as word from  word_status status
        left join  word word  on status.word = word.book || '_' || word.word
         where word.book=CAST(?1 AS TEXT) and status.status=-1
        ''',
        mapper: (Map<String, Object?> row) => row['word'] as String,
        arguments: [wordBook]);
    return wordList;
  }

  Future<List<String>> queryBookNotDeleteWord(int wordBook) async {
    var wordList = await queryAdapter.queryList(
        '''select distinct word.word as word from  word word
        left join  word_status status  on status.word = word.book || '_' || word.word
         where word.book=CAST(?1 AS TEXT) and (status.status!=-1 or status.status is null)
        ''',
        mapper: (Map<String, Object?> row) => row['word'] as String,
        arguments: [wordBook]);
    return wordList;
  }

  @Query("select * from word_status where word like :prefix")
  Future<List<WordStatusPO>> queryWordStatusByPrefix(String prefix);

  Future<List<WordStatusPO>> queryWordStatusByBook(int book) {
    // GLOB treats '_' literally. LIKE '${book}_%' incorrectly lets book 1
    // consume statuses from books 10 through 19.
    return queryAdapter.queryList(
      "select * from word_status where word GLOB CAST(?1 AS TEXT) || '_*'",
      mapper: _mapWordStatus,
      arguments: [book],
    );
  }

  Future<List<WordStatusPO>> queryTodayReviewStatuses(int book) {
    return queryAdapter.queryList(
      '''
      select status.*
      from word_status status
      inner join word word
        on status.word = word.book || '_' || word.word
      where word.book=CAST(?1 AS TEXT)
        and status.status=1
        and status.updateTime>=?2
      order by status.updateTime asc
      ''',
      mapper: _mapWordStatus,
      arguments: [book, getDayStartTime()],
    );
  }

  Future<int?> queryTodayReviewCount(int book) async {
    final count = await queryAdapter.query(
      '''
      select count(distinct word.word) as count
      from word_status status
      inner join word word
        on status.word = word.book || '_' || word.word
      where word.book=CAST(?1 AS TEXT)
        and status.status=1
        and status.updateTime>=?2
      ''',
      mapper: (Map<String, Object?> row) => row['count'] as int?,
      arguments: [book, getDayStartTime()],
    );
    return count;
  }

  @Query('''
    select count(*) as count from word_status
    where (status=1 or (studyCycle>0 and status!=-1))
    and updateTime > :dayStartTime
  ''')
  Future<int?> queryDailyPassWordCountWithTime(int dayStartTime);

  Future<int?> queryDailyPassWordCount() {
    return queryDailyPassWordCountWithTime(getDayStartTime());
  }

  Future<int?> queryDailyStudyCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct word.word) as count from  word_status status
        left join  word word  on status.word = word.book || '_' || word.word
         where word.book=CAST(?1 AS TEXT) and createTime > ${getDayStartTime()} and status.status!=-1 and status.status is not null
        ''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments: [wordBook]);
    return count;
  }

  Future<int?> queryTotalStudyTime() async {
    var result = await queryAdapter.query(
        'select sum(endTime-startTime) as time from study_time_count',
        mapper: (Map<String, Object?> row) => (row['time'] as int?) ?? 0);
    return result;
  }

  Future<int?> queryStudyTime() async {
    var count = await queryAdapter.query(
        '''
          select sum(endTime-startTime) as time from study_time_count
           where startTime > ${getDayStartTime()}
        ''',
        mapper: (Map<String, Object?> row) => row['time'] as int?,
        arguments: []);
    return count;
  }

  Future<void> deleteAllWords() async {
    await queryAdapter.queryNoReturn('DELETE FROM word', arguments: []);
  }

  Future<void> addWords(List<WordPO> words) async {
    await Future.forEach(words, (WordPO word) async {
      await addWord(word);
    });
  }

  Future<void> clearWord() async {
    await queryAdapter.queryNoReturn('DELETE FROM word', arguments: []);
  }

  @Query('select * from word where book=CAST(:book AS TEXT)')
  Future<List<WordPO>> queryWords(int book);

  @Query('select * from word_status')
  Future<List<WordStatusPO>> queryWordStatusList();

  Future<void> replaceBackupTables({
    required List<WordPO> words,
    required List<WordStatusPO> statuses,
    required List<StudyTimeCountPO> studyTimes,
    required List<WordStudyTimeCountPO> wordStudyTimes,
  }) async {
    await queryAdapter.queryNoReturn('DELETE FROM word_status');
    await queryAdapter.queryNoReturn('DELETE FROM word');
    await queryAdapter.queryNoReturn('DELETE FROM study_time_count');
    await queryAdapter.queryNoReturn('DELETE FROM word_study_time_count');

    for (final word in words) {
      await queryAdapter.queryNoReturn(
        'INSERT INTO word (id, book, word) VALUES (?1, ?2, ?3)',
        arguments: <Object>[word.id ?? 0, word.book ?? '', word.word ?? ''],
      );
    }
    for (final status in statuses) {
      await queryAdapter.queryNoReturn(
        'INSERT INTO word_status '
        '(id, word, status, studyCycle, nextReviewTime, createTime, updateTime) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
        arguments: <Object>[
          status.id ?? 0,
          status.word ?? '',
          status.status ?? 0,
          status.studyCycle ?? 0,
          status.nextReviewTime ?? 0,
          status.createTime ?? 0,
          status.updateTime ?? 0,
        ],
      );
    }
    for (final studyTime in studyTimes) {
      await queryAdapter.queryNoReturn(
        'INSERT INTO study_time_count (id, startTime, endTime) '
        'VALUES (?1, ?2, ?3)',
        arguments: <Object>[
          studyTime.id ?? 0,
          studyTime.startTime ?? 0,
          studyTime.endTime ?? 0,
        ],
      );
    }
    for (final item in wordStudyTimes) {
      await queryAdapter.queryNoReturn(
        'INSERT INTO word_study_time_count '
        '(id, word, startTime, endTime, studyCycle, playComplete) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6)',
        arguments: <Object>[
          item.id ?? 0,
          item.word ?? '',
          item.startTime ?? 0,
          item.endTime ?? 0,
          item.studyCycle ?? 0,
          item.playComplete ?? 0,
        ],
      );
    }
  }

  Future<void> addWordStudyTimeRecord(WordStudyTimeCountPO record) async {
    await queryAdapter
        .queryNoReturn('''insert into word_study_time_count (word, startTime, endTime, studyCycle, playComplete) values (?1, ?2, ?3, ?4, ?5)''',
            arguments: [
          record.word ?? '',
          record.startTime ?? 0,
          record.endTime ?? 0,
          record.studyCycle ?? 0,
          record.playComplete ?? 0
        ]);
  }

  Future<void> addStudyTimeRecord(StudyTimeCountPO record) async {
    await queryAdapter.queryNoReturn(
        '''insert into study_time_count (startTime, endTime) values (?1, ?2)''',
        arguments: [record.startTime ?? 0, record.endTime ?? 0]);
  }

  Future<int?> queryReviewWordCount() async {
    var count = await queryAdapter.query(
      'select count(distinct word) as count from word_status where status=1',
      mapper: (Map<String, Object?> row) => row['count'] as int?,
    );
    return count;
  }

  @Query('select * from word_study_time_count')
  Future<List<WordStudyTimeCountPO>> queryAllWordStudyTimeRecords();

  @Query('select * from study_time_count')
  Future<List<StudyTimeCountPO>> queryAllStudyTimeRecords();
}
