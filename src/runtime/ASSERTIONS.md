# Assertion contracts

All comparison calls put expected values first. `assert_eq`, `assert_ne`,
`assert_true`, `assert_false`, `assert_contains`, `assert_near`, and `fail` stop
the current case on failure. `check_eq` records a failure and continues unless
a runtime result/diagnostic limit makes the run incomplete. Later cases still
execute after ordinary assertion failures.

`assert_contains(expected_fragment, actual_text, message = "")` compares byte
substrings, without Unicode normalization or case folding. Empty fragments match
any text, including empty text. Embedded NUL bytes are ordinary bytes. Failure
text labels the expected fragment and actual text.

`assert_near(expected, actual, absolute_tolerance, message = "")` takes f64 values
and an absolute tolerance. The tolerance must be finite and nonnegative; invalid
tolerances are assertion failures, even when operands are equal. Negative zero
is valid. NaN in either operand always fails. Equal positive infinities and equal
negative infinities pass with valid tolerance; other infinite comparisons fail.
Finite values pass when `abs(expected - actual) <= absolute_tolerance`, inclusive.
Overflow in the subtraction produces a failed comparison. There is no relative
tolerance. Zero tolerance accepts equal values, including opposite signed zeros.

Equality and inequality use Goose's ordinary comparable-value semantics for
scalars, strings, arrays, and slices. Floating equality is exact; use `assert_near`
when absolute tolerance is intended. Optional messages prefix generated details
without replacing expected/actual labels or the tolerance.

Passing assertions do not format values. Diagnostics are recorded separately
from console output. A diagnostic limit produces a visible incomplete-run error
and status 2, never a passing or silently truncated failed assertion. Retained
failures are committed atomically; previously recorded diagnostics survive.

Direct scalar values have finite formatting size; byte strings and collections
are appended with budget checks before copying or visiting more elements. Nested
arrays/slices retain Goose's bracket, separator and byte-string quoting style.
The total failure scratch retained by the framework is bounded by the remaining
diagnostic budget (plus a scalar-format scratch value).

Custom format hooks and opaque/default struct formatters are user code from the
runtime's perspective. They may allocate or do arbitrary work before
returning; the framework caps what is appended/retained after return. The CLI's
run deadline covers a nonterminating hook exactly as it covers a nonterminating
test. Direct runtime consumers must provide their own process deadline when
needed. No memory bound is promised inside custom or opaque struct formatters.
The bound covers direct scalar/collection rendering, not an arbitrary object
graph recursively printed by such a formatter.
