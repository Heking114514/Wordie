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
    await queryAdapter.queryNoReturn('DELETE FROM word WHERE book=CAST(?1 AS TEXT)', arguments: [bookId]);
  }

  Future<void> clearBookProgress(int bookId) async {
    await queryAdapter.queryNoReturn(
      "DELETE FROM word_status WHERE word LIKE CAST(?1 AS TEXT) || '\\_%' ESCAPE '\\'",
      arguments: [bookId]
    );
  }

  @Query('''
  select word.* from word_status status
  left join word word on status.word = word.book || '_' || word.word
  where status.status = 1
  group by word.word
  order by status.updateTime ASC
  limit :count
''')
  Future<List<WordPO>> queryNeedReviewWords(int count);

  @insert
  Future<int> createWordStatus(WordStatusPO status);

  @Query('''
  select * from word_status where word=:word
  ''')
  Future<WordStatusPO?> queryWordStatus(String word);

  @update
  Future<int> updateStatus(WordStatusPO status);

  Future<void> upsetWordStatusById(String? wordId, int status, int bookId) async {
    String wordKey = "${bookId}_${wordId}";
    var wordStatus = await queryWordStatus(wordKey);
    if (wordStatus == null) {
      await createWordStatus(WordStatusPO(word: wordKey, status: status));
      return;
    }
    await queryAdapter.queryNoReturn('''
    update word_status set status=?1 where word=?2
    ''', arguments:[status, wordKey]);
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
        arguments:[wordBook]);
    return count;
  }

  Future<int?> queryDailyBookPassWordCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct word.word) as count from  word_status status
        left join  word word  on status.word = word.book || '_' || word.word
         where word.book=CAST(?1 AS TEXT) and (status.status=1 or status.studyCycle>0)
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
         where word.book=CAST(?1 AS TEXT) and (status.status=1 or status.studyCycle>0)
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
    return queryWordStatusByPrefix('${book}_%');
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
        arguments:[wordBook]);
    return count;
  }

  Future<int?> queryTotalStudyTime() async {
    var result = await queryAdapter.query('select sum(endTime-startTime) as time from study_time_count',
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
        arguments:[]);
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

  @Query('select * from word where book=:book')
  Future<List<WordPO>> queryWords(int book);

  @Query('select * from word_status')
  Future<List<WordStatusPO>> queryWordStatusList();

  Future<void> addWordStudyTimeRecord(WordStudyTimeCountPO record) async {
    await queryAdapter.queryNoReturn(
        '''insert into word_study_time_count (word, startTime, endTime, studyCycle, playComplete) values (?1, ?2, ?3, ?4, ?5)''',
        arguments:[record.word ?? '', record.startTime ?? 0, record.endTime ?? 0, record.studyCycle ?? 0, record.playComplete ?? 0]);
  }

  Future<void> addStudyTimeRecord(StudyTimeCountPO record) async {
    await queryAdapter.queryNoReturn(
        '''insert into study_time_count (startTime, endTime) values (?1, ?2)''',
        arguments:[record.startTime ?? 0, record.endTime ?? 0]);
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
