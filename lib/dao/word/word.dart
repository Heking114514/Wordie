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
  select word.* from  word_status status left join word word on word.word = status.word
   where status.status = 0 
   group by word.word
   limit :count
  ''')
  Future<List<WordPO>> queryStudyingWords(int count);

  @Query('''
  select word.* from  word word left join word_status status on word.word = status.word
   where word.book=:book and status.id is null
   group by word.word
   order by random()
   limit :count
  ''')
  Future<List<WordPO>> queryNotStudyWords(int book, int count);

  @Query('''
  select word.* from word word left join word_status status on word.word = status.word
   where word.book=:book and status.id is null
   group by word.word
  ''')
  Future<List<WordPO>> queryAllNotStudyWords(int book);

  Future<void> deleteBookWords(int bookId) async {
    await queryAdapter.queryNoReturn('DELETE FROM word WHERE book=?1', arguments: [bookId]);
  }

  Future<void> clearBookProgress(int bookId) async {
    await queryAdapter.queryNoReturn(
      'DELETE FROM word_status WHERE word IN (SELECT word FROM word WHERE book=?1)',
      arguments: [bookId]
    );
  }

  // 👇 修复点：彻底移除 SQL 单行注释，防止 limit 被截断
  @Query('''
  select word.* from word_status status 
  left join word word on word.word = status.word
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

  Future<void> upsetWordStatusById(String? wordId, int status) async {
    var wordStatus = await queryWordStatus(wordId ?? '');
    if (wordStatus == null) {
      await createWordStatus(WordStatusPO(word: wordId, status: status));
      return;
    }
    await queryAdapter.queryNoReturn('''
    update word_status set status=?1 where word=?2
    ''', arguments:[status, wordId ?? '']);
  }

  @Query('''
  select * from word_status 
  ''')
  Future<List<WordStatusPO>> queryWordStatusList();

  Future<int?> queryWordCount(int wordBook) async {
    var count = await queryAdapter.query(
        'select count(distinct word) as count from word where book=?1',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments: [wordBook]);
    return count;
  }

  Future<int?> queryProgressWordCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct word.word) as count from  word_status status
        left join  word word  on status.word = word.word
         where word.book=?1 and (status.status=1 or (status.studyCycle>0) or status.status=-1)
        ''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments:[wordBook]);
    return count;
  }

  Future<int?> queryDailyBookPassWordCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct word.word) as count from  word_status status
        left join  word word  on status.word = word.word
         where word.book=?1 and (status.status=1 or status.studyCycle>0)
         and createTime > ${getDayStartTime()}
        ''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments: [wordBook]);
    return count;
  }

  Future<List<String>> queryBookPassWord(int wordBook) async {
    var wordList = await queryAdapter.queryList(
        '''select distinct word.word as word from  word_status status
        left join  word word  on status.word = word.word
         where word.book=?1 and (status.status=1 or status.studyCycle>0)
        ''',
        mapper: (Map<String, Object?> row) => row['word'] as String,
        arguments: [wordBook]);
    return wordList;
  }

  Future<List<String>> queryBookDeleteWord(int wordBook) async {
    var wordList = await queryAdapter.queryList(
        '''select distinct word.word as word from  word_status status
        left join  word word  on status.word = word.word
         where word.book=?1 and status.status=-1
        ''',
        mapper: (Map<String, Object?> row) => row['word'] as String,
        arguments: [wordBook]);
    return wordList;
  }

  Future<List<String>> queryBookNotDeleteWord(int wordBook) async {
    var wordList = await queryAdapter.queryList(
        '''select distinct word.word as word from  word word
        left join  word_status status  on status.word = word.word
         where word.book=?1 and (status.status!=-1 or status.status is null)
        ''',
        mapper: (Map<String, Object?> row) => row['word'] as String,
        arguments: [wordBook]);
    return wordList;
  }

  Future<int?> queryDailyPassWordCount() async {
    var count = await queryAdapter.query(
      '''select count(distinct word.word) as count from  word_status status
        left join  word word  on status.word = word.word
         where (status.status=1 or (status.studyCycle>0 and status.status!=-1))
         and createTime > ${getDayStartTime()}
        ''',
      mapper: (Map<String, Object?> row) => row['count'] as int?,
    );
    return count;
  }

  Future<int?> queryDailyStudyCount(int wordBook) async {
    var count = await queryAdapter.query(
        '''select count(distinct word.word) as count from  word_status status
        left join  word word  on status.word = word.word
         where word.book=?1 and createTime > ${getDayStartTime()} and status.status!=-1 and status.status is not null
        ''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments:[wordBook]);
    return count;
  }

  Future<int?> queryReviewWordCount() async {
    var count = await queryAdapter.query(
        '''
          select count(distinct word) as count from word_status  
           where status=1
        ''',
        mapper: (Map<String, Object?> row) => row['count'] as int?,
        arguments:[]);
    return count;
  }

  @insert
  Future<int> addStudyTimeRecord(StudyTimeCountPO po);

  @insert
  Future<int> addWordStudyTimeRecord(WordStudyTimeCountPO po);

  @Query('select * from study_time_count order by startTime desc')
  Future<List<StudyTimeCountPO>> queryAllStudyTimeRecords();

  Future<int?> queryStudyTime() async {
    var count = await queryAdapter.query(
        '''
          select sum(endTime-startTime) as time from word_study_time_count  
           where startTime > ${getDayStartTime()}
        ''',
        mapper: (Map<String, Object?> row) => row['time'] as int?,
        arguments:[]);
    return count;
  }

  Future<void> clearWord() async {
    return await queryAdapter.queryNoReturn("delete from word");
  }

  Future<void> addWords(List<WordPO> words) async {
    var batch = database.batch();
    for (var word in words) {
      batch.insert("word", {
        "word": word.word,
        "book": word.book,
      });
    }
    await batch.commit();
  }
}