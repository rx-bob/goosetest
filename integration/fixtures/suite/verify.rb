# frozen_string_literal: true

# Independent suite-hook order, status, isolation and case-accounting oracle.

require_relative '../support'

repo = Pathname.new(__dir__).parent.parent.parent
cli = Pathname.new(ARGV.fetch(0)).expand_path

Dir.mktmpdir('goosetest-suite-') do |temporary|
  project = Pathname.new(temporary)
  (project / 'src').mkdir
  (project / 'test').mkdir
  %w[a b c].each do |name|
    (project / "src/#{name}.goose").write_text("namespace #{name};\n")
  end
  (project / 'goosetest_root.goose').write_text(
    "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
    "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
  )
  env = environment('GOOSE_HOME' => (project / 'cache').to_s)
  template = <<~GOOSE
    // Suite hooks surround every selected case, without sharing a fixture.
    namespace a_test;
    import goosetest;
    import std;
    fn initialize() -> i64 { print("EVENT A CONSTRUCT"); return 7; }
    struct Fixture { value: i64 = initialize() }
    fn before_all(t: goosetest::Test&) {
        print("EVENT A SETUP");
        SETUP
    }
    fn after_all(t: goosetest::Test&) {
        print("EVENT A CLEANUP");
        CLEANUP
    }
    fn before_each(f: Fixture&) { print("EVENT A EACH SETUP"); }
    fn after_each(f: Fixture&) { print("EVENT A EACH CLEANUP"); }
    fn test_one(t: goosetest::Test&, f: Fixture&) {
        print("EVENT A ONE");
        t.assert_eq(7, f.value);
        BODY
    }
    fn test_two(t: goosetest::Test&) { print("EVENT A TWO"); t.assert_true(true); }
  GOOSE
  (project / 'test/b_test.goose').write_text(<<~GOOSE)
    namespace b_test;
    import goosetest;
    import std;
    fn test_b(t: goosetest::Test&) { print("EVENT B BODY"); t.assert_true(true); }
  GOOSE
  (project / 'test/c_test.goose').write_text(<<~GOOSE)
    namespace c_test;
    import goosetest;
    import std;
    fn before_all() { print("EVENT C SETUP"); }
    fn after_all() { print("EVENT C CLEANUP"); }
    fn test_c(t: goosetest::Test&) { print("EVENT C BODY"); t.assert_true(true); }
  GOOSE

  scenarios = {
    'pass' => ['t.assert_true(true);', 't.assert_true(true);', '', 0, 4, 0, 0, 0],
    'setup' => ['t.fail("suite setup cause"); print("NEVER");', '', '', 1, 2, 0, 2, 1],
    'soft_setup' => ['t.check_eq(1, 2, "suite setup cause");', '', '', 1, 2, 0, 2, 1],
    'cleanup' => ['', 't.fail("suite cleanup cause");', '', 1, 4, 0, 0, 1],
    'both' => ['t.fail("suite setup cause");', 't.fail("suite cleanup cause");', '', 1, 2, 0, 2, 2],
    'body_cleanup' => ['', 't.fail("suite cleanup cause");', 't.fail("body cause");', 1, 3, 1, 0, 1],
    'two_checks' => ['t.check_eq(1, 2, "first"); t.check_eq(3, 4, "second");', '', '', 1, 2, 0, 2, 1]
  }

  scenarios.each do |mode, (setup, cleanup, body, status, passed, failed, skipped, hook_errors)|
    source = template.sub("    SETUP\n", "    #{setup}\n")
                     .sub("    CLEANUP\n", "    #{cleanup}\n")
                     .sub("    BODY\n", "    #{body}\n")
    (project / 'test/a_test.goose').write_text(source)
    result = run_capture([cli, 'test', '--project', project], env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [mode, result.status, result.stdout, result.stderr])
    output = result.stdout
    events = output.lines.map(&:chomp).select { |line| line.start_with?('EVENT ') }
    expected = ['EVENT A SETUP']
    unless skipped.positive?
      expected += ['EVENT A CONSTRUCT', 'EVENT A EACH SETUP', 'EVENT A ONE',
                   'EVENT A EACH CLEANUP', 'EVENT A TWO']
    end
    expected += ['EVENT A CLEANUP', 'EVENT B BODY', 'EVENT C SETUP', 'EVENT C BODY', 'EVENT C CLEANUP']
    assert_equal(expected, events, "events for #{mode}")
    summary = "Cases: #{passed} passed, #{failed} failed, #{skipped} skipped, 0 errors, 0 not run".b
    assert_includes(output, summary, "summary for #{mode}")
    assert_includes(output, "suite-hook errors: #{hook_errors}".b, "hook errors for #{mode}")
    assert(!output.include?('NEVER'.b), "NEVER output for #{mode}")
    if skipped.positive?
      assert(output.include?('suite setup failed'.b) && output.include?('[suite setup]'.b))
    end
    if cleanup.include?('cleanup cause')
      assert(output.include?('[suite cleanup]'.b) && output.include?('suite cleanup cause'.b))
    end
    if mode == 'both'
      assert(output.index('[suite setup]'.b) < output.index('[suite cleanup]'.b))
    end
    if mode == 'two_checks'
      assert(output.include?('first:'.b) && output.include?('second:'.b))
    end
    # Suite-hook diagnostics must never fabricate a case outcome.
    case_rows = output.lines.map(&:chomp)
                      .select { |line| line.start_with?('PASS ', 'FAIL ', 'SKIP ', 'ERROR ') }
    assert_equal(4, case_rows.length, "case rows for #{mode}")
    generated = project / 'goosetest_generated'
    check_generated_style(generated, repo)
  end

  # Incomplete setup still reaches the last wrapper across a dispatch boundary.
  tests = (0...40).map do |index|
    "fn test_#{index}(t: goosetest::Test&) { print(\"NEVER BODY\"); }"
  end.join("\n")
  (project / 'test/a_test.goose').write_text(
    "namespace a_test;\nimport goosetest;\nimport std;\n" \
    "fn before_all(t: goosetest::Test&) {\n    print(\"EVENT A SETUP\");\n" \
    "    var message: u8[>..] = [];\n    for index in 0..1048577 { message.push('x'); }\n" \
    "    t.fail(message);\n}\n" \
    "fn after_all() { print(\"EVENT A CLEANUP\"); }\n" + tests
  )
  result = run_capture([cli, 'test', '--project', project], env: env, timeout: 120)
  assert_equal(2, result.status, 'incomplete setup status')
  events = result.stdout.lines.map(&:chomp).select { |line| line.start_with?('EVENT ') }
  assert_equal(['EVENT A SETUP', 'EVENT A CLEANUP'], events, 'incomplete setup events')
  assert_includes(result.stdout, '42 not run'.b)
  assert_includes(result.stdout, 'diagnostic byte limit exhausted'.b)
  assert(!result.stdout.include?('NEVER BODY'.b))
end
puts 'suite hook process tests passed'
