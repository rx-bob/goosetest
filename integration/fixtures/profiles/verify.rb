# frozen_string_literal: true

# Independent profile argv, child-environment, and native-cache oracle.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent
real_goose = which('goose') or raise FixtureSupport::Failure, 'goose not found'
CALLER_HOME = '/caller Goose cache ;$(literal)'

def run_fixture(cli, args, cwd, env, status = 0)
  result = run_capture([cli, *args], chdir: cwd, env: env, timeout: 240)
  assert(result.status == status, 'unexpected status',
         [args, result.status, result.stdout, result.stderr])
  result
end

def make_project(path, package_link, configured = false)
  test_root = configured ? 'tests' : 'test'
  path.mkdir(parents: true)
  (path / 'src').mkdir
  (path / test_root).mkdir
  (path / 'native').mkdir
  (path / 'native/profile.c').write_text(
    "#include <stdlib.h>\n#include <string.h>\n" \
    "int gt_profile_mode(void) {\n#ifdef __OPTIMIZE__\nreturn 1;\n#else\nreturn 0;\n#endif\n}\n" \
    "int gt_parent_home_matches(void) { const char *v = getenv(\"GOOSE_HOME\"); " \
    "return v && !strcmp(v, #{JSON.generate(CALLER_HOME)}); }\n" \
    "int gt_parent_home_empty(void) { const char *v = getenv(\"GOOSE_HOME\"); return !v || !*v; }\n"
  )
  (path / 'src/value.goose').write_text(
    "namespace value;\nfn answer() -> i64 { return 42; }\n"
  )
  if configured
    entry = 'goosetest_core.goose'
    generated_import = 'goosetest_generated.core.runner'
    (path / 'goosetest.json').write_text(json_dump(
      'version' => 1,
      'targets' => [{ 'name' => 'core', 'entry' => entry,
                      'tests' => [{ 'path' => test_root, 'kind' => 'unit' }] }]
    ))
  else
    entry = 'goosetest_root.goose'
    generated_import = 'goosetest_generated.runner'
  end
  root = "import goosetest from \"#{package_link}\";\nimport #{generated_import};\n" \
         "fn main() { exit(goosetest_generated::run_all()); }\n"
  (path / entry).write_text(root)
  (path / (entry.delete_suffix('.goose') + '.build')).write_text(
    'c_sources = ["native/profile.c"];' + "\n"
  )
  [entry, test_root]
end

def write_case(project, test_root, expected_mode, empty_home = false)
  home_assertion = if empty_home
                     't.assert_true(gt_parent_home_empty());'
                   else
                     't.assert_true(gt_parent_home_matches());'
                   end
  (project / test_root / 'value_test.goose').write_text(
    "namespace value_test;\nimport goosetest;\nimport src.value;\n" \
    "extern \"gt_profile_mode\" fn profile_mode() -> i64;\n" \
    "extern \"gt_parent_home_matches\" fn gt_parent_home_matches() -> bool;\n" \
    "extern \"gt_parent_home_empty\" fn gt_parent_home_empty() -> bool;\n" \
    "fn test_profile(t: goosetest::Test&) {\n" \
    "    t.assert_eq(#{expected_mode}, profile_mode());\n" \
    "    #{home_assertion}\n" \
    "    t.assert_eq(42, value::answer());\n}\n"
  )
end

def write_recovery_cases(project, expected_mode)
  (project / 'test/value_test.goose').write_text(<<~GOOSE)
    namespace value_test;
    import goosetest;
    import src.value;
    extern "gt_profile_mode" fn profile_mode() -> i64;
    extern "gt_parent_home_matches" fn gt_parent_home_matches() -> bool;
    struct Fixture { acquired: bool = false }
    var next_case: i64 = 0;
    var cleanup_count: i64 = 0;
    fn before_each(t: goosetest::Test&, f: Fixture&) {
        next_case += 1;
        if next_case == 1 { print("EVENT BEFORE A"); }
        else if next_case == 2 { print("EVENT BEFORE B"); }
        else if next_case == 3 { f.acquired = true; print("EVENT ACQUIRE C"); }
        else { print("EVENT BEFORE D"); }
    }
    fn after_each(t: goosetest::Test&, f: Fixture&) {
        if f.acquired { cleanup_count += 1; f.acquired = false; print("EVENT CLEANUP C"); }
        else if next_case == 1 { print("EVENT AFTER A"); }
        else if next_case == 2 { print("EVENT AFTER B"); }
        else { print("EVENT AFTER D"); }
    }
    fn test_case_a(t: goosetest::Test&, f: Fixture&) {
        t.assert_eq(4, 2 + 2);
        t.assert_eq(#{expected_mode}, profile_mode());
        t.assert_true(gt_parent_home_matches());
        t.assert_eq(42, value::answer());
    }
    fn test_case_b(t: goosetest::Test&, f: Fixture&) {
        t.check_eq(99, 4, "soft check failure");
        print("EVENT SOFT CONTINUES");
        t.assert_eq(5, 2 + 2, "case_b hard failure");
        print("NEVER CASE B");
    }
    fn test_case_c(t: goosetest::Test&, f: Fixture&) {
        print("EVENT BODY C");
        t.fail("case_c body failure");
        print("NEVER CASE C");
    }
    fn test_case_d(t: goosetest::Test&, f: Fixture&) {
        print("EVENT BODY D");
        t.assert_eq(1, cleanup_count);
    }
  GOOSE
  (project / 'test/disabled_test.goose').write_text(<<~GOOSE)
    namespace disabled_test;
    import goosetest;
    fn before_all() { print("NEVER DISABLED SUITE SETUP"); }
    fn after_all() { print("NEVER DISABLED SUITE CLEANUP"); }
    // @Disabled("profile disabled fixture")
    fn test_disabled(t: goosetest::Test&) { print("NEVER DISABLED BODY"); t.fail("disabled"); }
  GOOSE
end

def compiler_record(log, label)
  value = JSON.parse(log.read_text)
  assert_equal(label, value['argv'], 'compiler argv')
  assert(!value['home'].nil?, 'missing compiler home', value)
  value
end

Dir.mktmpdir('goosetest-profile-') do |temporary|
  work = Pathname.new(temporary).realpath
  (work / 'package').symlink_to(repo)
  project = work / 'consumer space ;$(literal)'
  entry, test_root = make_project(project, '../package')
  log = work / 'compiler.json'
  compiler = project / 'goose-profile-proxy'
  compiler.write_text(<<~RUBY)
    #!#{ruby_executable}
    require 'json'
    log = #{log.to_s.dump}
    File.write(log, JSON.generate({'argv' => ARGV, 'home' => ENV['GOOSE_HOME'], 'path' => ENV['PATH']}))
    exec(#{real_goose.dump}, *ARGV)
  RUBY
  compiler.chmod(0o700)
  env = environment('GOOSE_HOME' => CALLER_HOME)
  absolute_cache = work / 'explicit cache ;$(literal)'
  output = './goosetest_generated/tests'
  write_case(project, test_root, 0)

  # Read-only discovery does not create the default compiler cache.
  run_fixture(cli, ['list', '--project', project], work, env)
  assert(!(project / 'goosetest_generated/cache').exist?)
  run_fixture(cli, ['check-mirror', '--project', project], work, env)
  assert(!(project / 'goosetest_generated/cache').exist?)

  # The same sidecar source compiles under both profiles in distinct GOOSE_HOME trees.
  [['debug', 0], ['optimized', 1]].each do |profile, mode|
    write_case(project, test_root, mode)
    argv = if profile == 'debug'
             ['build', entry, '-O0', '--debug', '--offline', '-o', output]
           else
             ['build', entry, '-O2', '--offline', '-o', output]
           end
    run_fixture(cli, ['test', '--project', project, '--profile', profile, '--offline',
                      '--cache-root', absolute_cache, '--compiler', compiler], work, env)
    record = compiler_record(log, argv)
    assert_equal((absolute_cache / 'default' / profile).to_s, record['home'],
                 'profile cache home')
    assert_equal(env['PATH'], record['path'], 'compiler PATH')
    assert((absolute_cache / 'default' / profile).directory?)
  end

  # The default cache lives under the generated root but outside its source manifest.
  write_case(project, test_root, 0)
  run_fixture(cli, ['test', '--project', project, '--compiler', compiler], work, env)
  default_cache = project / 'goosetest_generated/cache/default/debug'
  record = compiler_record(log, ['build', entry, '-O0', '--debug', '-o', output])
  assert_equal('./goosetest_generated/cache/default/debug', record['home'], 'default cache home')
  assert(default_cache.directory?)
  run_fixture(cli, ['list', '--project', project], work, env)
  assert(default_cache.directory?)
  (default_cache / 'owned-by-compiler-cache').write_text('keep')
  write_case(project, test_root, 0)
  run_fixture(cli, ['test', '--project', project, '--compiler', compiler], work, env)
  record = compiler_record(log, ['build', entry, '-O0', '--debug', '-o', output])
  assert_equal('./goosetest_generated/cache/default/debug', record['home'])
  assert_equal('keep', (default_cache / 'owned-by-compiler-cache').read_text)

  # Relative roots resolve from the project, and bare compiler names still use PATH.
  relative_root = 'relative cache ;$(literal)'
  project_env = env.merge('PATH' => project.to_s + File::PATH_SEPARATOR + env['PATH'])
  write_case(project, test_root, 0)
  run_fixture(cli, ['test', '--project', project, '--cache-root', relative_root,
                    '--compiler', compiler.basename], work, project_env)
  record = compiler_record(log, ['build', entry, '-O0', '--debug', '-o', output])
  assert_equal('./' + relative_root + '/default/debug', record['home'], 'relative cache home')
  assert_equal(project_env['PATH'], record['path'], 'relative compiler PATH')
  assert((project / relative_root / 'default' / 'debug').directory?)

  # The launched test executable keeps the caller's absent or empty value.
  [nil, ''].each do |inherited|
    write_case(project, test_root, 0, true)
    child_env = env.dup
    if inherited.nil?
      child_env.delete('GOOSE_HOME')
    else
      child_env['GOOSE_HOME'] = inherited
    end
    run_fixture(cli, ['test', '--project', project, '--profile', 'debug',
                      '--cache-root', absolute_cache, '--compiler', compiler], work, child_env)
    record = compiler_record(log, ['build', entry, '-O0', '--debug', '-o', output])
    assert_equal((absolute_cache / 'default' / 'debug').to_s, record['home'],
                 'inherited home cache')
  end

  # Configured target key is separate from legacy default, even with the same root/profile.
  configured = work / 'configured core'
  core_entry, core_tests = make_project(configured, '../package', true)
  write_case(configured, core_tests, 0)
  configured_cache = work / 'shared cache'
  run_fixture(cli, ['list', '--project', configured], work, env)
  assert(!configured_cache.exist?)
  disabled = run_fixture(cli, ['check-mirror', '--project', configured], work, env, 2)
  assert_includes(disabled.stderr, 'disabled'.b)
  assert(!configured_cache.exist?)
  run_fixture(cli, ['test', '--project', configured, '--cache-root', configured_cache,
                    '--compiler', compiler], work, env)
  core_output = './goosetest_generated/core/tests'
  record = compiler_record(log, ['build', core_entry, '-O0', '--debug', '-o', core_output])
  assert_equal((configured_cache / 'core' / 'debug').to_s, record['home'], 'configured cache home')
  assert((configured_cache / 'core' / 'debug').directory?)
  assert(!(configured_cache / 'default').exist?)

  # Cache directories are compiler-owned: source regeneration never prunes them.
  core_sentinel = configured_cache / 'core' / 'debug' / 'must-survive'
  core_sentinel.write_text('keep')
  write_case(configured, core_tests, 0)
  run_fixture(cli, ['test', '--project', configured, '--cache-root', configured_cache,
                    '--compiler', compiler], work, env)
  assert_equal('keep', core_sentinel.read_text)

  # Offline compilation failure cannot execute or leave the previous test binary.
  binary = configured / 'goosetest_generated/core/tests'
  assert(binary.exist?)
  (configured / core_entry).write_text(
    "import not_a_real_offline_dependency;\n" \
    "import goosetest_generated.core.runner;\n" \
    "fn main() { exit(goosetest_generated::run_all()); }\n"
  )
  failed = run_fixture(cli, ['test', '--project', configured, '--offline',
                             '--cache-root', configured_cache, '--compiler', compiler],
                       work, env, 2)
  assert_includes(failed.stderr, 'compilation'.b)
  assert(!binary.exist?, 'failed offline compilation left a stale test executable')

  # The same recovery and hook contract must hold in debug and optimized C builds.
  recovery = work / 'recovery consumer'
  recovery_entry, recovery_tests = make_project(recovery, '../package')
  (recovery / 'src/disabled.goose').write_text("namespace disabled;\n")
  write_recovery_cases(recovery, 0)
  recovery_cache = work / 'recovery compiler cache'
  recovery_output = './goosetest_generated/tests'
  case_ids = {
    'test/value_test.goose::value_test::test_case_a' => 'PASS',
    'test/value_test.goose::value_test::test_case_b' => 'FAIL',
    'test/value_test.goose::value_test::test_case_c' => 'FAIL',
    'test/value_test.goose::value_test::test_case_d' => 'PASS',
    'test/disabled_test.goose::disabled_test::test_disabled' => 'SKIP'
  }
  [['debug', 0, '-O0', '--debug'], ['optimized', 1, '-O2', nil]].each do |profile, mode, optimize, debug|
    write_recovery_cases(recovery, mode)
    expected_argv = ['build', recovery_entry, optimize]
    expected_argv << debug unless debug.nil?
    expected_argv += ['-o', recovery_output]
    result = run_fixture(cli, ['test', '--project', recovery, '--profile', profile,
                               '--cache-root', recovery_cache, '--compiler', compiler],
                         work, env, 1)
    record = compiler_record(log, expected_argv)
    assert_equal((recovery_cache / 'default' / profile).to_s, record['home'],
                 'recovery cache home')
    reports = {}
    result.stdout.scan(/^(PASS|FAIL|SKIP|NOT RUN|ERROR) ([^ ]+) /).each do |status, identity|
      reports[identity.force_encoding('UTF-8')] = status
    end
    assert_equal(case_ids, reports, "recovery reports #{profile}")
    events = result.stdout.lines.map(&:chomp).select { |line| line.start_with?('EVENT ') }
    assert_equal(['EVENT BEFORE A', 'EVENT AFTER A', 'EVENT BEFORE B',
                  'EVENT SOFT CONTINUES', 'EVENT AFTER B', 'EVENT ACQUIRE C',
                  'EVENT BODY C', 'EVENT CLEANUP C', 'EVENT BEFORE D',
                  'EVENT BODY D', 'EVENT AFTER D'], events, "recovery events #{profile}")
    assert(result.stdout.include?('soft check failure'.b) &&
           result.stdout.include?('case_b hard failure'.b))
    assert_includes(result.stdout, 'case_c body failure'.b)
    assert(result.stdout.include?('expected: <5>'.b) && result.stdout.include?('actual: <4>'.b))
    assert(!result.stdout.include?('NEVER CASE B'.b) && !result.stdout.include?('NEVER CASE C'.b))
    assert(!result.stdout.include?('NEVER DISABLED'.b))
    assert_includes(result.stdout, 'Cases: 2 passed, 2 failed, 1 skipped, 0 errors, 0 not run'.b)

    fail_fast = run_fixture(cli, ['test', '--project', recovery, '--profile', profile,
                                  '--cache-root', recovery_cache, '--compiler', compiler,
                                  '--fail-fast'], work, env, 1)
    compiler_record(log, expected_argv)
    stopped_reports = {}
    fail_fast.stdout.scan(/^(PASS|FAIL|SKIP|NOT RUN|ERROR) ([^ ]+) /).each do |status, identity|
      stopped_reports[identity.force_encoding('UTF-8')] = status
    end
    assert_equal('PASS', stopped_reports['test/value_test.goose::value_test::test_case_a'])
    assert_equal('FAIL', stopped_reports['test/value_test.goose::value_test::test_case_b'])
    assert_equal('NOT RUN', stopped_reports['test/value_test.goose::value_test::test_case_c'])
    assert_equal('NOT RUN', stopped_reports['test/value_test.goose::value_test::test_case_d'])
    assert_equal('SKIP', stopped_reports['test/disabled_test.goose::disabled_test::test_disabled'])
    stopped_events = fail_fast.stdout.lines.map(&:chomp).select { |line| line.start_with?('EVENT ') }
    assert_equal(['EVENT BEFORE A', 'EVENT AFTER A', 'EVENT BEFORE B',
                  'EVENT SOFT CONTINUES', 'EVENT AFTER B'], stopped_events,
                 "fail-fast events #{profile}")
    disabled_only = run_fixture(cli, ['test', '--project', recovery, '--profile', profile,
                                      '--cache-root', recovery_cache, '--compiler', compiler,
                                      '--filter', '::test_disabled'], work, env)
    compiler_record(log, expected_argv)
    assert_includes(disabled_only.stdout, '0 passed, 0 failed, 1 skipped'.b)
    assert(!disabled_only.stdout.include?('NEVER DISABLED'.b))
    assert(disabled_only.stdout.lines.none? { |line| line.start_with?('EVENT ') })
  end

  fatal = work / 'fatal recovery consumer'
  fatal_entry, fatal_tests = make_project(fatal, '../package')
  write_case(fatal, fatal_tests, 0)
  (fatal / fatal_tests / 'value_test.goose').write_text(
    "namespace value_test;\nimport goosetest;\n" \
    'fn test_fatal(t: goosetest::Test&) { assert(false); }' + "\n"
  )
  fatal_cache = work / 'fatal compiler cache'
  fatal_binary = fatal / 'goosetest_generated/tests'
  fatal_completion = fatal / 'goosetest_generated/completion'
  [['debug', '-O0', '--debug'], ['optimized', '-O2', nil]].each do |profile, optimize, debug|
    fatal_argv = ['build', fatal_entry, optimize]
    fatal_argv << debug unless debug.nil?
    fatal_argv += ['-o', recovery_output]
    result = run_fixture(cli, ['test', '--project', fatal, '--profile', profile,
                               '--cache-root', fatal_cache, '--compiler', compiler],
                         work, env, 2)
    compiler_record(log, fatal_argv)
    assert(result.stderr.include?('execution'.b) && result.stderr.include?('incomplete'.b))
    assert(!result.stdout.match(/^(?:PASS|FAIL) /m), 'fatal run reported a case', result.stdout)
    assert(fatal_binary.exist?)
    assert(!fatal_completion.exist?)
  end

  version = run_capture(['goose', 'version'], timeout: 15)
  assert_equal(0, version.status, 'goose version')
  puts "profile recovery/cache tests passed with #{version.stdout.strip} on " \
       "#{RbConfig::CONFIG['host_os']} #{RbConfig::CONFIG['host_cpu']}"
end
