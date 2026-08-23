// void test_unit_begin()
// Begins unit test.

global.testAssertions = 0;
global.testAssertionsSucceeded = 0;
// Deliberately does NOT reset global.testFailLog - see test_assert_equals. The runner
// re-runs this helper after it has read the counters back, so anything cleared here is
// cleared again before the caller outside the game gets to look at it. Clear the log by
// hand when you want a fresh one.
