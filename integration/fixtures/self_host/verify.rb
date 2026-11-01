# frozen_string_literal: true

# External status and inventory oracle for the generated repository test runner.

require_relative '../support'

REPO = Pathname.new(__dir__).parent.parent.parent
TOKEN = /[A-Za-z_][A-Za-z_0-9]*|[^\s]/

# Skip comments and quoted literals before recognizing declarations.
def source_tokens(source)
  tokens = []
  cursor = 0
  while cursor < source.length
    if source[cursor, 2] == '//'
      ending = source.index("\n", cursor)
      cursor = ending.nil? ? source.length : ending
    elsif source[cursor, 2] == '/*'
      cursor += 2
      depth = 1
      while depth.positive?
        assert(cursor < source.length, 'unclosed block comment')
        if source[cursor, 2] == '/*'
          depth += 1
          cursor += 2
        elsif source[cursor, 2] == '*/'
          depth -= 1
          cursor += 2
        else
          cursor += 1
        end
      end
    elsif ['"', "'"].include?(source[cursor])
      delimiter = source[cursor, 3] == '"""' ? '"""' : source[cursor]
      cursor += delimiter.length
      until source[cursor, delimiter.length] == delimiter
        assert(cursor < source.length, 'unclosed quoted literal')
        cursor += source[cursor] == '\\' ? 2 : 1
      end
      cursor += delimiter.length
    elsif source[cursor] =~ /\s/
      cursor += 1
    else
      match = TOKEN.match(source, cursor)
      tokens << [match[0], match.begin(0)]
      cursor = match.end(0)
    end
  end
  tokens
end

def inventory(project)
  records = {}
  %w[test integration].each do |directory|
    recursive_paths(project / directory, '**/*.goose').each do |path|
      assert(path.basename.to_s.end_with?('_test.goose'), 'unexpected test filename', path)
      tokens = source_tokens(path.read_text)
      namespace = nil
      depth = 0
      count = 0
      tokens.each_with_index do |(token, offset), index|
        if depth.zero? && token == 'namespace'
          namespace = tokens[index + 1][0]
        end
        if depth.zero? && token == 'fn' && tokens[index + 1][0].start_with?('test_')
          assert(namespace, 'test declaration outside namespace', path)
          name = tokens[index + 1][0]
          identity = "#{path.relative_path_from(project)}::#{namespace}::#{name}"
          assert(!records.key?(identity), 'duplicate identity', identity)
          records[identity] = [path.relative_path_from(project), offset]
          count += 1
        end
        if token == '{'
          depth += 1
        elsif token == '}'
          depth -= 1
          assert(depth >= 0, 'unbalanced braces', path)
        end
      end
      assert(depth.zero? && count.positive?, 'empty or unbalanced suite', path)
    end
  end
  assert(!records.empty?, 'empty source inventory')
  records
end

def run_fixture(argv, env, status = 0, cwd = REPO)
  result = run_capture(argv, chdir: cwd, env: env, timeout: 900)
  assert(result.status == status, 'unexpected status',
         [argv, result.status, result.stdout, result.stderr])
  result.stdout.force_encoding('UTF-8')
end

def listed(output)
  output.lines.select { |line| line.start_with?('unit  ', 'integration  ') }
        .map { |line| line.split[1] }
end

def rows(output, outcome)
  output.scan(/^#{Regexp.escape(outcome)} ([^ ]+) /).flatten
end

def main
  expected = inventory(REPO)
  Dir.mktmpdir('goosetest-self-host-') do |temporary|
    work = Pathname.new(temporary)
    scratch = work / 'scratch'
    scratch.mkdir
    env = environment('GOOSE_HOME' => (work / 'cache').to_s, 'TMPDIR' => scratch.to_s)
    cli = if ARGV.length == 1
            Pathname.new(ARGV[0]).expand_path
          else
            work / 'goosetest'
          end
    if ARGV.empty?
      run_fixture(['goose', 'build', '--debug', REPO / 'main.goose', '-o', cli], env)
    end
    run_fixture([cli, 'check-mirror', '--project', REPO], env)
    actual = listed(run_fixture([cli, 'list', '--project', REPO], env))
    assert_equal(expected.keys.sort, actual.sort, 'inventory mismatch')
    output = run_fixture([cli, 'test', '--project', REPO,
                          '--compile-timeout-seconds', '600',
                          '--run-timeout-seconds', '600'], env)
    assert_equal(expected.keys.sort, rows(output, 'PASS').sort, 'passing inventory mismatch')
    %w[FAIL SKIP ERROR].each do |state|
      assert(rows(output, state).empty?, "unexpected #{state} rows", output)
    end
    assert(rows(output, 'NOT RUN').empty?, 'unexpected NOT RUN rows', output)

    clone = work / 'injected'
    copy_tree(REPO, clone, ignore_names: %w[.git goosetest_generated cache .DS_Store])
    identity = 'integration/self_host_test.goose::self_host_integration_test::test_generated_identity'
    relative, offset = expected.fetch(identity)
    target = clone / relative
    source = target.read_text
    opening = source.index('{', offset)
    source = source[0..opening] + "\n    outer.fail(\"external failure injection\");" + source[(opening + 1)..]
    target.write_text(source)
    failed = run_fixture([cli, 'test', '--project', clone,
                          '--compile-timeout-seconds', '600',
                          '--run-timeout-seconds', '600'], env, 1)
    assert_equal([identity], rows(failed, 'FAIL'), 'injected failure inventory')
    assert_includes(failed, 'external failure injection')
    assert_equal((expected.keys - [identity]).sort, rows(failed, 'PASS').sort,
                 'remaining passing inventory')
    puts "self-host verified: #{expected.length} discovered and passing; injected assertion exits 1"
  end
end

main
