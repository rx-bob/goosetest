# frozen_string_literal: true

# Independent process/read-only checks. Supply built CLI and Goose oracle paths.

require_relative '../support'

cli, oracle = ARGV[0, 2].map { |value| Pathname.new(value).expand_path }
repo = Pathname.new(__dir__).parent.parent.parent

def snapshot(root)
  paths = [root] + recursive_paths(root, '**/*')
  paths.each_with_object({}) do |path, result|
    info = path.lstat
    data = path.file? ? digest(path) : nil
    result[path.relative_path_from(root).to_s] =
      [info.mode, info.size, info.mtime.to_i * 1_000_000_000 + info.mtime.nsec, data]
  end
end

def run_fixture(cli, args, cwd, status = 0, contains = nil)
  result = run_capture([cli, *args], chdir: cwd, timeout: 15)
  assert(result.status == status, 'unexpected status',
         [args, result.status, result.stderr])
  if status.zero?
    assert(result.stderr.empty?, 'unexpected stderr', result.stderr)
  else
    assert(result.stdout.empty?, 'error wrote stdout', result.stdout)
    assert(!result.stderr.empty?, 'error omitted stderr', args)
  end
  assert_includes(result.stdout + result.stderr, contains, 'missing output') unless contains.nil?
  result
end

def exact(oracle, result, expected, work)
  (work / 'actual').write_bytes(result.stdout)
  (work / 'expected').write_bytes(expected)
  run_checked([oracle, work / 'actual', work / 'expected', result.status, 0], timeout: 15)
end

Dir.mktmpdir('goosetest-cli-') do |temporary|
  work = Pathname.new(temporary)
  project = work / 'project with spaces'
  %w[src test integration].each { |name| (project / name).mkdir(parents: true) }
  # Deliberately uncompilable source proves discovery does not invoke compilation.
  (project / 'src/a.goose').write_text('not valid Goose production source')
  (project / 'test/a_test.goose').write_text(
    "namespace a;\n// @Disabled(\"why\\n\\0\")\n" \
    'fn test_a(t: goosetest::Test&) { write_file("executed", "bad"); }'
  )
  (project / 'integration/flow_test.goose').write_text(
    "namespace flow;\nimport src.a;\n" \
    'fn test_flow(t: goosetest::Test&) { write_file("executed", "bad"); }'
  )
  before = snapshot(project)
  first = run_fixture(cli, ['list', '--project', project], work)
  exact(oracle, first,
        "integration  integration/flow_test.goose::flow::test_flow  " \
        "(integration/flow_test.goose:3:1)\n" \
        "unit  test/a_test.goose::a::test_a  (test/a_test.goose:3:1)\n" \
        "      disabled: why\\x0A\\x00\n" \
        "2 discovered cases: 1 executable, 1 disabled\n".b, work)
  assert_equal(first.stdout, run_fixture(cli, ['list'], project).stdout, 'listing cwd independence')
  assert_equal(first.stdout,
               run_fixture(cli, ['--project', project, 'list'], work).stdout,
               'argument order independence')
  audit = run_fixture(cli, ['check-mirror'], project)
  exact(oracle, audit,
        "MIRROR OK  src/a.goose -> test/a_test.goose\n" \
        "Unit mirrors: 1 matched, 0 missing, 0 orphaned; 0 bad test filenames\n" \
        "Integration suites: 1\n".b, work)
  assert_equal(before, snapshot(project), 'read-only command mutated project')

  [
    [], ['unknown'], %w[list --unknown a], %w[list --project],
    ['list', '--project', ''], %w[list extra], %w[list check-mirror],
    ['list', '--project', '.', '--project', '.'], ['--help', '--bad']
  ].each do |args|
    run_fixture(cli, args, work, 2, 'Usage:'.b)
  end
  run_fixture(cli, ['--help'], work, 0, 'Default finite limits'.b)
  run_fixture(cli, ['list', '--help', '--project', 'nonexistent'], work, 0, 'Usage:'.b)
  run_fixture(cli, ['list', '--project', 'nonexistent'], work, 2, 'cannot open project'.b)

  (project / 'src/a.goose').rename(project / 'src/renamed.goose')
  before = snapshot(project)
  %w[list check-mirror test].each do |command|
    result = run_fixture(cli, [command], project, 2, 'MISSING TEST  src/renamed.goose'.b)
    assert_includes(result.stderr, 'ORPHAN TEST  test/a_test.goose'.b)
  end
  assert_equal(before, snapshot(project), 'missing-mirror audit mutated project')
  (project / 'src/renamed.goose').rename(project / 'src/a.goose')

  [
    ['namespace a;', 'requires at least one valid test'],
    ["namespace a;\n// @Tag(\"x\")\nfn test_a(t: goosetest::Test&) {}",
     'unsupported annotation'],
    ["namespace a;\n// @DisplayName(42)\nfn test_a(t: goosetest::Test&) {}",
     'annotation requires one quoted string argument'],
    ["namespace a;\n// @Disabled(\"\")\nfn test_a(t: goosetest::Test&) {}",
     'disabled reason must not be empty']
  ].each do |content, error|
    (project / 'test/a_test.goose').write_text(content)
    before = snapshot(project)
    %w[list check-mirror test].each do |command|
      run_fixture(cli, [command], project, 2, error.b)
    end
    assert_equal(before, snapshot(project), 'invalid metadata mutated project')
    assert(!(project / 'executed').exist?)
    assert(!(project / 'goosetest_generated').exist?)
  end

  (project / 'test/a_test.goose').rename(project / 'test/helper.goose')
  run_fixture(cli, ['list'], project, 2, 'BAD TEST NAME  test/helper.goose'.b)
  (project / 'test/helper.goose').rename(project / 'test/a_test.goose')
  (project / 'test/a_test.goose').write_text(
    'namespace a; fn test_a(t: goosetest::Test&) {}'
  )
  assert(Process.euid != 0, 'permission-denial fixture requires an unprivileged user')
  unreadable = project / 'src/a.goose'
  unreadable.chmod(0)
  begin
    run_fixture(cli, ['list'], project, 2, 'cannot read regular source file'.b)
  ensure
    unreadable.chmod(0o644)
  end
  unreadable.write_bytes('x' * 1_048_577)
  before = snapshot(project)
  %w[check-mirror test].each do |command|
    run_fixture(cli, [command], project, 2, 'max_file_bytes exceeded'.b)
  end
  assert_equal(before, snapshot(project), 'oversized source mutated project')
  assert(!(project / 'executed').exist?)
  assert(!(project / 'goosetest_generated').exist?)

  # Missing roots and empty projects fail; the real example passes from another cwd.
  empty = work / 'empty'
  empty.mkdir
  run_fixture(cli, ['list', '--project', empty], work, 2, 'required root is missing'.b)
  (empty / 'src').mkdir
  (empty / 'test').mkdir
  run_fixture(cli, ['check-mirror', '--project', empty], work, 2,
              'no test cases discovered'.b)
  example = repo / 'examples/basic'
  before = snapshot(example)
  run_fixture(cli, ['list', '--project', example], work, 0, '4 discovered cases'.b)
  run_fixture(cli, ['check-mirror', '--project', example], work, 0, '1 matched'.b)
  assert_equal(before, snapshot(example), 'example project mutated')
end
puts 'cli process tests passed'
