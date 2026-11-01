# frozen_string_literal: true

# Exercise the configured one-target pipeline from an unrelated caller cwd.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent

def write_project(root, suite = nil, entry = nil)
  tests = root / 'tests/request'
  tests.mkdir(parents: true)
  (tests / 'support.goose').write_text(
    "namespace support;\nfn value() -> i64 { return 42; }\n"
  )
  (root / 'resource').write_text("project cwd\n")
  suite ||= "namespace url_test;\nimport goosetest;\nimport os;\n" \
            "import tests.request.support;\n" \
            "fn test_a_failure(t: goosetest::Test&) { t.assert_eq(1, 2); }\n" \
            "fn test_b_pass(t: goosetest::Test&) { var data: u8[>..] = []; " \
            "t.assert_true(read_file(\"resource\", data)); " \
            "t.assert_eq(\"project cwd\\n\", data); " \
            "t.assert_eq(42, support::value()); }\n"
  (tests / 'url_test.goose').write_text(suite)
  entry ||= "import goosetest from \"../goosetest\";\n" \
            "import goosetest_generated.core.runner;\n" \
            "fn main() { exit(goosetest_generated::run_all()); }\n"
  (root / 'goosetest_core.goose').write_text(entry)
  config = {
    'version' => 1,
    'targets' => [{
      'name' => 'core',
      'entry' => 'goosetest_core.goose',
      'tests' => [{ 'path' => 'tests/request', 'kind' => 'unit' }],
      'mirror' => { 'policy' => 'off', 'pairs' => [] }
    }]
  }
  (root / 'goosetest.json').write_text(json_dump(config))
end

def project_at(base, name, repo)
  root = base / name
  root.mkdir
  link = base / 'goosetest'
  link.symlink_to(repo) unless link.exist?
  write_project(root)
  native = root / 'native'
  native.mkdir
  (native / 'marker.c').write_text("int configured_marker(void) { return 1; }\n")
  (root / 'goosetest_core.build').write_text('c_sources = ["native/marker.c"];' + "\n")
  root
end

Dir.mktmpdir('goosetest-configured-') do |temporary|
  work = Pathname.new(temporary)
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)

  run_case = lambda do |args, cwd, status = 0, contains = ''.b|
    result = run_capture([cli, *args], chdir: cwd, env: env, timeout: 180)
    assert(result.status == status, 'unexpected status',
           [args, result.status, result.stdout, result.stderr])
    assert_includes(result.stdout + result.stderr, contains, 'missing output')
    result
  end

  # Run from another cwd: the config, entry, generated imports, and test resource all
  # resolve from the project root.
  good = project_at(work, 'consumer with spaces', repo)
  before_entry = (good / 'goosetest_core.goose').read_bytes
  before_sidecar = (good / 'goosetest_core.build').read_bytes
  listed = run_case.call(['list', '--project', good], work, 0,
                         'core::tests/request/url_test.goose::url_test::test_a_failure'.b)
  assert_includes(listed.stdout,
                  'core::tests/request/url_test.goose::url_test::test_b_pass'.b)
  assert(!listed.stdout.include?('support.goose'.b))
  run_case.call(['check-mirror', '--project', good], work, 2,
                'Mirror enforcement is disabled'.b)
  failed = run_case.call(['test', '--project', good], work, 1,
                         'core::tests/request/url_test.goose::url_test::test_a_failure'.b)
  assert_includes(failed.stdout,
                  'core::tests/request/url_test.goose::url_test::test_b_pass'.b)
  assert_includes(failed.stdout, 'expected: <1> actual: <2>'.b)
  assert_equal(before_entry, (good / 'goosetest_core.goose').read_bytes, 'entry changed')
  assert_equal(before_sidecar, (good / 'goosetest_core.build').read_bytes, 'sidecar changed')
  generated = good / 'goosetest_generated/core'
  assert((generated / 'tests').file?)
  assert_equal("1\n", (generated / 'completion').read_text, 'completion record')
  run_case.call(['test', '--project', good], work, 1, '1 failed'.b)
  first = generated.glob('*.goose').to_h do |path|
    [path.basename.to_s,
     [Digest::SHA256.digest(path.read_bytes), path.stat.mtime.to_i * 1_000_000_000 + path.stat.mtime.nsec]]
  end
  run_case.call(['test', '--project', good], work, 1, '1 failed'.b)
  repeated = generated.glob('*.goose').to_h do |path|
    [path.basename.to_s,
     [Digest::SHA256.digest(path.read_bytes), path.stat.mtime.to_i * 1_000_000_000 + path.stat.mtime.nsec]]
  end
  assert_equal(first, repeated, 'repeated generation changed artifacts')
  (good / 'goosetest_generated/user-file.txt').write_text("preserve\n")

  # A later passing case demonstrates normal success after the failure.
  (good / 'tests/request/url_test.goose').write_text(
    "namespace url_test;\nimport goosetest;\nimport os;\nimport tests.request.support;\n" \
    "fn test_a_pass(t: goosetest::Test&) { var data: u8[>..] = []; " \
    "t.assert_true(read_file(\"resource\", data)); " \
    "t.assert_eq(\"project cwd\\n\", data); t.assert_eq(42, support::value()); }\n" \
    "fn test_b_pass(t: goosetest::Test&) { t.assert_eq(42, support::value()); }\n"
  )
  run_case.call(['test', '--project', good], work, 0, '2 passed'.b)
  assert_equal("preserve\n", (good / 'goosetest_generated/user-file.txt').read_text,
               'user file removed')

  text = (good / 'tests/request/url_test.goose').read_text
                                       .gsub('tests.request.support', 'tests.request.absent')
  (good / 'tests/request/url_test.goose').write_text(text)
  run_case.call(['test', '--project', good], work, 2, 'compilation'.b)
  assert(!(good / 'goosetest_generated/core/tests').exist?)

  premature = project_at(work, 'premature exit', repo)
  (premature / 'goosetest_core.goose').write_text("fn main() { exit(0); }\n")
  run_case.call(['test', '--project', premature], work, 2, 'completion record'.b)

  unowned = project_at(work, 'unowned target', repo)
  (unowned / 'goosetest_generated/core').mkdir(parents: true)
  run_case.call(['test', '--project', unowned], work, 2, 'artifacts'.b)

  linked = project_at(work, 'linked target', repo)
  outside = work / 'outside'
  outside.mkdir
  (linked / 'goosetest_generated').mkdir
  File.symlink(outside.to_s, (linked / 'goosetest_generated/core').to_s)
  run_case.call(['test', '--project', linked], work, 2, 'artifacts'.b)

  multiple = project_at(work, 'multiple targets', repo)
  config = json_load(multiple / 'goosetest.json')
  second = config['targets'][0].dup
  second['name'] = 'other'
  second['entry'] = 'other.goose'
  second['tests'] = [{ 'path' => 'tests/other', 'kind' => 'unit' }]
  config['targets'] << second
  (multiple / 'goosetest.json').write_text(json_dump(config))
  selected = run_case.call(['list', '--project', multiple, '--target', 'core'], work, 0,
                           'core::tests/request/url_test.goose'.b)
  assert(!selected.stdout.include?('other::'.b))

  # A configured strict pair uses arbitrary source/test roots and still
  # discovers imported helpers without admitting them as suites.
  strict = project_at(work, 'strict configured mirror', repo)
  (strict / 'src/request').mkdir(parents: true)
  (strict / 'src/request/url.goose').write_text(
    "namespace url;\nfn value() -> i64 { return 42; }\n"
  )
  (strict / 'tests/request/url_test.goose').write_text(
    "namespace url_test;\nimport goosetest;\nimport src.request.url;\n" \
    "import tests.request.support;\n" \
    "fn test_configured_mirror(t: goosetest::Test&) { " \
    "t.assert_eq(42, url::value()); t.assert_eq(42, support::value()); }\n"
  )
  config = json_load(strict / 'goosetest.json')
  config['targets'][0]['mirror'] = {
    'policy' => 'strict',
    'pairs' => [{ 'source' => 'src/request', 'tests' => 'tests/request' }]
  }
  (strict / 'goosetest.json').write_text(json_dump(config))
  strict_audit = run_case.call(['check-mirror', '--project', strict, '--target', 'core'],
                               work, 0, '1 matched'.b)
  assert(!strict_audit.stdout.include?('Mirror enforcement is disabled'.b))
  run_case.call(['test', '--project', strict, '--target', 'core'], work, 0, '1 passed'.b)
end
puts 'configured target process tests passed'
