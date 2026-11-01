# frozen_string_literal: true

# External shell-status and plain-text oracle for the handwritten reporting harness.

require_relative '../support'

harness = Pathname.new(ARGV.fetch(0)).expand_path

run_case = lambda do |mode, status, summary|
  result = run_capture([harness, mode], timeout: 15)
  assert(result.status == status, 'unexpected status',
         [mode, result.status, result.stdout, result.stderr])
  assert_equal(''.b, result.stderr, 'unexpected stderr')
  assert_includes(result.stdout, summary, 'missing summary')
  assert_includes(result.stdout, 'locations identify test declarations'.b)
  assert(result.stdout.bytes.all? { |byte| byte == 10 || (32..126).cover?(byte) },
         'report contains non-printable bytes', result.stdout)
  repeated = run_capture([harness, mode], timeout: 15)
  assert_equal([status, result.stdout, result.stderr],
               [repeated.status, repeated.stdout, repeated.stderr], 'nondeterministic report')
  result.stdout
end

passed = run_case.call('passing', 0, 'Cases: 5 passed, 0 failed, 1 skipped, 0 errors, 0 not run'.b)
assert(passed.include?('viewer write access'.b) && passed.include?('pending clock support'.b))
assert(!passed.include?('Failures:'.b))
failed = run_case.call('failing', 1, 'Cases: 4 passed, 1 failed, 1 skipped, 0 errors, 0 not run'.b)
assert(failed.include?('Failures:'.b))
assert(failed.include?('test/permissions_test.goose:30'.b))
assert(failed.include?('.allowed expected: <true> actual: <false>'.b))
assert(failed.include?('.reason expected: <ok> actual: <insufficient_role>'.b))
assert(failed.index('.allowed'.b) < failed.index('.reason'.b))
assert(!failed.include?('.role expected'.b))
mixed = run_case.call('mixed', 1, 'Cases: 1 passed, 2 failed, 1 skipped, 0 errors, 2 not run; 2 filtered'.b)
%w[setup test cleanup].each do |phase|
  assert(mixed.include?("[#{phase}]".b), 'missing phase', [phase, mixed])
end
assert(mixed.include?('[suite setup]'.b), 'missing suite setup', mixed)
assert(mixed.include?('[suite cleanup]'.b), 'missing suite cleanup', mixed)
assert(mixed.include?('Suite-hook errors:'.b), mixed)
assert(mixed.include?('Assertions: 6; suite-hook errors: 2'.b), mixed)
assert(mixed.include?('setup\\x0Amessage'.b) && mixed.include?('body\\x1Bmessage'.b))
assert(mixed.include?('cleanup\\x0Dmessage'.b) && mixed.include?('pending\\x0Areason\\x1B'.b))
incomplete = run_case.call('incomplete', 2, 'Cases: 1 passed, 0 failed, 0 skipped, 0 errors, 3 not run'.b)
assert(incomplete.include?('incomplete run: diagnostic byte limit exhausted'.b))
puts 'reporting process tests passed'
