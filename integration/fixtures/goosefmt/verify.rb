# frozen_string_literal: true

# Run original regression contracts, then a disposable mirrored consumer of exact production bytes.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
fixture = Pathname.new(__dir__)
repo = fixture.parent.parent.parent
EXPECTED = [
  'integration/pipeline_test.goose::consumer_pipeline_test::test_format_and_lex',
  'test/formatter_test.goose::consumer_formatter_test::test_statement_blocks',
  'test/lexer_test.goose::consumer_lexer_test::test_literal_preservation'
].freeze

def run_fixture(argv, cwd, env, status = 0)
  result = run_capture(argv, chdir: cwd, env: env, timeout: 180)
  assert(result.status == status, 'unexpected status',
         [argv, result.status, result.stdout, result.stderr])
  result
end

manifest = json_load(fixture / 'provenance.json')
manifest['files'].each do |entry|
  assert_equal(entry['sha256'], digest(fixture / entry['snapshot']), 'snapshot digest')
end

# Verify the independent baseline is assembled from exact original declaration bytes.
original_tests = (fixture / 'production/original_tests.goose.data').read_text
declarations = []
(manifest['selected_helpers'] + manifest['selected_tests']).each do |name|
  start = original_tests.match(/^fn #{Regexp.escape(name)}\(/)
  assert(start, 'selected declaration missing', name)
  following = original_tests[start.end(0)..].match(/^fn /)
  assert(following, 'following declaration missing', name)
  finish = start.end(0) + following.begin(0)
  declarations << original_tests[start.begin(0)...finish].rstrip + "\n"
end
expected_baseline = "import std;\nimport formatter;\nimport lexer;\n\n" \
                    + declarations.join("\n") +
                    "\nfn main() {\n    test_statement_blocks();\n    test_literal_preservation();\n}\n"
assert_equal(expected_baseline, (fixture / 'baseline.goose.data').read_text, 'baseline bytes')

Dir.mktmpdir('goosetest-goosefmt-') do |temporary|
  work = Pathname.new(temporary).realpath
  assert(work != repo && !work.to_s.start_with?("#{repo}/"),
         'consumer workspace must be outside the checkout')
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)
  vendor = work / 'vendor'
  vendor.mkdir
  production = manifest['files'].reject { |entry| entry['source'] == 'tests.goose' }
  production.each do |entry|
    copy_file(fixture / entry['snapshot'], vendor / entry['source'])
  end
  (vendor / 'goosefmt.goose').write_text("import lexer;\nimport formatter;\n")
  # Original selected functions and helpers retain builtin assertions and original expectations.
  copy_file(fixture / 'baseline.goose.data', vendor / 'baseline.goose')
  baseline = work / 'baseline'
  run_fixture(['goose', 'build', '--debug', vendor / 'baseline.goose', '-o', baseline], work, env)
  run_fixture([baseline], work, env)

  project = work / 'consumer with spaces'
  (fixture / 'consumer').rglob('**/*.goose.data').each do |template|
    path = project / template.relative_path_from(fixture / 'consumer')
    path = path.with_suffix('')
    path.parent.mkdir(parents: true)
    copy_file(template, path)
  end
  (work / 'framework').symlink_to(repo)
  run_fixture(['goosefmt', 'check', '--config', repo / '.goosefmt.toml', project], work, env)
  listing = run_fixture([cli, 'list', '--project', project], work, env)
  listed = listing.stdout.force_encoding('UTF-8').scan(/^(?:unit|integration)  (\S+)  \(/).flatten
  assert_equal(EXPECTED, listed, 'listing mismatch')
  assert(listing.stdout.force_encoding('UTF-8')
               .end_with?("3 discovered cases: 3 executable, 0 disabled\n"), 'listing trailer')
  audit = run_fixture([cli, 'check-mirror', '--project', project], work, env)
  assert_includes(audit.stdout, '2 matched'.b)

  result = run_fixture([cli, 'test', '--project', project], work, env)
  passed = result.stdout.force_encoding('UTF-8').scan(/^PASS (\S+) \(/).flatten
  assert_equal(EXPECTED, passed, 'passing identities')
  assert_includes(result.stdout, 'Cases: 3 passed, 0 failed, 0 skipped, 0 errors, 0 not run'.b)
  run_fixture(['goosefmt', 'check', '--config', repo / '.goosefmt.toml', project], work, env)

  negative = project / 'test/formatter_test.goose'
  original = negative.read_text
  wrong = original.sub('"fn f() {\\n', '"BROKEN fn f() {\\n')
  assert(wrong != original, 'negative formatter mutation did not change source')
  negative.write_text(wrong)
  rejected = run_fixture([cli, 'test', '--project', project], work, env, 1)
  text = rejected.stdout.force_encoding('UTF-8')
  assert_equal([EXPECTED[1]], text.scan(/^FAIL (\S+) \(/).flatten, 'failing identity')
  assert_equal([EXPECTED[0], EXPECTED[2]], text.scan(/^PASS (\S+) \(/).flatten, 'passing identities')
  assert(text.match(/FAIL .* \(test\/formatter_test\.goose:[0-9]+\)/), text)
  assert_includes(text, 'goosefmt statement formatting')
  assert_includes(text, 'expected: <BROKEN fn f()')
  assert_includes(text, 'actual: <fn f()')
  assert_includes(text, 'Cases: 2 passed, 1 failed, 0 skipped, 0 errors, 0 not run')
  production.each do |entry|
    assert_equal(entry['sha256'], digest(vendor / entry['source']), 'production digest')
  end
end
puts 'goosefmt adoption passed: original baseline, 3 exact migrated IDs, failing expectation status 1'
