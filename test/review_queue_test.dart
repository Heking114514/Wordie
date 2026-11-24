import 'package:english/service/study/study.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('single-day review queue helpers', () {
    test('opening freeze only includes words completed by the opening time',
        () {
      final frozen = freezeReviewIdsForOpening(
        candidates: const <ReviewWordSnapshot>[
          ReviewWordSnapshot(
            id: 'later-priority',
            updateTime: 1200,
            lastReviewTime: 100,
          ),
          ReviewWordSnapshot(
            id: 'first-priority',
            updateTime: 1100,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'yesterday',
            updateTime: 900,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'after-open',
            updateTime: 2100,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'completed',
            updateTime: 1300,
            lastReviewTime: 0,
          ),
        ],
        dayStart: 1000,
        openedAt: 2000,
        maxCount: 3,
        excludedIds: const <String>['completed'],
      );

      expect(frozen, <String>['first-priority', 'later-priority']);
    });

    test('words completed after opening enter only the pending queue', () {
      final pending = buildPendingReviewIds(
        candidates: const <ReviewWordSnapshot>[
          ReviewWordSnapshot(
            id: 'before-open',
            updateTime: 1200,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'after-open',
            updateTime: 2200,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'active',
            updateTime: 1300,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'done',
            updateTime: 1400,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'yesterday',
            updateTime: 900,
            lastReviewTime: 0,
          ),
        ],
        dayStart: 1000,
        activeIds: const <String>['active'],
        excludedIds: const <String>['done'],
      );

      expect(pending, <String>['before-open', 'after-open']);
      expect(pending, isNot(contains('active')));
      expect(pending, isNot(contains('done')));
    });

    test('pending promotion respects the configured batch size', () {
      expect(
        limitReviewIds(
          const <String>['a', 'b', 'a', 'c', 'd'],
          2,
        ),
        <String>['a', 'b'],
      );
      expect(
        limitReviewIds(const <String>['a', 'b'], 0),
        <String>['a', 'b'],
      );
    });

    test('each unique active word is repeated once per review cycle', () {
      expect(
        expandReviewQueue(const <String>['a', 'b', 'a', ''], 3),
        <String>['a', 'b', 'a', 'b', 'a', 'b'],
      );
      expect(expandReviewQueue(const <String>[], 3), isEmpty);
    });

    test('promotion replaces the active queue and never re-adds the old one',
        () {
      final plan = promoteReviewQueuePlan(
        currentActiveIds: const <String>['old-active'],
        nextIds: const <String>['next-a', 'next-b'],
        candidates: const <ReviewWordSnapshot>[
          ReviewWordSnapshot(
            id: 'old-active',
            updateTime: 1200,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'next-a',
            updateTime: 1300,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'next-b',
            updateTime: 1400,
            lastReviewTime: 0,
          ),
          ReviewWordSnapshot(
            id: 'learned-later',
            updateTime: 2500,
            lastReviewTime: 0,
          ),
        ],
        dayStart: 1000,
        completedIds: const <String>['old-active'],
      );

      expect(plan.activeIds, <String>['next-a', 'next-b']);
      expect(plan.nextIds, <String>['learned-later']);
      expect(plan.nextIds, isNot(contains('old-active')));
      expect(plan.nextIds, isNot(contains('next-a')));
    });

    test('a stored queue from another day is stale', () {
      expect(isReviewStateForDay('2026-11-23', '2026-11-24'), isFalse);
      expect(isReviewStateForDay('2026-11-24', '2026-11-24'), isTrue);
      expect(isReviewStateForDay(null, '2026-11-24'), isFalse);
    });
  });
}
