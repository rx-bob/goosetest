# frozen_string_literal: true

# Verify selected target inventories, stable IDs, and all-target preflight.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent

def run_fixture(cli, args, cwd, env, status = 0, contains = ''.b)
  result = run_capture([cli, *args], chdir: cwd, env: env, timeout: 180)
  assert(result.status == status, 'unexpected status',
         [args, result.status, result.stdout, result.stderr])
  assert_includes(result.stdout + result.stderr, contains, 'missing output')
  result
end

def suite(namespace, function, assertion = 't.assert_true(true);')
  "namespace #{namespace};\nimport goosetest;\n" \
    "fn #{function}(t: goosetest::Test&) { #{assertion} }\n"
end

def write_entry(path, target)
  (path / "goosetest_#{target}.goose").write_text(
    "import goosetest from \"../goosetest\";\n" \
    "import goosetest_generated.#{target}.runner;\n" \
    "fn main() { exit(goosetest_generated::run_all()); }\n"
  )
end

def artifact_snapshot(directory)
  recursive_paths(directory, '**/*').select(&:file?).each_with_object({}) do |path, result|
    result[path.relative_path_from(Pathname.new(directory)).to_s] =
      [path.read_bytes, path.stat.mtime.to_i * 1_000_000_000 + path.stat.mtime.nsec]
  end
end

Dir.mktmpdir('goosetest-targets-') do |temporary|
  work = Pathname.new(temporary)
  project = work / 'consumer'
  project.mkdir
  (work / 'goosetest').symlink_to(repo)
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)
  config = {
    'version' => 1,
    'targets' => [
      { 'name' => 'http', 'entry' => 'goosetest_http.goose',
        'tests' => [{ 'path' => 'tests/http', 'kind' => 'integration' }] },
      { 'name' => 'database', 'entry' => 'missing_database_entry.goose',
        'tests' => [{ 'path' => 'tests/database', 'kind' => 'integration' }] },
      { 'name' => 'core', 'entry' => 'goosetest_core.goose',
        'tests' => [{ 'path' => 'tests/core', 'kind' => 'unit' }] }
    ]
  }
  (project / 'goosetest.json').write_text(json_dump(config))
  (project / 'tests/core').mkdir(parents: true)
  (project / 'tests/http').mkdir(parents: true)
  (project / 'tests/core/path_test.goose').write_text(suite('shared_test', 'test_route'))
  (project / 'tests/http/path_test.goose').write_text(suite('shared_test', 'test_route'))
  write_entry(project, 'core')
  write_entry(project, 'http')

  # Selected inventory ignores the absent database entry and root.
  core = run_fixture(cli, ['list', '--project', project, '--target', 'core'], work, env)
  assert(core.stdout.start_with?('unit  core::tests/core/path_test.goose::shared_test::test_route'.b))
  assert(!core.stdout.include?('database::'.b))
  assert(!core.stdout.include?('http::'.b))
  core_again = run_fixture(cli, ['list', '--project', project, '--target', 'core'], work, env)
  assert_equal(core.stdout, core_again.stdout, 'selected inventory is not stable')

  # CLI argument order does not control inventory/list ordering or IDs.
  both = run_fixture(cli, ['list', '--project', project, '--target', 'http', '--target', 'core'],
                     work, env)
  assert(both.stdout.index('core::'.b) < both.stdout.index('http::'.b), 'target ordering')
  both_reverse = run_fixture(cli, ['list', '--project', project, '--target', 'core',
                                   '--target', 'http'], work, env)
  assert_equal(both.stdout, both_reverse.stdout, 'selector order changed inventory')
  assert_equal(2, both.stdout.scan('::shared_test::test_route').length, 'duplicate IDs')
  both_run = run_fixture(cli, ['test', '--project', project, '--target', 'http',
                               '--target', 'core'], work, env, 0, '1 passed'.b)
  assert(both_run.stdout.index('PASS core::'.b) < both_run.stdout.index('PASS http::'.b),
         'target execution ordering')

  # Invalid unselected suites and missing entry files stay outside core preflight.
  (project / 'tests/database').mkdir(parents: true)
  (project / 'tests/database/bad_test.goose').write_text('namespace broken; fn test_bad(')
  run_fixture(cli, ['test', '--project', project, '--target', 'core'], work, env, 0,
              '1 passed'.b)
  assert(!(project / 'goosetest_generated/database/tests').exist?)

  # A selected invalid suite prevents every selected listing and all builds.
  (project / 'goosetest_generated').rmtree
  invalid_selected = run_fixture(cli, ['list', '--project', project, '--target', 'core',
                                       '--target', 'database'], work, env, 2,
                                 'tests/database'.b)
  assert(!invalid_selected.stdout.include?('core::'.b))
  assert(!(project / 'goosetest_generated').exist?)

  compiler_called = work / 'compiler-called'
  compiler_spy = work / 'compiler-spy'
  compiler_spy.write_text("#!/bin/sh\nprintf called > '#{compiler_called}'\nexit 87\n")
  compiler_spy.chmod(0o755)
  run_fixture(cli, ['test', '--project', project, '--target', 'core', '--target', 'database',
                    '--compiler', compiler_spy], work, env, 2, 'tests/database'.b)
  assert(!compiler_called.exist?, 'selected-target preflight must finish before compiler spawn')

  # Name validation happens before discovery; unknown, duplicate, and mixed selectors are rejected.
  [['--target', 'unknown'],
   ['--target', 'core', '--target', 'core'],
   ['--target', 'all', '--target', 'core']].each do |selectors|
    failed = run_fixture(cli, ['test', '--project', project, '--compiler', compiler_spy,
                               *selectors], work, env, 2, 'target'.b)
    assert(!(project / 'goosetest_generated').exist?)
    assert(!compiler_called.exist?)
    assert(!failed.stdout.include?('PASS'.b))
  end

  # Make database valid but unmatched; core alone matches the filter and builds once.
  config['targets'][1]['entry'] = 'goosetest_database.goose'
  (project / 'goosetest_database.goose').write_text(
    "import goosetest from \"../goosetest\";\n" \
    "import goosetest_generated.database.runner;\n" \
    "fn main() { exit(goosetest_generated::run_all()); }\n"
  )
  (project / 'tests/database/bad_test.goose').write_text(
    "namespace database_test;\nimport goosetest;\n" \
    "// @Disabled(\"external database is not installed\")\n" \
    'fn test_database(t: goosetest::Test&) { t.fail("must remain skipped"); }' + "\n"
  )
  (project / 'goosetest.json').write_text(json_dump(config))
  all_targets = run_fixture(cli, ['list', '--project', project, '--target', 'all'], work, env)
  assert_includes(all_targets.stdout, 'core::tests/core/path_test.goose'.b)
  assert_includes(all_targets.stdout, 'database::tests/database/bad_test.goose'.b)
  assert_includes(all_targets.stdout, 'http::tests/http/path_test.goose'.b)
  integration_targets = run_fixture(cli, ['list', '--project', project, '--target', 'all',
                                           '--suite', 'integration'], work, env)
  assert(!integration_targets.stdout.include?('core::'.b))
  assert(integration_targets.stdout.include?('database::'.b) &&
         integration_targets.stdout.include?('http::'.b))
  run_fixture(cli, ['check-mirror', '--project', project, '--target', 'core'], work, env, 2,
              'Mirror enforcement is disabled'.b)
  filtered = run_fixture(cli, ['test', '--project', project, '--target', 'database',
                               '--target', 'core', '--filter', 'test_route'], work, env,
                         0, '1 passed'.b)
  assert(filtered.stdout.index('PASS core::'.b) <
         filtered.stdout.index('TARGET database: selection excluded'.b),
         'selection exclusion ordering')
  assert_includes(filtered.stdout, 'TARGET database PROFILE debug: selection excluded'.b)
  assert((project / 'goosetest_generated/core/tests').file?)
  assert(!(project / 'goosetest_generated/database/tests').exist?)

  zero = run_fixture(cli, ['test', '--project', project, '--target', 'database',
                           '--filter', 'no_match'], work, env, 2, 'matched zero cases'.b)
  assert(!(project / 'goosetest_generated/database/tests').exist?)
  disabled = run_fixture(cli, ['test', '--project', project, '--target', 'database',
                               '--filter', '::test_database'], work, env, 0, '1 skipped'.b)
  assert_includes(disabled.stdout,
                  'SKIP database::tests/database/bad_test.goose::database_test::test_database'.b)
  assert_includes(disabled.stdout, 'external database is not installed'.b)
  assert_includes(disabled.stdout,
                  'TARGET database PROFILE debug: skipped (all cases disabled)'.b)
  all_fail_fast = run_fixture(cli, ['test', '--project', project, '--target', 'all',
                                    '--fail-fast'], work, env, 0, 'Aggregate status: 0'.b)
  assert(all_fail_fast.stdout.include?('PASS core::'.b) &&
         all_fail_fast.stdout.include?('PASS http::'.b))

  # The real compiler associates a nested entry with its adjacent sidecar and
  # resolves native source paths from that sidecar's directory.
  nested_compiler_project = work / 'nested compiler sidecar'
  nested_entry_dir = nested_compiler_project / 'targets/core'
  (nested_entry_dir / 'native').mkdir(parents: true)
  nested_entry = nested_entry_dir / 'goosetest_core.goose'
  nested_entry.write_text(
    "import goosetest from \"../../../goosetest\";\n" \
    "extern \"nested_sidecar_value\" fn value() -> i64;\n" \
    "fn main() { if value() != 42 { exit(1); } }\n"
  )
  nested_sidecar = nested_entry_dir / 'goosetest_core.build'
  nested_sidecar.write_text('c_sources = ["native/value.c"];' + "\n")
  nested_source = nested_entry_dir / 'native/value.c'
  nested_source.write_text("int nested_sidecar_value(void) { return 42; }\n")
  nested_entry_bytes = nested_entry.read_bytes
  nested_sidecar_bytes = nested_sidecar.read_bytes
  nested_source_bytes = nested_source.read_bytes
  nested_binary = work / 'nested-sidecar-test'
  nested_build = run_capture(['goose', 'build', nested_entry, '--debug', '-o', nested_binary],
                             chdir: nested_compiler_project, env: env, timeout: 120)
  assert(nested_build.status.zero?, 'nested sidecar build failed',
         [nested_build.stdout, nested_build.stderr])
  run_checked([nested_binary], chdir: nested_compiler_project, env: env, timeout: 30)
  assert_equal(nested_entry_bytes, nested_entry.read_bytes, 'nested entry changed')
  assert_equal(nested_sidecar_bytes, nested_sidecar.read_bytes, 'nested sidecar changed')
  assert_equal(nested_source_bytes, nested_source.read_bytes, 'nested source changed')

  # Per-target sidecars own direct native inputs; symbols stay isolated per executable.
  native_project = work / 'target sidecar consumer'
  native_project.mkdir
  core_dir = native_project / 'targets/core'
  database_dir = native_project / 'targets/database'
  [core_dir / 'native', database_dir / 'native', native_project / 'src/core',
   native_project / 'src/database', native_project / 'tests/core',
   native_project / 'tests/database'].each { |path| path.mkdir(parents: true) }
  config = {
    'version' => 1,
    'targets' => [
      { 'name' => 'core', 'entry' => 'goosetest_core.goose',
        'tests' => [{ 'path' => 'tests/core', 'kind' => 'unit' }] },
      { 'name' => 'database', 'entry' => 'goosetest_database.goose',
        'tests' => [{ 'path' => 'tests/database', 'kind' => 'integration' }] }
    ]
  }
  (native_project / 'goosetest.json').write_text(json_dump(config))
  [[core_dir, 'core'], [database_dir, 'database']].each do |target_dir, target|
    (native_project / "goosetest_#{target}.goose").write_text(
      "import goosetest from \"../goosetest\";\n" \
      "import goosetest_generated.#{target}.runner;\n" \
      "fn main() { exit(goosetest_generated::run_all()); }\n"
    )
    (native_project / "src/#{target}/production.goose").write_text(
      "namespace production;\n" \
      "extern \"shared_target_value\" fn native_value() -> i64;\n" \
      "fn value() -> i64 { return native_value(); }\n"
    )
    target_dir # keep tuple shape explicit
  end
  (core_dir / 'native/shared_symbol.c').write_text(
    "int shared_target_value(void) { return 17; }\n"
  )
  (database_dir / 'native/shared_symbol.c').write_text(
    "extern int database_library_value(void);\n" \
    "int shared_target_value(void) { return database_library_value(); }\n"
  )
  optional_library = database_dir / 'native/unavailable_optional.c'
  optional_library.write_text('/* optional database library is unavailable */' + "\n")
  core_sidecar = native_project / 'goosetest_core.build'
  core_sidecar.write_text('c_sources = ["targets/core/native/shared_symbol.c"];' + "\n")
  database_sidecar = native_project / 'goosetest_database.build'
  database_sidecar.write_text(
    'c_sources = ["targets/database/native/shared_symbol.c", ' \
    '"targets/database/native/unavailable_optional.c"];' + "\n"
  )
  (native_project / 'tests/core/native_test.goose').write_text(
    "namespace native_test;\nimport goosetest;\nimport src.core.production;\n" \
    'fn test_native_value(t: goosetest::Test&) { t.assert_eq(17, production::value()); }' + "\n"
  )
  (native_project / 'tests/database/native_test.goose').write_text(
    "namespace native_test;\nimport goosetest;\nimport src.database.production;\n" \
    'fn test_native_value(t: goosetest::Test&) { t.assert_eq(29, production::value()); }' + "\n"
  )
  core_entry_before = (native_project / 'goosetest_core.goose').read_bytes
  core_sidecar_before = core_sidecar.read_bytes
  database_entry_before = (native_project / 'goosetest_database.goose').read_bytes
  unavailable_sidecar_before = database_sidecar.read_bytes
  core_native_before = (core_dir / 'native/shared_symbol.c').read_bytes
  database_native_before = (database_dir / 'native/shared_symbol.c').read_bytes
  run_fixture(cli, ['test', '--project', native_project, '--target', 'core'], work, env,
              0, '1 passed'.b)
  core_artifacts = native_project / 'goosetest_generated/core'
  core_snapshot = artifact_snapshot(core_artifacts)
  unavailable = run_fixture(cli, ['test', '--project', native_project, '--target', 'database'],
                            work, env, 2, 'compilation for target database'.b)
  assert(!unavailable.stdout.include?('core::'.b))
  assert_equal(core_snapshot, artifact_snapshot(core_artifacts), 'core artifacts changed')
  assert(!(native_project / 'goosetest_generated/database/completion').exist?)
  assert_equal(unavailable_sidecar_before, database_sidecar.read_bytes, 'database sidecar changed')

  optional_library.write_text("int database_library_value(void) { return 29; }\n")
  run_fixture(cli, ['test', '--project', native_project, '--target', 'database'], work, env,
              0, '1 passed'.b)
  database_artifacts = native_project / 'goosetest_generated/database'
  database_snapshot = artifact_snapshot(database_artifacts)
  assert_equal(core_snapshot, artifact_snapshot(core_artifacts), 'core artifacts changed')
  run_fixture(cli, ['test', '--project', native_project, '--target', 'core'], work, env,
              0, '1 passed'.b)
  assert_equal(database_snapshot, artifact_snapshot(database_artifacts),
               'database artifacts changed')
  assert((core_artifacts / 'tests').file?)
  assert_equal("0\n".b, (core_artifacts / 'completion').read_bytes, 'core completion')
  assert_equal(core_entry_before, (native_project / 'goosetest_core.goose').read_bytes,
               'core entry changed')
  assert_equal(core_sidecar_before, core_sidecar.read_bytes, 'core sidecar changed')
  assert_equal(database_entry_before, (native_project / 'goosetest_database.goose').read_bytes,
               'database entry changed')
  assert_equal(unavailable_sidecar_before, database_sidecar.read_bytes,
               'database sidecar changed again')
  assert_equal(database_native_before, (database_dir / 'native/shared_symbol.c').read_bytes,
               'database native source changed')
  assert_equal(core_native_before, (core_dir / 'native/shared_symbol.c').read_bytes,
               'core native source changed')

  # Assertion failures continue by default, compile failures continue only
  # after the compiler child was reaped, and aggregate status 2 dominates 1.
  results_project = work / 'aggregate outcomes'
  results_project.mkdir
  result_names = %w[core database http tail]
  result_config = { 'version' => 1, 'targets' => [] }
  result_names.each do |name|
    (results_project / "tests/#{name}").mkdir(parents: true)
    write_entry(results_project, name)
    result_config['targets'] << {
      'name' => name,
      'entry' => "goosetest_#{name}.goose",
      'tests' => [{ 'path' => "tests/#{name}", 'kind' => 'unit' }]
    }
  end
  (results_project / 'goosetest.json').write_text(json_dump(result_config))
  (results_project / 'tests/core/core_test.goose').write_text(
    suite('core_test', 'test_failure', 't.fail("intentional core failure");')
  )
  (results_project / 'tests/database/database_test.goose').write_text(
    suite('database_test', 'test_success')
  )
  (results_project / 'tests/http/http_test.goose').write_text(suite('http_test', 'test_http'))
  (results_project / 'tests/tail/tail_test.goose').write_text(
    suite('tail_test', 'test_after_compile_failure')
  )
  (results_project / 'goosetest_http.build').write_text('c_sources = ["http.c"];' + "\n")
  (results_project / 'http.c').write_text(
    "extern int missing_http_library(void);\n" \
    "int http_dependency(void) { return missing_http_library(); }\n"
  )
  invocation_log = work / 'compiler-invocations'
  compiler_spy = work / 'compiler-spy'
  compiler_spy.write_text(<<~RUBY)
    #!#{ruby_executable}
    log = #{invocation_log.to_s.dump}
    File.open(log, 'a') { |stream| stream.write(File.basename(ARGV[1]) + "\\n") }
    exec('goose', *ARGV)
  RUBY
  compiler_spy.chmod(0o755)

  default_run = run_fixture(cli, ['test', '--project', results_project, '--compiler', compiler_spy],
                            work, env, 2, 'Aggregate status: 2'.b)
  assert_includes(default_run.stdout, 'TARGET core PROFILE debug: starting'.b)
  assert_includes(default_run.stdout, 'TARGET core PROFILE debug: assertion failure (status 1)'.b)
  assert_includes(default_run.stdout, 'TARGET database PROFILE debug: passed (status 0)'.b)
  assert_includes(default_run.stdout, 'TARGET http PROFILE debug: incomplete (status 2)'.b)
  assert_includes(default_run.stdout, 'TARGET tail PROFILE debug: passed (status 0)'.b)
  assert_equal(%w[goosetest_core.goose goosetest_database.goose goosetest_http.goose
                  goosetest_tail.goose], invocation_log.read_text.lines.map(&:chomp),
               'default compiler invocations')

  invocation_log.unlink
  fail_fast = run_fixture(cli, ['test', '--project', results_project, '--compiler', compiler_spy,
                                '--fail-fast'], work, env, 1, 'Aggregate status: 1'.b)
  assert_equal(['goosetest_core.goose'], invocation_log.read_text.lines.map(&:chomp),
               'fail-fast compiler invocations')
  assert_includes(fail_fast.stdout, 'TARGET database PROFILE debug: NOT RUN'.b)
  assert_includes(fail_fast.stdout, 'TARGET http PROFILE debug: NOT RUN'.b)
  assert_includes(fail_fast.stdout, 'TARGET tail PROFILE debug: NOT RUN'.b)

  invocation_log.unlink
  compile_then_pass = run_fixture(cli, ['test', '--project', results_project, '--compiler',
                                        compiler_spy, '--target', 'http', '--target', 'tail'],
                                  work, env, 2, 'Aggregate status: 2'.b)
  assert_equal(%w[goosetest_http.goose goosetest_tail.goose],
               invocation_log.read_text.lines.map(&:chomp), 'compile-failure invocations')
  assert_includes(compile_then_pass.stdout, 'TARGET tail PROFILE debug: passed (status 0)'.b)

  # Each target gets a fresh child and native globals, including after abort().
  isolation = work / 'native state isolation'
  isolation.mkdir
  isolation_names = %w[core database fatal tail]
  isolation_config = { 'version' => 1, 'targets' => [] }
  fixture = Pathname.new(__dir__) / 'process_fixture.c'
  copy_file(fixture, isolation / 'process_fixture.c')
  isolation_names.each do |name|
    (isolation / "tests/#{name}").mkdir(parents: true)
    write_entry(isolation, name)
    (isolation / "goosetest_#{name}.build").write_text('c_sources = ["process_fixture.c"];' + "\n")
    isolation_config['targets'] << {
      'name' => name,
      'entry' => "goosetest_#{name}.goose",
      'tests' => [{ 'path' => "tests/#{name}", 'kind' => 'unit' }]
    }
    body = case name
           when 'fatal' then 'assert(fixture_next() == 1); fixture_abort();'
           when 'tail' then 'assert(fixture_next() == 1); assert(fixture_descendant_stopped() == 1);'
           else 'assert(fixture_next() == 1);'
           end
    (isolation / "tests/#{name}/#{name}_test.goose").write_text(
      "namespace #{name}_test;\nimport goosetest;\n" \
      "extern \"goosetest_fixture_next\" fn fixture_next() -> i32;\n" \
      "extern \"goosetest_fixture_abort\" fn fixture_abort();\n" \
      "extern \"goosetest_fixture_descendant_stopped\" fn fixture_descendant_stopped() -> i32;\n" \
      "fn test_native_state(t: goosetest::Test&) { #{body} }\n"
    )
  end
  (isolation / 'goosetest.json').write_text(json_dump(isolation_config))
  observations = isolation / 'process-observations'
  isolated_run = run_fixture(cli, ['test', '--project', isolation], work, env, 2,
                             'TARGET tail PROFILE debug: passed (status 0)'.b)
  assert_includes(isolated_run.stdout, 'TARGET fatal PROFILE debug: incomplete (status 2)'.b)
  observed = observations.read_text.lines.map(&:split)
  assert(observed.length == 4 && observed.all? { |_, value| value == '1' }, 'native state', observed)
  assert_equal(4, observed.map(&:first).uniq.length, 'native state reused a child')

  observations.unlink
  fatal_fail_fast = run_fixture(cli, ['test', '--project', isolation, '--fail-fast'],
                                work, env, 2, 'Aggregate status: 2'.b)
  assert(observations.read_text.lines.length == 3, 'fail-fast native observations')
  assert_includes(fatal_fail_fast.stdout, 'TARGET tail PROFILE debug: NOT RUN'.b)

  # Stale success is reset before explicit exit(0)/exit(1), and malformed
  # completion evidence is rejected even when the generated runner passed.
  evidence = work / 'completion evidence'
  evidence.mkdir
  (evidence / 'tests/case').mkdir(parents: true)
  write_entry(evidence, 'evidence')
  (evidence / 'tests/case/evidence_test.goose').write_text(
    suite('evidence_test', 'test_valid_completion')
  )
  (evidence / 'goosetest.json').write_text(json_dump(
    'version' => 1,
    'targets' => [{
      'name' => 'evidence', 'entry' => 'goosetest_evidence.goose',
      'tests' => [{ 'path' => 'tests/case', 'kind' => 'unit' }]
    }]
  ))
  run_fixture(cli, ['test', '--project', evidence], work, env, 0,
              'TARGET evidence PROFILE debug: passed (status 0)'.b)
  assert_equal("0\n".b, (evidence / 'goosetest_generated/evidence/completion').read_bytes,
               'evidence completion')
  evidence_entry = evidence / 'goosetest_evidence.goose'
  [0, 1].each do |code|
    evidence_entry.write_text("fn main() { exit(#{code}); }\n")
    early_exit = run_fixture(cli, ['test', '--project', evidence], work, env, 2,
                             'completion record'.b)
    assert_includes(early_exit.stdout, 'TARGET evidence PROFILE debug: incomplete (status 2)'.b)
    assert(!early_exit.stdout.include?('TARGET evidence PROFILE debug: passed'.b))
    assert(!(evidence / 'goosetest_generated/evidence/completion').exist?)
  end

  evidence_entry.write_text(
    "import goosetest from \"../goosetest\";\n" \
    "import goosetest_generated.evidence.runner;\n" \
    "extern \"goosetest_fixture_corrupt_completion\" fn corrupt_completion();\n" \
    "fn main() { let status = goosetest_generated::run_all(); " \
    "corrupt_completion(); exit(status); }\n"
  )
  (evidence / 'process_fixture.c').write_bytes(fixture.read_bytes)
  (evidence / 'goosetest_evidence.build').write_text('c_sources = ["process_fixture.c"];' + "\n")
  malformed_env = env.merge(
    'GOOSETEST_COMPLETION_PATH' => (evidence / 'goosetest_generated/evidence/completion').to_s
  )
  malformed = run_fixture(cli, ['test', '--project', evidence], work, malformed_env, 2,
                          'completion record'.b)
  assert_includes(malformed.stdout, 'TARGET evidence PROFILE debug: incomplete (status 2)'.b)
  assert_equal("bad\n".b, (evidence / 'goosetest_generated/evidence/completion').read_bytes,
               'malformed completion retained')

  # A run deadline must release a descendant-owned listening socket before
  # the next target begins and default mode must continue to that target.
  timeout_project = work / 'target timeout socket'
  timeout_project.mkdir
  copy_file(fixture, timeout_project / 'process_fixture.c')
  timeout_config = { 'version' => 1, 'targets' => [] }
  %w[alpha beta].each do |name|
    (timeout_project / "tests/#{name}").mkdir(parents: true)
    write_entry(timeout_project, name)
    (timeout_project / "goosetest_#{name}.build").write_text(
      'c_sources = ["process_fixture.c"];' + "\n"
    )
    timeout_config['targets'] << {
      'name' => name,
      'entry' => "goosetest_#{name}.goose",
      'tests' => [{ 'path' => "tests/#{name}", 'kind' => 'unit' }]
    }
  end
  (timeout_project / 'goosetest.json').write_text(json_dump(timeout_config))
  (timeout_project / 'tests/alpha/alpha_test.goose').write_text(
    "namespace alpha_test;\nimport goosetest;\n" \
    "extern \"goosetest_fixture_socket_wait\" fn socket_wait();\n" \
    'fn test_socket_owner(t: goosetest::Test&) { socket_wait(); }' + "\n"
  )
  (timeout_project / 'tests/beta/beta_test.goose').write_text(
    "namespace beta_test;\nimport goosetest;\n" \
    "extern \"goosetest_fixture_rebind_socket\" fn rebind_socket() -> i32;\n" \
    'fn test_socket_released(t: goosetest::Test&) { t.assert_eq(1, rebind_socket()); }' + "\n"
  )
  timed_out = run_fixture(cli, ['test', '--project', timeout_project,
                                '--run-timeout-seconds', '1'], work, env, 2,
                          'TARGET beta PROFILE debug: passed (status 0)'.b)
  assert_includes(timed_out.stdout, 'TARGET alpha PROFILE debug: incomplete (status 2)'.b)
  timeout_pids = (timeout_project / 'owned-pids').read_text.split.map(&:to_i)
  FixtureSupport.wait_tree_stopped(timeout_pids)

  # Interrupt both the first and a later selected target with SIGINT/SIGTERM.
  # The cancelled invocation must skip gamma and release the lock for reuse.
  cancel_project = work / 'target cancellation'
  cancel_project.mkdir
  copy_file(fixture, cancel_project / 'process_fixture.c')
  cancel_config = { 'version' => 1, 'targets' => [] }
  %w[alpha beta gamma].each do |name|
    (cancel_project / "tests/#{name}").mkdir(parents: true)
    write_entry(cancel_project, name)
    cancel_config['targets'] << {
      'name' => name,
      'entry' => "goosetest_#{name}.goose",
      'tests' => [{ 'path' => "tests/#{name}", 'kind' => 'unit' }]
    }
  end
  (cancel_project / 'goosetest.json').write_text(json_dump(cancel_config))
  (cancel_project / 'tests/alpha/alpha_test.goose').write_text(
    suite('alpha_test', 'test_before_cancel')
  )
  (cancel_project / 'goosetest_beta.build').write_text('c_sources = ["process_fixture.c"];' + "\n")
  (cancel_project / 'tests/beta/beta_test.goose').write_text(
    "namespace beta_test;\nimport goosetest;\n" \
    "extern \"goosetest_fixture_socket_wait\" fn socket_wait();\n" \
    'fn test_wait_for_cancellation(t: goosetest::Test&) { socket_wait(); }' + "\n"
  )
  (cancel_project / 'tests/gamma/gamma_test.goose').write_text(
    "namespace gamma_test;\nimport goosetest;\nimport os;\n" \
    'fn test_must_not_run(t: goosetest::Test&) { t.assert_true(write_file("gamma-ran", "yes")); }' + "\n"
  )

  [true, false].each do |selected_first|
    [Signal.list.fetch('INT'), Signal.list.fetch('TERM')].each do |cancel_signal|
      (cancel_project / 'gamma-ran').unlink(missing_ok: true)
      (cancel_project / 'owned-pids').unlink(missing_ok: true)
      (cancel_project / 'owned-port').unlink(missing_ok: true)
      selectors = selected_first ? ['--target', 'beta', '--target', 'gamma'] : []
      command = [cli, 'test', '--project', cancel_project, '--run-timeout-seconds', '30',
                 *selectors]
      running = FixtureSupport::OwnedProcess.new(command, chdir: work, env: env)
      begin
        ready_by = FixtureSupport.monotonic + 40
        until (cancel_project / 'owned-pids').exist?
          assert(running.poll.nil?, 'target exited before readiness', running.read_out)
          assert(FixtureSupport.monotonic < ready_by, 'target process tree did not become ready')
          sleep 0.02
        end
        cancelled_pids = (cancel_project / 'owned-pids').read_text.split.map(&:to_i)
        running.signal(cancel_signal)
        stdout, stderr = running.communicate(timeout: 20)
        expected = 128 + cancel_signal
        assert_equal(expected, running.returncode, 'cancellation status')
        assert_includes(stdout, "Aggregate status: #{expected}".b)
        assert(stderr.include?("signal=#{cancel_signal}".b) && stderr.include?('run incomplete'.b),
               'cancellation diagnostics', stderr)
        assert_includes(stdout, 'TARGET beta PROFILE debug: cancelled'.b)
        assert_includes(stdout, 'TARGET gamma PROFILE debug: NOT RUN'.b)
        assert_includes(stdout, 'TARGET alpha PROFILE debug: passed'.b) unless selected_first
        assert(!(cancel_project / 'gamma-ran').exist?)
        FixtureSupport.wait_tree_stopped(cancelled_pids)
      ensure
        if running.poll.nil?
          running.kill
          running.communicate(timeout: 5)
        end
        running.close
      end

      # A fresh command proves cancellation closed the project lock.
      reacquired = run_fixture(cli, ['test', '--project', cancel_project, '--target', 'gamma'],
                               work, env, 0,
                               'TARGET gamma PROFILE debug: passed (status 0)'.b)
      assert_includes(reacquired.stdout, '1 passed'.b)
      assert_equal('yes', (cancel_project / 'gamma-ran').read_text)
    end
  end
end
puts 'target selection and preflight tests passed'
