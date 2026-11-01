# frozen_string_literal: true

# Independent artifact ownership, recovery, and concurrent invocation checks.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent

def artifact_snapshot(directory)
  recursive_paths(directory, '**/*').each_with_object({}) do |path, result|
    info = path.lstat
    data = path.file? && !path.symlink? ? path.read_bytes : nil
    result[path.relative_path_from(Pathname.new(directory)).to_s] =
      [info.mode, info.mtime.to_i * 1_000_000_000 + info.mtime.nsec, data]
  end
end

Dir.mktmpdir('goosetest-artifacts-') do |temporary|
  work = Pathname.new(temporary)
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)

  write_source = lambda do |root, names|
    body = names.map do |name|
      "fn test_#{name}(t: goosetest::Test&) { " \
        "t.assert_true(write_file(\"executed\", \"#{name}\")); }"
    end.join("\n")
    (root / 'test/a_test.goose').write_text(
      "namespace a_test;\nimport goosetest;\nimport os;\n" + body + "\n"
    )
  end

  make_project = lambda do |name, names = ['first']|
    root = work / "#{name} with spaces"
    (root / 'src').mkdir(parents: true)
    (root / 'test').mkdir
    (root / 'src/a.goose').write_text("namespace a;\n")
    write_source.call(root, names)
    (root / 'goosetest_root.goose').write_text(
      "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
      "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
    )
    root
  end

  run_case = lambda do |root, status = 0, contains = ''.b, extra = []|
    result = run_capture([cli, 'test', '--project', root, *extra],
                         chdir: work, env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [root.basename.to_s, result.status, result.stdout, result.stderr])
    assert_includes(result.stdout + result.stderr, contains, 'missing output')
    result
  end

  repeated = make_project.call('repeat', %w[one two three])
  authored = (repeated / 'goosetest_root.goose').read_bytes
  run_case.call(repeated, 0, '3 passed'.b)
  generated = repeated / 'goosetest_generated'
  first = generated.glob('*.goose').each_with_object({}) do |path, result|
    result[path.basename.to_s] = [path.read_bytes, path.stat.mtime.to_i * 1_000_000_000 + path.stat.mtime.nsec]
  end
  manifest_before = [(generated / '.manifest').read_bytes,
                     (generated / '.manifest').stat.mtime.to_i * 1_000_000_000 +
                       (generated / '.manifest').stat.mtime.nsec]
  run_case.call(repeated, 0, '3 passed'.b)
  second = generated.glob('*.goose').each_with_object({}) do |path, result|
    result[path.basename.to_s] = [path.read_bytes, path.stat.mtime.to_i * 1_000_000_000 + path.stat.mtime.nsec]
  end
  assert_equal(first, second, 'generated files changed on identical run')
  assert_equal(manifest_before,
               [(generated / '.manifest').read_bytes,
                (generated / '.manifest').stat.mtime.to_i * 1_000_000_000 +
                  (generated / '.manifest').stat.mtime.nsec],
               'manifest changed on identical run')
  assert_equal(authored, (repeated / 'goosetest_root.goose').read_bytes, 'authored root changed')

  # Extra user files are never removed, even when obsolete generated cases are pruned.
  (generated / 'user-notes.txt').write_text('preserve me')
  write_source.call(repeated, ['renamed'])
  result = run_case.call(repeated, 0, '1 passed'.b)
  assert(result.stdout.include?('test_renamed'.b) && !result.stdout.include?('test_three'.b))
  assert(!(generated / 'case_1.goose').exist?)
  assert(!(generated / 'case_2.goose').exist?)
  assert(!(generated / 'dispatch_0_0.goose').exist?)
  assert_equal('preserve me', (generated / 'user-notes.txt').read_text)
  assert(!generated.glob('*.goose').map(&:read_bytes).join.include?('test_three'.b))
  assert_equal(authored, (repeated / 'goosetest_root.goose').read_bytes)

  unowned = make_project.call('unowned')
  output = unowned / 'goosetest_generated'
  output.mkdir
  (output / 'runner.goose').write_text('user source')
  before = artifact_snapshot(output)
  run_case.call(unowned, 2, 'artifacts'.b)
  assert_equal(before, artifact_snapshot(output), 'unowned artifacts changed')
  assert(!(unowned / 'executed').exist?)

  # Replace an owned generated file with a link: target and link must survive unchanged.
  outside = work / 'outside.goose'
  outside.write_text('untouchable')
  wrapper = generated / 'case_0.goose'
  wrapper.unlink
  wrapper.symlink_to(outside)
  (repeated / 'executed').unlink
  run_case.call(repeated, 2, 'artifact'.b)
  assert(wrapper.symlink? && outside.read_text == 'untouchable', 'symlinked artifact changed')
  assert(!(repeated / 'executed').exist?)
  wrapper.unlink
  run_case.call(repeated)

  # A changed wrapper cannot publish into a read-only directory or execute its stale binary.
  assert(Process.euid != 0, 'permission fixture requires an unprivileged user')
  write_source.call(repeated, ['changed'])
  (repeated / 'executed').unlink
  before_source = (generated / 'case_0.goose').read_bytes
  generated.chmod(0o500)
  begin
    run_case.call(repeated, 2, 'artifact'.b)
    assert(!(repeated / 'executed').exist?)
    assert_equal(before_source, (generated / 'case_0.goose').read_bytes,
                 'read-only artifact changed')
  ensure
    generated.chmod(0o700)
  end
  run_case.call(repeated, 0, 'test_changed'.b)

  # Simulate interruption after union manifest publication and a partial source update.
  manifest = generated / '.manifest'
  owned = manifest.read_text.lines.map(&:chomp).uniq
  owned << 'case_999.goose'
  manifest.write_text(owned.sort.map { |name| name + "\n" }.join)
  (generated / 'case_999.goose').write_text('interrupted obsolete module')
  (generated / 'case_0.goose').write_text('interrupted current module')
  (generated / '.write-tmp').write_text('interrupted atomic write')
  run_case.call(repeated, 0, 'test_changed'.b)
  assert(!(generated / 'case_999.goose').exist?)
  assert(!(generated / '.write-tmp').exist?)
  assert(!manifest.read_text.include?('case_999.goose'))
  assert_equal('preserve me', (generated / 'user-notes.txt').read_text)

  # New generated names cannot claim an existing unmanifested user file.
  (generated / 'case_1.goose').write_text('user-owned future name')
  write_source.call(repeated, %w[changed added])
  (repeated / 'executed').unlink
  run_case.call(repeated, 2, 'artifact'.b)
  assert_equal('user-owned future name', (generated / 'case_1.goose').read_text)
  assert(!(repeated / 'executed').exist?)
  (generated / 'case_1.goose').unlink
  run_case.call(repeated, 0, '2 passed'.b)
  (repeated / 'src/a.goose').rename(repeated / 'src/b.goose')
  (repeated / 'test/a_test.goose').rename(repeated / 'test/b_test.goose')
  result = run_case.call(repeated, 0, 'test/b_test.goose'.b)
  assert(!result.stdout.include?('test/a_test.goose'.b))
  assert_equal(authored, (repeated / 'goosetest_root.goose').read_bytes)

  compiler = work / 'slow compiler'
  fixture = Pathname.new(__dir__).parent / 'execution/process_tree.c'
  compiler_source = work / 'compiler.c'
  compiler_source.write_text("#include \"#{fixture}\"\n" \
                             "int main(void) { gt_pipeline_wait(); return 0; }\n")
  run_checked(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', compiler_source,
               '-o', compiler], timeout: 30)

  concurrent = make_project.call('concurrent')
  owned_tree = lambda do
    ready = concurrent / 'owned-pids'
    next [] unless ready.exist?

    values = ready.read_text.split
    values.length == 2 ? values.map(&:to_i) : []
  end
  process = FixtureSupport::OwnedProcess.new(
    [cli, 'test', '--project', concurrent, '--compiler', compiler], chdir: work, env: env
  )
  pids = []
  begin
    ready_by = FixtureSupport.monotonic + 15
    while pids.empty?
      pids = owned_tree.call
      assert(process.poll.nil?, 'compiler exited before readiness', process.read_out)
      assert(FixtureSupport.monotonic < ready_by, 'compiler process tree never became ready')
      sleep 0.02
    end
    before = artifact_snapshot(concurrent / 'goosetest_generated')
    run_case.call(concurrent, 2, 'artifact'.b)
    assert_equal(before, artifact_snapshot(concurrent / 'goosetest_generated'),
                 'concurrent invocation changed artifacts')
    process.signal(Signal.list.fetch('INT'))
    stdout, stderr = process.communicate(timeout: 10)
    assert_equal(130, process.returncode, 'concurrent cancellation status')
    assert(stderr.include?('compilation for target default failed;'.b) &&
           stderr.include?('signal=2'.b), 'missing cancellation detail', stderr)
    until_at = FixtureSupport.monotonic + 5
    while !pids.each_with_index.all? { |pid, index| stopped?(pid, allow_zombie: index.positive?) } &&
          FixtureSupport.monotonic < until_at
      sleep 0.02
    end
    assert(pids.each_with_index.all? { |pid, index| stopped?(pid, allow_zombie: index.positive?) },
           'owned process survived', pids)
    assert(!(concurrent / 'executed').exist?, 'stale executable ran')
  ensure
    if process.poll.nil?
      process.kill
      process.communicate(timeout: 5)
    end
    process.close
    cleanup = pids.empty? ? owned_tree.call : pids
    cleanup.each do |pid|
      begin
        Process.kill('KILL', pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end

  # Cancellation releases ownership; every retry regenerates and rebuilds.
  run_case.call(concurrent, 0, '1 passed'.b)
  assert((concurrent / 'executed').exist?)
end
puts 'artifact ownership matrix passed'
