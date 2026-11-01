# frozen_string_literal: true

# Independent process oracle for generated per-case fixture lifecycles.

require_relative '../support'

repo = Pathname.new(__dir__).parent.parent.parent
fixtures = Pathname.new(__dir__)
cli = Pathname.new(ARGV.fetch(0)).expand_path

Dir.mktmpdir('goosetest-lifecycle-') do |temporary|
  project = Pathname.new(temporary)
  (project / 'src').mkdir
  (project / 'test').mkdir
  (project / 'src/lifecycle.goose').write_text("namespace lifecycle;\n")
  (project / 'goosetest_root.goose').write_text(
    "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
    "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
  )
  test = project / 'test/lifecycle_test.goose'
  env = environment('GOOSE_HOME' => (project / 'cache').to_s)

  run_case = lambda do |source, status|
    test.write_text(source)
    run_checked(['goosefmt', 'fmt', '--config', repo / '.goosefmt.toml', test], timeout: 15)
    run_checked(['goosefmt', 'check', '--config', repo / '.goosefmt.toml', test], timeout: 15)
    result = run_capture([cli, 'test', '--project', project], env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [result.status, result.stdout, result.stderr])
    generated = project / 'goosetest_generated'
    check_generated_style(generated, repo) if generated.exist?
    [result.stdout, result.stderr]
  end

  events = lambda do |output|
    output.lines.map(&:chomp).select { |line| line.start_with?('EVENT ') }
  end

  template = (fixtures / 'cases.goose.data').read_text
  scenarios = {
    'pass' => {},
    'setup_hard' => { 'SETUP_FAILURE' => 'if f.id == 1 { t.fail("setup hard"); print("NEVER SETUP"); }' },
    'setup_soft' => { 'SETUP_FAILURE' => 'if f.id == 1 { t.check_eq(1, 2, "setup soft"); print("SOFT CONTINUED"); }' },
    'setup_default' => { 'SETUP_EARLY' => 'if f.id == 1 { t.fail("setup default"); }' },
    'body' => { 'BODY_FAILURE' => 't.fail("body hard"); print("NEVER BODY");' },
    'cleanup' => { 'CLEANUP_FAILURE' => 'if f.id == 1 { t.fail("cleanup hard"); print("NEVER CLEANUP"); }' },
    'body_cleanup' => {
      'BODY_FAILURE' => 't.fail("body hard"); print("NEVER BODY");',
      'CLEANUP_FAILURE' => 'if f.id == 1 { t.fail("cleanup hard"); print("NEVER CLEANUP"); }'
    },
    'setup_cleanup' => {
      'SETUP_FAILURE' => 'if f.id == 1 { t.fail("setup hard"); }',
      'CLEANUP_FAILURE' => 'if f.id == 1 { t.fail("cleanup hard"); }'
    }
  }

  scenarios.each do |name, changes|
    source = template
    %w[SETUP_EARLY SETUP_FAILURE BODY_FAILURE CLEANUP_FAILURE].each do |key|
      source = source.gsub(key) { changes.fetch(key, '') }
    end
    setup_failed = name.start_with?('setup')
    first_state = if name == 'setup_default'
                    7
                  elsif setup_failed
                    9
                  else
                    11
                  end
    # Soft setup continues after its failure; readiness becomes true but body is still skipped.
    ready = !setup_failed || name == 'setup_soft'
    source = source.gsub('CLEANUP_CHECK') do
      "if f.id == 1 { t.assert_eq(#{first_state}, f.state); " \
        "t.assert_eq(#{ready}, f.ready); } " \
        'else { t.assert_eq(12, f.state); }'
    end
    out, err = run_case.call(source, name == 'pass' ? 0 : 1)
    expected = ['EVENT CONSTRUCT 1', 'EVENT SETUP 1']
    expected += ['EVENT BODY 1'] unless setup_failed
    expected += ['EVENT CLEAN 1', 'EVENT FREE 1', 'EVENT CONSTRUCT 2',
                 'EVENT SETUP 2', 'EVENT SECOND 2', 'EVENT CLEAN 2']
    assert_equal(expected, events.call(out), "events for #{name}")
    assert(!out.include?('NEVER'.b), "NEVER output for #{name}", out)
    assert_equal(name == 'setup_soft', out.include?('SOFT CONTINUED'.b),
                 "soft continuation for #{name}")
    summary = name == 'pass' ? 'Cases: 3 passed, 0 failed' : 'Cases: 2 passed, 1 failed'
    assert_includes(out, summary.b)
    assert_includes(out, '[setup]'.b) if setup_failed
    if name.include?('body')
      assert(out.include?('[test]'.b) && out.include?('body hard'.b), "body diagnostic for #{name}")
    end
    if name.include?('cleanup')
      assert(out.include?('[cleanup]'.b) && out.include?('cleanup hard'.b),
             "cleanup diagnostic for #{name}")
    end
    if name == 'body_cleanup'
      assert(out.index('[test]'.b) < out.index('[cleanup]'.b))
    end
    if name == 'setup_cleanup'
      assert(out.index('[setup]'.b) < out.index('[cleanup]'.b))
    end
  end

  legacy = (fixtures / 'legacy.goose.data').read_text
  out, = run_case.call(legacy, 0)
  assert_equal(['EVENT CONSTRUCT 1', 'EVENT SETUP', 'EVENT BODY', 'EVENT CLEAN', 'EVENT FREE'],
               events.call(out), 'legacy events')
  assert_includes(out, 'Cases: 2 passed'.b)
  %w[before_each after_each].each do |hook|
    mixed_hooks = legacy.sub("fn #{hook}(f: Fixture&)",
                             "fn #{hook}(t: goosetest::Test&, f: Fixture&)")
    out, = run_case.call(mixed_hooks, 0)
    assert_equal(['EVENT CONSTRUCT 1', 'EVENT SETUP', 'EVENT BODY', 'EVENT CLEAN', 'EVENT FREE'],
                 events.call(out), "mixed hook events for #{hook}")
  end

  # Missing hooks are optional; default fixture state still belongs to this case.
  before_start = legacy.index('fn before_each')
  after_start = legacy.index('fn after_each')
  body_start = legacy.index('fn test_first')
  without_setup = (legacy[0...before_start] + legacy[after_start..])
                  .gsub('t.assert_eq(7, f.value)', 't.assert_eq(5, f.value)')
  out, = run_case.call(without_setup, 0)
  assert_equal(['EVENT CONSTRUCT 1', 'EVENT BODY', 'EVENT CLEAN', 'EVENT FREE'],
               events.call(out), 'without setup events')
  without_cleanup = legacy[0...after_start] + legacy[body_start..]
  out, = run_case.call(without_cleanup, 0)
  assert_equal(['EVENT CONSTRUCT 1', 'EVENT SETUP', 'EVENT BODY', 'EVENT FREE'],
               events.call(out), 'without cleanup events')
  without_hooks = (legacy[0...before_start] + legacy[body_start..])
                  .gsub('t.assert_eq(7, f.value)', 't.assert_eq(5, f.value)')
  out, = run_case.call(without_hooks, 0)
  assert_equal(['EVENT CONSTRUCT 1', 'EVENT BODY', 'EVENT FREE'],
               events.call(out), 'without hooks events')

  # A suite with hooks but only a Test-only case never constructs or calls them.
  start = legacy.index('fn test_first')
  finish = legacy.index('fn test_free')
  free_only = (legacy[0...start] + legacy[finish..])
              .gsub('t.assert_eq(1, constructed)', 't.assert_eq(0, constructed)')
  out, = run_case.call(free_only, 0)
  assert_equal(['EVENT FREE'], events.call(out), 'free-only events')

  # Both valid hook forms in one suite are ambiguous and fail during discovery.
  duplicate = legacy + "\nfn before_each(t: goosetest::Test&, f: Fixture&) {}\n"
  out, err = run_case.call(duplicate, 2)
  assert_equal([], events.call(out), 'duplicate hook events')
  assert((out + err).downcase.include?('duplicate'.b), 'duplicate hook diagnostic', [out, err])

  # Fatal language checks do not unwind into framework cleanup.
  aborting = legacy.sub('t.assert_eq(7, f.value);', 'assert(false);')
  out, err = run_case.call(aborting, 2)
  assert_equal(['EVENT CONSTRUCT 1', 'EVENT SETUP', 'EVENT BODY'], events.call(out),
               'fatal events')
  assert(err.include?('execution'.b) && err.include?('incomplete'.b), 'fatal diagnostic', err)

  # Resource ownership is safe after partial setup and closes an acquired
  # descriptor once after a recoverable body assertion failure.
  (project / 'resource.c').write_text(<<~C)
    #include <fcntl.h>
    #include <stdio.h>
    #include <unistd.h>
    static void record(const char *event, int fd) {
        FILE *log = fopen("resource-events", "a");
        if (!log) _exit(110);
        if (fprintf(log, "%s %d\\n", event, fd) < 0 || fclose(log) != 0) _exit(111);
    }
    int gt_lifecycle_open_resource(void) {
        int fd = open("/dev/null", O_RDONLY);
        if (fd >= 0) record("OPEN", fd);
        return fd;
    }
    int gt_lifecycle_close_resource(int fd) {
        record("CLOSE", fd);
        return close(fd);
    }
  C
  (project / 'goosetest_root.build').write_text('c_sources = ["resource.c"];' + "\n")
  resource_source = <<~GOOSE
    namespace lifecycle_resource_test;
    import goosetest;
    extern "gt_lifecycle_open_resource" fn open_resource() -> i32;
    extern "gt_lifecycle_close_resource" fn close_resource(fd: i32) -> i32;
    var next_id: i32 = 0;
    fn new_id() -> i32 { next_id += 1; return next_id; }
    struct Fixture { fd: i32 = -1, id: i32 = new_id() }
    fn before_each(t: goosetest::Test&, f: Fixture&) {
        if f.id == 1 { t.fail("partial setup"); }
        f.fd = open_resource();
        t.assert_true(f.fd >= 0);
    }
    fn after_each(t: goosetest::Test&, f: Fixture&) {
        if f.fd >= 0 { t.assert_eq(0, close_resource(f.fd)); f.fd = -1; }
    }
    fn test_a_partial_setup(t: goosetest::Test&, f: Fixture&) { print("NEVER PARTIAL BODY"); }
    fn test_b_body_failure(t: goosetest::Test&, f: Fixture&) { t.fail("body failure"); }
  GOOSE
  out, err = run_case.call(resource_source, 1)
  ['[setup]', 'partial setup', '[test]', 'body failure'].each do |value|
    assert_includes(out, value.b, 'missing resource lifecycle phase')
  end
  assert(!out.include?('NEVER PARTIAL BODY'.b))
  resource_events = (project / 'resource-events').read_text.lines.map(&:chomp)
  assert(resource_events.first.start_with?('OPEN '), 'resource was not opened')
  assert_equal(2, resource_events.length, 'unexpected resource event count')
  opened_fd = resource_events.first.split[1]
  assert_equal(["OPEN #{opened_fd}", "CLOSE #{opened_fd}"], resource_events,
               'resource was not closed exactly once')
end
puts 'lifecycle process tests passed'
