# frozen_string_literal: true

# Independent disabled-code reachability, typechecking, and metadata oracle.

require_relative '../support'

repo = Pathname.new(__dir__).parent.parent.parent
cli = Pathname.new(ARGV.fetch(0)).expand_path

def quoted(value)
  result = +'"'
  value.bytes.each do |byte|
    result << if byte == 34
                '\\"'
              elsif byte == 92
                '\\\\'
              elsif byte.between?(32, 126)
                byte.chr
              else
                format('\\x%02X', byte)
              end
  end
  result << '"'
  result
end

def escaped(value)
  value.bytes.map do |byte|
    if byte == 92
      '\\\\'
    elsif byte.between?(32, 126)
      byte.chr
    else
      format('\\x%02X', byte)
    end
  end.join.b
end

def occurrences(haystack, needle)
  haystack.enum_for(:scan, Regexp.new(Regexp.escape(needle))).map { Regexp.last_match.begin(0) }.length
end

Dir.mktmpdir('goosetest-disabled-') do |temporary|
  project = Pathname.new(temporary)
  (project / 'src').mkdir
  (project / 'test').mkdir
  (project / 'src/disabled.goose').write_text("namespace disabled;\n")
  (project / 'goosetest_root.goose').write_text(
    "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
    "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
  )
  test = project / 'test/disabled_test.goose'
  env = environment('GOOSE_HOME' => (project / 'cache').to_s)
  label = "same \"label\"\\\n\0\x1b\xC3\xA9".b
  reason = "pending \"); print(\"INJECTED\"); //\n\0\x1B\\".b
  template = <<~GOOSE
    // Disabled wrappers must remain typechecked without lifecycle side effects.
    namespace disabled_test;
    import goosetest;
    import std;
    fn initialize() -> i64 { print("EVENT CONSTRUCT"); return 7; }
    struct Fixture { value: i64 = initialize() }
    fn before_all(t: goosetest::Test&) { print("EVENT BEFORE_ALL"); t.assert_true(true); }
    fn after_all(t: goosetest::Test&) { print("EVENT AFTER_ALL"); t.assert_true(true); }
    fn before_each(t: goosetest::Test&, f: Fixture&) { print("EVENT BEFORE_EACH"); t.assert_eq(7, f.value); }
    fn after_each(t: goosetest::Test&, f: Fixture&) { print("EVENT AFTER_EACH"); t.assert_eq(7, f.value); }
    // @DisplayName(LABEL)
    // @Disabled(REASON)
    fn test_disabled_plain(t: goosetest::Test&) { print("EVENT DISABLED PLAIN"); t.assert_true(true); t.fail("disabled fail"); }
    // @DisplayName(LABEL)
    // @Disabled(REASON)
    fn test_disabled_fixture(t: goosetest::Test&, f: Fixture&) { print("EVENT DISABLED FIXTURE"); t.assert_eq(8, f.value); }
  GOOSE
  template = template.gsub('LABEL') { quoted(label) }.gsub('REASON') { quoted(reason) }

  run_case = lambda do |source, status|
    test.write_text(source)
    result = run_capture([cli, 'test', '--project', project], env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [result.status, result.stdout, result.stderr])
    [result.stdout, result.stderr]
  end

  events = lambda do |output|
    output.lines.map(&:chomp).select { |line| line.start_with?('EVENT ') }
  end

  style = -> { check_generated_style(project / 'goosetest_generated', repo) }

  out, = run_case.call(template, 0)
  assert_equal([], events.call(out), 'disabled suite ran lifecycle code')
  assert_includes(out, 'Cases: 0 passed, 0 failed, 2 skipped, 0 errors, 0 not run'.b)
  assert_includes(out, 'Assertions: 0; suite-hook errors: 0'.b)
  assert_equal(2, occurrences(out, "  display: ".b + escaped(label) + "\n".b), 'display metadata')
  assert_equal(2, occurrences(out, "  reason: ".b + escaped(reason) + "\n".b), 'reason metadata')
  assert_includes(out, 'SKIP test/disabled_test.goose::disabled_test::test_disabled_plain')
  assert_includes(out, 'SKIP test/disabled_test.goose::disabled_test::test_disabled_fixture')
  assert(!out.include?("\nINJECTED\n".b), 'disabled reason injected execution')
  style.call

  # Exact reason budget survives worst-case escaping; one extra byte fails explicitly.
  maximum_reason = "\x01".b * 1024
  maximum = template.gsub(quoted(reason)) { quoted(maximum_reason) }
  out, = run_case.call(maximum, 0)
  assert_equal(2, occurrences(out, "  reason: ".b + escaped(maximum_reason) + "\n".b),
               'maximum reason metadata')
  assert_equal([], events.call(out))
  style.call
  out, err = run_case.call(template.gsub(quoted(reason)) { quoted(maximum_reason + 'x') }, 2)
  assert(events.call(out).empty? && err.include?('disabled reason exceeds'.b),
         'oversized disabled reason', [out, err])

  # Even assertion failures in every hook remain unreachable in an all-disabled suite.
  no_hooks = template.gsub('t.assert_true(true); }', 't.fail("disabled hook"); }')
                     .gsub('t.assert_eq(7, f.value); }', 't.fail("disabled each hook"); }')
  out, = run_case.call(no_hooks, 0)
  assert(events.call(out).empty? && out.include?('2 skipped'.b), 'disabled hooks executed', out)

  enabled = <<~GOOSE.gsub('LABEL') { quoted(label) }
    // @DisplayName(LABEL)
    fn test_enabled(t: goosetest::Test&, f: Fixture&) { print("EVENT ENABLED"); t.assert_eq(7, f.value); }
  GOOSE
  out, = run_case.call(template + enabled, 0)
  assert_equal(['EVENT BEFORE_ALL', 'EVENT CONSTRUCT', 'EVENT BEFORE_EACH',
                'EVENT ENABLED', 'EVENT AFTER_EACH', 'EVENT AFTER_ALL'],
               events.call(out), 'enabled lifecycle events')
  assert_includes(out, 'Cases: 1 passed, 0 failed, 2 skipped'.b)
  assert_equal(3, occurrences(out, "  display: ".b + escaped(label) + "\n".b), 'enabled display metadata')
  style.call

  # Suite-setup failure must not overwrite explicit disabled reasons.
  failed_setup = (template + enabled).sub('print("EVENT BEFORE_ALL"); t.assert_true(true);',
                                          'print("EVENT BEFORE_ALL"); t.fail("setup cause");')
  out, = run_case.call(failed_setup, 1)
  assert_equal(['EVENT BEFORE_ALL', 'EVENT AFTER_ALL'], events.call(out), 'failed setup events')
  assert_includes(out, 'Cases: 0 passed, 0 failed, 3 skipped'.b)
  assert_equal(2, occurrences(out, "  reason: ".b + escaped(reason) + "\n".b), 'preserved reasons')
  assert_equal(1, occurrences(out, "  reason: suite setup failed\n".b), 'suite setup reason')
  assert_includes(out, 'suite-hook errors: 1'.b)

  # Each disabled dependency must still reach the type checker, despite no runtime execution.
  invalid = {
    'body' => template.sub('t.fail("disabled fail");', 'unknown_disabled_body();'),
    'fixture' => template.sub('return 7;', 'return "wrong type";'),
    'before_each' => template.sub('print("EVENT BEFORE_EACH");', 'unknown_before_each();'),
    'after_each' => template.sub('print("EVENT AFTER_EACH");', 'unknown_after_each();'),
    'before_all' => template.sub('print("EVENT BEFORE_ALL");', 'unknown_before_all();'),
    'after_all' => template.sub('print("EVENT AFTER_ALL");', 'unknown_after_all();')
  }
  invalid.each do |name, source|
    out, err = run_case.call(source, 2)
    assert(err.include?('compilation'.b), "missing compilation diagnostic for #{name}", [out, err])
    assert(events.call(out).empty?, "disabled code executed for #{name}", out)
    assert(!(project / 'goosetest_generated/tests').exist?, "artifacts for #{name}")
  end

  ['@Disabled("")', '@Tag("tag")', '@RepeatedTest(2)', '@Future("unsupported")'].each do |annotation|
    source = "namespace disabled_test;\nimport goosetest;\n// #{annotation}"
    source += "\nfn test_invalid(t: goosetest::Test&) { print(\"EVENT INVALID\"); }\n"
    out, err = run_case.call(source, 2)
    assert(events.call(out).empty?, 'invalid annotation executed', out)
    assert(err.include?('no tests executed'.b) && !err.include?('compilation'.b),
           'invalid annotation diagnostics', [annotation, err])
  end
end
puts 'disabled execution process tests passed'
