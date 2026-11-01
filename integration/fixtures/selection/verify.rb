# frozen_string_literal: true

# Independent selection, cold call-graph and fail-fast cleanup oracle.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent

Dir.mktmpdir('goosetest-selection-') do |temporary|
  project = Pathname.new(temporary)
  %w[src test integration].each { |name| (project / name).mkdir }
  %w[a b].each do |name|
    (project / "src/#{name}.goose").write_text("namespace #{name};\n")
  end
  (project / 'goosetest_root.goose').write_text(
    "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
    "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
  )
  env = environment('GOOSE_HOME' => (project / 'cache').to_s)
  a = <<~GOOSE
    // Selected cases keep per-case and suite cleanup boundaries.
    namespace a_test;
    import goosetest;
    import std;
    fn initialize() -> i64 { print("EVENT A CONSTRUCT"); return 7; }
    struct Fixture { value: i64 = initialize() }
    fn before_all(t: goosetest::Test&) { print("EVENT A SETUP"); SETUP }
    fn after_all(t: goosetest::Test&) { print("EVENT A CLEANUP"); CLEANUP }
    fn before_each(t: goosetest::Test&, f: Fixture&) { print("EVENT A EACH SETUP"); }
    fn after_each(t: goosetest::Test&, f: Fixture&) { print("EVENT A EACH CLEANUP"); }
    // @DisplayName("pretty label")
    fn test_first(t: goosetest::Test&, f: Fixture&) { print("EVENT A FIRST"); t.assert_eq(7, f.value); BODY }
    fn test_second(t: goosetest::Test&) { print("EVENT A SECOND"); t.assert_true(true); }
    // @Disabled("own reason")
    fn test_disabled(t: goosetest::Test&, f: Fixture&) { print("NEVER DISABLED"); t.fail("disabled"); }
  GOOSE
  b = <<~GOOSE
    namespace b_test;
    import goosetest;
    import std;
    fn before_all() { print("EVENT B SETUP"); }
    fn after_all() { print("EVENT B CLEANUP"); }
    fn test_later(t: goosetest::Test&) { print("EVENT B BODY"); t.assert_true(true); }
  GOOSE
  integration = <<~GOOSE
    namespace flow_test;
    import goosetest;
    import std;
    fn test_flow(t: goosetest::Test&) { print("EVENT INTEGRATION"); t.assert_true(true); }
  GOOSE

  write_case = lambda do |setup = '', cleanup = '', body = ''|
    source = a.sub(' SETUP }') { " #{setup} }" }
              .sub(' CLEANUP }') { " #{cleanup} }" }
              .sub(' BODY }') { " #{body} }" }
    (project / 'test/a_test.goose').write_text(source)
    (project / 'test/b_test.goose').write_text(b)
    (project / 'integration/flow_test.goose').write_text(integration)
  end

  run_case = lambda do |command = 'test', extra = [], status = 0, contains = ''.b|
    result = run_capture([cli, command, '--project', project, *extra],
                         env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [command, extra, result.status, result.stdout, result.stderr])
    assert_includes(result.stdout + result.stderr, contains, 'missing output')
    result
  end

  events = lambda do |result|
    result.stdout.lines.map(&:chomp).select { |line| line.start_with?('EVENT ') }
  end

  listed = lambda do |result|
    result.stdout.force_encoding('UTF-8').lines
          .select { |line| line.start_with?('unit  ', 'integration  ') }
          .map { |line| line.split[1] }
  end

  reported = lambda do |result|
    result.stdout.force_encoding('UTF-8').lines.each_with_object([]) do |line, result_rows|
      match = line.match(/^(?:PASS|FAIL|SKIP|NOT RUN|ERROR) ([^ ]+) /)
      result_rows << match[1] if match
    end
  end

  write_case.call
  [[], %w[--suite unit], %w[--suite integration], %w[--suite all],
   %w[--filter ::test_first], %w[--filter .goose::], ['--filter', ''],
   %w[--suite unit --filter ::test_disabled]].each do |options|
    ids = listed.call(run_case.call('list', options))
    executed = run_case.call('test', options)
    assert_equal(ids, reported.call(executed), "reported cases for #{options.inspect}")
  end
  disabled = run_case.call('test', ['--filter', '::test_disabled'])
  assert(events.call(disabled).empty? && disabled.stdout.include?('0 passed, 0 failed, 1 skipped'.b))
  assert_includes(disabled.stdout, '0 not run; 4 filtered'.b)
  assert(disabled.stdout.include?('own reason'.b) && disabled.stdout.include?('Assertions: 0;'.b))

  %w[test_.* * \[first\] pretty\ label no\ match].each do |literal|
    %w[list test].each do |command|
      result = run_case.call(command, ['--filter', literal], 2, 'zero cases'.b)
      assert(events.call(result).empty?)
    end
  end
  run_case.call('list', %w[--suite integration --filter ::test_first], 2, 'zero cases'.b)
  integration_path = project / 'integration/flow_test.goose'
  integration_path.unlink
  %w[list test].each do |command|
    run_case.call(command, %w[--suite integration], 2, 'zero cases'.b)
  end
  integration_path.write_text(integration)
  before = listed.call(run_case.call('list', ['--filter', '::test_first']))
  path = project / 'test/a_test.goose'
  path.write_text(path.read_text.sub('pretty label', 'changed display label'))
  assert_equal(before, listed.call(run_case.call('list', ['--filter', '::test_first'])))
  assert_equal(before, reported.call(run_case.call('test', ['--filter', '::test_first'])))
  run_case.call('list', ['--filter', 'changed display label'], 2, 'zero cases'.b)

  write_case.call
  selected_b = run_case.call('test', ['--filter', '::test_later'])
  assert_equal(['EVENT B SETUP', 'EVENT B BODY', 'EVENT B CLEANUP'], events.call(selected_b))
  assert_includes(selected_b.stdout, '4 filtered'.b)

  # Hard assertion returns in cold bodies retain their required runtime ancestry.
  write_case.call('', '', 't.assert_true(false); t.fail("filtered hard return"); print("NEVER FILTERED");')
  cold = run_case.call('test', ['--filter', '::test_later'])
  assert_equal(['EVENT B SETUP', 'EVENT B BODY', 'EVENT B CLEANUP'], events.call(cold))
  assert(!cold.stdout.include?('NEVER FILTERED'.b) && cold.stdout.include?('4 filtered'.b))

  # Unselected sources, constructors and hooks still compile in their recovery ancestry.
  invalid_changes = [
    ['test/b_test.goose', 't.assert_true(true);', 'unknown_filtered_body();'],
    ['test/a_test.goose', 'return 7;', 'return "wrong fixture value";'],
    ['test/a_test.goose', 'print("EVENT A EACH SETUP");', 'unknown_filtered_each();'],
    ['test/a_test.goose', 'print("EVENT A SETUP");', 'unknown_filtered_suite();'],
    ['test/a_test.goose', 'print("EVENT A EACH CLEANUP");', 'unknown_filtered_each_cleanup();'],
    ['test/a_test.goose', 'print("EVENT A CLEANUP");', 'unknown_filtered_suite_cleanup();']
  ]
  invalid_changes.each do |filename, old, new|
    write_case.call
    path = project / filename
    path.write_text(path.read_text.sub(old, new))
    selected = filename.start_with?('test/b') ? '::test_first' : '::test_later'
    result = run_case.call('test', ['--filter', selected], 2, 'compilation'.b)
    assert(events.call(result).empty?)
    assert_includes(result.stderr, new.split('(')[0].b) if new.start_with?('unknown_')
    assert(!(project / 'goosetest_generated/tests').exist?)
  end

  write_case.call
  path = project / 'test/b_test.goose'
  path.write_text(b.sub('t: goosetest::Test&', 't: i64'))
  result = run_case.call('test', ['--filter', '::test_first'], 2, 'no tests executed'.b)
  assert(events.call(result).empty?)
  write_case.call
  missing = project / 'src/missing.goose'
  missing.write_text("namespace missing;\n")
  result = run_case.call('test', ['--filter', '::test_first'], 2, 'no tests executed'.b)
  assert(events.call(result).empty?)
  missing.unlink

  active_a = ['EVENT A SETUP', 'EVENT A CONSTRUCT', 'EVENT A EACH SETUP',
              'EVENT A FIRST', 'EVENT A EACH CLEANUP']
  write_case.call('', '', 't.fail("first failed"); print("NEVER BODY");')
  result = run_case.call('test', %w[--suite unit --fail-fast], 1)
  assert_equal(active_a + ['EVENT A CLEANUP'], events.call(result))
  assert_includes(result.stdout,
                  'Cases: 0 passed, 1 failed, 1 skipped, 0 errors, 2 not run; 1 filtered'.b)
  assert_includes(result.stdout, 'NOT RUN test/a_test.goose::a_test::test_second'.b)
  assert_includes(result.stdout, 'NOT RUN test/b_test.goose::b_test::test_later'.b)
  assert(result.stdout.include?('fail-fast'.b) && result.stdout.include?('own reason'.b))
  assert(!result.stdout.include?('NEVER BODY'.b))
  result = run_case.call('test', ['--suite', 'unit'], 1)
  assert_equal(active_a + ['EVENT A SECOND', 'EVENT A CLEANUP',
                           'EVENT B SETUP', 'EVENT B BODY', 'EVENT B CLEANUP'],
               events.call(result))
  assert_includes(result.stdout,
                  'Cases: 2 passed, 1 failed, 1 skipped, 0 errors, 0 not run; 1 filtered'.b)

  write_case.call
  path = project / 'test/a_test.goose'
  path.write_text(path.read_text.sub('print("EVENT A EACH CLEANUP");',
                                     'print("EVENT A EACH CLEANUP"); t.fail("each cleanup failed");'))
  result = run_case.call('test', %w[--suite unit --fail-fast], 1)
  assert_equal(active_a + ['EVENT A CLEANUP'], events.call(result))
  assert_includes(result.stdout,
                  'Cases: 0 passed, 1 failed, 1 skipped, 0 errors, 2 not run; 1 filtered'.b)
  assert(result.stdout.include?('[cleanup]'.b) && result.stdout.include?('each cleanup failed'.b))

  write_case.call('t.fail("setup failed");')
  result = run_case.call('test', %w[--suite unit --fail-fast], 1)
  assert_equal(['EVENT A SETUP', 'EVENT A CLEANUP'], events.call(result))
  assert_includes(result.stdout,
                  'Cases: 0 passed, 0 failed, 3 skipped, 0 errors, 1 not run; 1 filtered'.b)
  assert(result.stdout.include?('suite setup failed'.b) && result.stdout.include?('own reason'.b))

  write_case.call('', 't.fail("cleanup failed");')
  result = run_case.call('test', %w[--suite unit --fail-fast], 1)
  assert_equal(active_a + ['EVENT A SECOND', 'EVENT A CLEANUP'], events.call(result))
  assert_includes(result.stdout,
                  'Cases: 2 passed, 0 failed, 1 skipped, 0 errors, 1 not run; 1 filtered'.b)
  assert_includes(result.stdout, '[suite cleanup]'.b)

  generated = project / 'goosetest_generated'
  check_generated_style(generated, repo)
end
puts 'selection and fail-fast process tests passed'
