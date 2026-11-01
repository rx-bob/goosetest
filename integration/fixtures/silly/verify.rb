# frozen_string_literal: true

# Compare preserved Silly URL/HTTP checks with a configured goosetest consumer.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
fixture = Pathname.new(__dir__)
repo = fixture.parent.parent.parent
EXPECTED = [
  'core::tests/http/http_host_test.goose::http_host_test::test_invalid_authority_forms',
  'core::tests/http/http_host_test.goose::http_host_test::test_request_target_syntax',
  'core::tests/http/http_host_test.goose::http_host_test::test_valid_authority_forms',
  'core::tests/request/url_test.goose::url_test::test_literal_invalid_escapes',
  'core::tests/request/url_test.goose::url_test::test_path_decoding_capacity_and_output_atomicity',
  'core::tests/request/url_test.goose::url_test::test_strict_query_decoding'
].freeze

def run_fixture(argv, cwd, env, status = 0)
  result = run_capture(argv, chdir: cwd, env: env, timeout: 240)
  assert(result.status == status, 'unexpected status',
         [argv, result.status, result.stdout, result.stderr])
  result
end

manifest = json_load(fixture / 'provenance.json')
manifest['files'].each do |record|
  assert_equal(record['sha256'], digest(fixture / record['snapshot']), 'snapshot digest')
end

Dir.mktmpdir('goosetest-silly-adoption-') do |temporary|
  work = Pathname.new(temporary).realpath
  assert(work != repo && !work.to_s.start_with?("#{repo}/"),
         'consumer workspace must be outside the checkout')
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)

  # Run the original standalone source unchanged, assembled from the exact
  # production and test snapshots recorded above.
  baseline = work / 'original Silly baseline'
  production = manifest['files'].select { |record| record['source'].start_with?('src/') }
  original_tests = manifest['files'].select { |record| record['source'].start_with?('tests/') }
  (production + original_tests).each do |record|
    output = baseline / record['source']
    output.parent.mkdir(parents: true)
    copy_file(fixture / record['snapshot'], output)
  end
  (baseline / 'silly.goose').write_text(
    "namespace silly;\n" \
    "import.src.request.url;\n" \
    "import.src.request.headers;\n" \
    "import.src.http.http_host;\n" \
    "import.src.http.http_head_types;\n" \
    "import.src.http.http_request_line;\n"
  )

  [['debug', ['--debug']], ['optimized', ['-O2']]].each do |profile, flags|
    url_binary = work / "url-original-#{profile}"
    http_binary = work / "http-original-#{profile}"
    run_fixture(['goose', 'build', baseline / 'tests/request/url_test.goose', *flags,
                 '-o', url_binary], baseline, env)
    url_run = run_fixture([url_binary], baseline, env)
    assert_equal('bounded URL and strict path decoding passed'.b, url_run.stdout.strip,
                 'original URL checks')
    run_fixture(['goose', 'build', baseline / 'tests/http/http_host_test.goose', *flags,
                 '-o', http_binary], baseline, env)
    http_run = run_fixture([http_binary], baseline, env)
    assert_equal('HTTP authority syntax passed'.b, http_run.stdout.strip, 'original HTTP checks')
  end

  # Materialize the small unchanged package closure and converted test roots.
  project = work / 'consumer with spaces'
  production.each do |record|
    relative = Pathname.new(record['source'])
    output = project / relative
    output.parent.mkdir(parents: true)
    copy_file(fixture / record['snapshot'], output)
  end
  materialize_templates(fixture / 'consumer', project)
  (work / 'goosetest').symlink_to(repo)
  config = {
    'version' => 1,
    'targets' => [
      {
        'name' => 'core',
        'entry' => 'goosetest_core.goose',
        'tests' => [
          { 'path' => 'tests/request', 'kind' => 'unit' },
          { 'path' => 'tests/http', 'kind' => 'unit' }
        ],
        'mirror' => { 'policy' => 'off', 'pairs' => [] }
      },
      {
        'name' => 'optional_native',
        'entry' => 'goosetest_optional_native.goose',
        'tests' => [{ 'path' => 'tests/optional', 'kind' => 'unit' }],
        'mirror' => { 'policy' => 'off', 'pairs' => [] }
      }
    ]
  }
  (project / 'goosetest.json').write_text(json_dump(config))

  listed = run_fixture([cli, 'list', '--project', project, '--target', 'core'], work, env)
  listed_ids = listed.stdout.force_encoding('UTF-8')
                       .scan(/^(?:unit|integration)  (\S+)  \(/).flatten
  assert_equal(EXPECTED, listed_ids, 'core inventory')
  assert(listed.stdout.force_encoding('UTF-8')
               .end_with?("6 discovered cases: 6 executable, 0 disabled\n"), 'inventory trailer')
  disabled_mirror = run_fixture([cli, 'check-mirror', '--project', project, '--target', 'core'],
                                work, env, 2)
  assert_includes(disabled_mirror.stdout + disabled_mirror.stderr,
                  'Mirror enforcement is disabled'.b)

  %w[debug optimized].each do |profile|
    result = run_fixture([cli, 'test', '--project', project, '--target', 'core',
                          '--profile', profile], work, env)
    passed = result.stdout.force_encoding('UTF-8').scan(/^PASS (\S+) \(/).flatten
    assert_equal(EXPECTED, passed, "passing inventory #{profile}")
    assert_includes(result.stdout,
                    'Cases: 6 passed, 0 failed, 0 skipped, 0 errors, 0 not run'.b)
  end

  # The intentionally unavailable native dependency is outside core's build closure.
  assert(!(project / 'goosetest_generated/optional_native/tests').exist?)
  optional = run_fixture([cli, 'test', '--project', project, '--target', 'optional_native'],
                         work, env, 2)
  assert_includes(optional.stderr, 'compilation for target optional_native'.b)
  assert(!optional.stdout.include?('TARGET core'.b))

  # A wrong converted expectation remains an ordinary, useful assertion failure.
  url_test = project / 'tests/request/url_test.goose'
  original = url_test.read_text
  wrong = original.sub(
    't.assert_eq("a+b/%2F//", copy(output), "path preserves plus and decodes once");',
    't.assert_eq("BROKEN", copy(output), "path preserves plus and decodes once");'
  )
  assert(wrong != original, 'negative URL mutation did not change source')
  url_test.write_text(wrong)
  rejected = run_fixture([cli, 'test', '--project', project, '--target', 'core'], work, env, 1)
  failure_text = rejected.stdout.force_encoding('UTF-8')
  failing_id = 'core::tests/request/url_test.goose::url_test::test_path_decoding_capacity_and_output_atomicity'
  assert_equal([failing_id], failure_text.scan(/^FAIL (\S+) \(/).flatten, 'failing inventory')
  assert_includes(failure_text, 'path preserves plus and decodes once')
  assert_includes(failure_text, 'expected: <BROKEN>')
  assert_includes(failure_text, 'actual: <a+b/%2F//>')
  url_test.write_text(original)

  # Copied production inputs and original test snapshots remain byte-identical.
  production.each do |record|
    assert_equal(record['sha256'], digest(project / record['source']), 'consumer production digest')
    assert_equal(record['sha256'], digest(baseline / record['source']), 'baseline production digest')
  end
  original_tests.each do |record|
    assert_equal(record['sha256'], digest(baseline / record['source']), 'baseline test digest')
  end
end
puts 'Silly adoption passed: original URL/HTTP checks, six exact IDs in both profiles, optional native isolation'
