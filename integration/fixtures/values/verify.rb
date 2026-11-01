# frozen_string_literal: true

# Exercise new assertions through generated consumer calls and shell statuses.

require_relative '../support'

repo = Pathname.new(__dir__).parent.parent.parent
cli = Pathname.new(ARGV.fetch(0)).expand_path

Dir.mktmpdir('goosetest-values-') do |temporary|
  project = Pathname.new(temporary)
  (project / 'src').mkdir
  (project / 'test').mkdir
  (project / 'src/value.goose').write_text("namespace value;\n")
  (project / 'goosetest_root.goose').write_text(
    "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
    "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
  )
  env = environment('GOOSE_HOME' => (project / 'cache').to_s)

  run_case = lambda do |body, status, expected|
    (project / 'test/value_test.goose').write_text(
      "namespace value_test;\nimport goosetest;\nimport std;\n" \
      "fn test_values(t: goosetest::Test&) { #{body} }\n" \
      "fn test_later(t: goosetest::Test&) { print(\"LATER\"); }\n"
    )
    result = run_capture([cli, 'test', '--project', project], env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [result.status, result.stdout, result.stderr])
    assert_includes(result.stdout, expected.b, 'missing expected output')
    result.stdout
  end

  run_case.call('t.assert_contains("oo", "goose"); t.assert_near(1.0, 1.25, 0.25);', 0, '2 passed')
  out = run_case.call('t.assert_contains("duck", "goose", "species"); print("UNREACHABLE");', 1,
                      'species: expected fragment: <duck> actual: <goose>')
  assert(out.include?('LATER'.b) && !out.include?('UNREACHABLE'.b), 'later case contract failed')
  run_case.call('t.assert_near(1.0, 1.25, 0.1, "distance");', 1, 'absolute tolerance:')
  run_case.call('t.assert_near(1.0, 1.0, -1.0);', 1, 'tolerance must be finite and nonnegative')
end
puts 'value assertion process tests passed'
