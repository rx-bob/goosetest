# frozen_string_literal: true

# Independent completeness oracle beyond 128 files per root and 64 cases per module.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent

def call_cli(cli, args, work, env, status = 0)
  result = run_capture([cli, *args], chdir: work, env: env, timeout: 180)
  assert(result.status == status, 'unexpected status',
         [args, result.status, result.stdout, result.stderr])
  result
end

def goose_literal(chunk)
  body = chunk[1..-2]
  body.gsub(/\\(x\h{2}|.)/m) do
    escape = Regexp.last_match(1)
    if escape.start_with?('x')
      escape[1..].to_i(16).chr
    else
      case escape
      when 'n' then "\n"
      when 'r' then "\r"
      when 't' then "\t"
      when '0' then "\0"
      else escape
      end
    end
  end
end

def wrapper_identity(path)
  source = path.read_text
  %w[source_path source_namespace source_function].map do |name|
    match = source.match(/fn #{Regexp.escape(name)}\(\).*?\n\}/m)
    assert(match, 'wrapper declaration missing', [path, name])
    chunks = match[0].scan(/text\.append\(("(?:[^"\\]|\\.)*")\);/m).flatten
    chunks.map { |chunk| goose_literal(chunk) }.join
  end.join('::')
end

Dir.mktmpdir('goosetest-limits-') do |temporary|
  work = Pathname.new(temporary).realpath
  project = work / 'large consumer'
  (project / 'src').mkdir(parents: true)
  (project / 'test').mkdir
  (work / 'package').symlink_to(repo)
  (project / 'goosetest_root.goose').write_text(
    "import goosetest from \"../package\";\nimport goosetest_generated.runner;\n" \
    "fn main() { exit(goosetest_generated::run_all()); }\n"
  )
  expected = []
  expected_listing = []
  129.times do |index|
    name = format('module_%03d', index)
    (project / 'src' / "#{name}.goose").write_text(
      "namespace #{name};\nfn value() -> i64 { return #{index}; }\n"
    )
    lines = ["namespace #{name}_test;", 'import goosetest;', "import src.#{name};"]
    cases = index.zero? ? (0...65).map { |number| format('case_%03d', number) } : %w[first second]
    cases.each do |test_case|
      function = "test_#{test_case}"
      identity = "test/#{name}_test.goose::#{name}_test::#{function}"
      lines << "fn #{function}(t: goosetest::Test&) { t.assert_eq(#{index}, #{name}::value()); }"
      expected << identity
      expected_listing << "unit  #{identity}  (test/#{name}_test.goose:#{lines.length}:1)"
    end
    (project / 'test' / "#{name}_test.goose").write_text(lines.join("\n") + "\n")
  end
  assert_equal(129, (project / 'src').glob('*.goose').length, 'source file count')
  assert_equal(129, (project / 'test').glob('*.goose').length, 'test file count')

  env = environment('GOOSE_HOME' => (work / 'cache').to_s)
  listing = call_cli(cli, ['list', '--project', project], work, env)
  assert(listing.stderr.empty?, 'listing wrote stderr', listing.stderr)
  assert_equal(expected_listing + ['321 discovered cases: 321 executable, 0 disabled'],
               listing.stdout.force_encoding('UTF-8').lines.map(&:chomp), 'listing mismatch')

  compiler = work / 'compiler'
  log = work / 'compiler.json'
  real_goose = which('goose') or raise FixtureSupport::Failure, 'goose not found'
  compiler.write_text(<<~RUBY)
    #!#{ruby_executable}
    require 'json'
    File.write(#{log.to_s.dump}, JSON.generate(ARGV))
    exec(#{real_goose.dump}, *ARGV)
  RUBY
  compiler.chmod(0o700)

  result = call_cli(cli, ['test', '--project', project, '--compiler', compiler], work, env)
  invocation = JSON.parse(log.read_text)
  assert_equal(['build', 'goosetest_root.goose', '-O0', '--debug', '-o',
                './goosetest_generated/tests'], invocation, 'compiler invocation')
  passed = result.stdout.scan(/^PASS (\S+) \(/).flatten
  assert_equal(expected, passed, 'passing identity order')
  assert_includes(result.stdout, 'Cases: 321 passed, 0 failed, 0 skipped, 0 errors, 0 not run'.b)
  generated = project / 'goosetest_generated'
  wrappers = generated.glob('case_*.goose').sort_by { |path| path.basename.to_s[5..].to_i }
  assert_equal(expected, wrappers.map { |path| wrapper_identity(path) }, 'wrapper identities')

  log.unlink
  oversized = project / 'src/module_000.goose'
  oversized.write_bytes('/' * (1_048_576 + 1))
  rejected = call_cli(cli, ['test', '--project', project, '--compiler', compiler], work, env, 2)
  diagnostic = rejected.stderr.force_encoding('UTF-8')
  assert_includes(diagnostic, 'src/module_000.goose')
  assert(diagnostic.downcase.include?('limit') && diagnostic.include?('1048576'), diagnostic)
  assert_includes(diagnostic, 'Discovery incomplete; no tests executed.')
  assert(!log.exist?, 'discovery failure must not invoke the compiler')
  assert(!rejected.stdout.match(/^PASS /m), 'failed discovery emitted PASS rows', rejected.stdout)
end
puts 'limits regression passed: 321 exact IDs; 129 files per root, 65 cases in one module; oversized source rejected'
