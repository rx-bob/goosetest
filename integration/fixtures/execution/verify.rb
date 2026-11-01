# frozen_string_literal: true

# External shell-status oracle for the one-command execution pipeline.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent

Dir.mktmpdir('goosetest-execution-') do |temporary|
  work = Pathname.new(temporary)
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)

  project = lambda do |name, body = 't.assert_true(true);', second = ''|
    root = work / "#{name} with spaces"
    (root / 'src').mkdir(parents: true)
    (root / 'test').mkdir
    (root / 'src/a.goose').write_text("namespace a;\n")
    (root / 'test/a_test.goose').write_text(
      "namespace a_test;\nimport goosetest;\nimport os;\n" \
      "fn test_first(t: goosetest::Test&) { #{body} }\n#{second}"
    )
    (root / 'goosetest_root.goose').write_text(
      "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
      "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
    )
    root
  end

  run_case = lambda do |root, status, contains = ''.b, extra = []|
    result = run_capture([cli, 'test', '--project', root, *extra],
                         chdir: work, env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [root.basename.to_s, result.status, result.stdout, result.stderr])
    assert_includes(result.stdout + result.stderr, contains, 'missing output')
    result
  end

  good = project.call('passing',
                      'var value: u8[>..] = []; ' \
                      't.assert_true(read_file("resource", value)); ' \
                      't.assert_eq("hello", value);')
  (good / 'resource').write_text('hello')
  run_case.call(good, 0, '1 passed'.b)

  # Broken new source must remove the previous executable before compilation.
  (good / 'test/a_test.goose').write_text(
    'namespace a_test;' + "\n" +
    'fn test_broken(t: goosetest::Test&) { missing(); }'
  )
  run_case.call(good, 2, 'compilation'.b)
  assert(!(good / 'goosetest_generated/tests').exist?)

  failed = project.call('assertion', 't.assert_eq(1, 2); print("NEVER");',
                        'fn test_second(t: goosetest::Test&) { print("FOLLOWING"); }' + "\n")
  result = run_case.call(failed, 1, 'FOLLOWING'.b)
  assert(!result.stdout.include?('NEVER'.b), 'failing body continued')
  run_case.call(project.call('compile', 'unknown_function();'), 2, 'compilation'.b)

  %w[debug optimized].each do |profile|
    run_case.call(project.call("abort #{profile}", 'assert(false);'), 2, 'execution'.b,
                  ['--profile', profile])
    [0, 1, 7].each do |code|
      run_case.call(project.call("exit#{code} #{profile}", "exit(#{code});"), 2, 'incomplete'.b,
                    ['--profile', profile])
    end
  end

  bad = project.call('audit')
  (bad / 'src/missing.goose').write_text("namespace missing;\n")
  run_case.call(bad, 2, 'no tests executed'.b)
  assert(!(bad / 'goosetest_generated').exist?)

  empty = project.call('empty')
  (empty / 'test/a_test.goose').unlink
  (empty / 'src/a.goose').unlink
  run_case.call(empty, 2, 'no tests executed'.b)

  oversized = project.call('generation')
  text = (oversized / 'test/a_test.goose').read_text.sub(
    'fn test_first', '// @DisplayName("' + ('x' * 1025) + '"' + ")\n" + 'fn test_first'
  )
  (oversized / 'test/a_test.goose').write_text(text)
  run_case.call(oversized, 2, 'generation'.b)
  assert(!(oversized / 'goosetest_generated').exist?)

  %w[debug optimized].each do |profile|
    run_case.call(project.call("missing compiler #{profile}"), 2, 'compilation'.b,
                  ['--profile', profile, '--compiler', work / 'absent'])
  end

  # The compiler and runner each own a separately observed hostile process tree.
  # A finite native alarm also bounds the fixture if both framework and verifier fail.
  fixture = Pathname.new(__dir__) / 'process_tree.c'
  compiler_source = work / 'compiler.c'
  compiler_source.write_text("#include \"#{fixture}\"\n" \
                             "int main(void) { gt_pipeline_wait(); return 0; }\n")
  compiler = work / 'compiler with spaces'
  run_checked(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', compiler_source,
               '-o', compiler], timeout: 30)

  owned_tree = lambda do |root|
    ready = root / 'owned-pids'
    next [] unless ready.exist?

    values = ready.read_text.split
    values.length == 2 ? values.map(&:to_i) : []
  end

  interruption = lambda do |stage, cancel, profile|
    root = project.call(stage + ' ' + profile + (cancel ? ' cancellation' : ' timeout'),
                        't.assert_true(write_file("executed", "fresh"));')
    profile_args = ['--profile', profile]
    # Seed a prior executable; no interruption may execute that stale artifact.
    run_case.call(root, 0, ''.b, profile_args)
    (root / 'executed').unlink
    extra = []
    if stage == 'compilation'
      extra = [*profile_args, '--compiler', compiler, '--compile-timeout-seconds',
               cancel ? '30' : '1']
    else
      copy_file(fixture, root / 'process_tree.c')
      (root / 'goosetest_root.build').write_text('c_sources = ["process_tree.c"];' + "\n")
      (root / 'test/a_test.goose').write_text(
        "namespace a_test;\nimport goosetest;\n" \
        "extern \"gt_pipeline_wait\" fn wait_tree();\n" \
        'fn test_first(t: goosetest::Test&) { wait_tree(); }' + "\n"
      )
      extra = [*profile_args, '--run-timeout-seconds', cancel ? '30' : '1']
    end
    process = FixtureSupport::OwnedProcess.new(
      [cli, 'test', '--project', root, *extra], chdir: work, env: env
    )
    pids = []
    begin
      ready_by = FixtureSupport.monotonic + 20
      while pids.empty?
        pids = owned_tree.call(root)
        assert(process.poll.nil?, 'pipeline exited before readiness', process.read_out)
        assert(FixtureSupport.monotonic < ready_by, 'process tree never became ready')
        sleep 0.02
      end
      process.signal(Signal.list.fetch('INT')) if cancel
      stdout, stderr = process.communicate(timeout: 15)
      assert_equal(cancel ? 130 : 2, process.returncode, 'unexpected cancellation status')
      diagnostic = stage.b + ' for target default' +
                   (cancel ? ' failed;' : ' exceeded its deadline').b
      assert_includes(stderr, diagnostic, 'missing stage diagnostic')
      if cancel
        assert(stderr.include?('signal=2'.b) && stderr.include?('run incomplete'.b),
               'missing cancellation detail', stderr)
      end
      assert(!(root / 'executed').exist?, 'stale executable ran')
      until_at = FixtureSupport.monotonic + 5
      while !pids.each_with_index.all? { |pid, index| stopped?(pid, allow_zombie: index.positive?) } &&
            FixtureSupport.monotonic < until_at
        sleep 0.02
      end
      assert(pids.each_with_index.all? { |pid, index| stopped?(pid, allow_zombie: index.positive?) },
             'owned process survived', pids)
    ensure
      if process.poll.nil?
        process.kill
        process.communicate(timeout: 5)
      end
      process.close
      cleanup = pids.empty? ? owned_tree.call(root) : pids
      cleanup.each do |pid|
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil
        end
      end
    end
    (root / 'test/a_test.goose').write_text(
      "namespace a_test;\nimport goosetest;\nimport os;\n" \
      'fn test_first(t: goosetest::Test&) { t.assert_true(write_file("executed", "fresh")); }' + "\n"
    )
    run_case.call(root, 0, '1 passed'.b, profile_args)
    assert_equal('fresh', (root / 'executed').read_text, 'ownership was not reusable')
  end

  %w[debug optimized].each do |profile|
    [false, true].each { |cancel| interruption.call('compilation', cancel, profile) }
  end
  [false, true].each { |cancel| interruption.call('execution', cancel, 'debug') }

  # A compiler claiming success without producing output must never succeed.
  compiler.write_text("#!/bin/sh\nexit 0\n")
  run_case.call(project.call('no binary'), 2, 'execution'.b, ['--compiler', compiler])
end
puts 'execution matrix passed'
