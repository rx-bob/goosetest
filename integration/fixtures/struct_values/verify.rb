# frozen_string_literal: true

# Independent permissions-example status and ordered field-diagnostic oracle.

require_relative '../support'

repo = Pathname.new(__dir__).parent.parent.parent
cli = Pathname.new(ARGV.fetch(0)).expand_path

Dir.mktmpdir('goosetest-struct-') do |temporary|
  project = Pathname.new(temporary)
  (project / 'src').mkdir
  (project / 'test').mkdir
  (project / 'goosetest_root.goose').write_text(
    "import goosetest from \"#{repo}\";\nimport goosetest_generated.runner;\n" \
    "import os;\nfn main() { exit(goosetest_generated::run_all()); }\n"
  )
  (project / 'src/permissions.goose').write_text(<<~GOOSE)
    // Representative comparable permission result.
    namespace permissions;

    struct Decision {
        allowed: bool,
        effective_role: const u8[:],
        reason: const u8[:],
    }

    fn viewer() -> Decision {
        return Decision {
            allowed: false,
            effective_role: "viewer",
            reason: "insufficient_role",
        };
    }
  GOOSE

  env = environment('GOOSE_HOME' => (project / 'cache').to_s)

  run_case = lambda do |allowed, reason, status|
    (project / 'test/permissions_test.goose').write_text(<<~GOOSE.gsub('ALLOWED', allowed).gsub('REASON', reason))
      // Passing and negative variants share authored source and generated execution.
      namespace permissions_test;

      import goosetest;

      import src.permissions;

      fn test_viewer(t: goosetest::Test&) {
          let expected = permissions::Decision {
              allowed: ALLOWED,
              effective_role: "viewer",
              reason: "REASON",
          };
          var actual = permissions::viewer();
          t.assert_struct_eq(expected, actual, "viewer write check");
      }

      fn test_later(t: goosetest::Test&) {
          t.assert_true(true);
      }
    GOOSE
    result = run_capture([cli, 'test', '--project', project], env: env, timeout: 120)
    assert(result.status == status, 'unexpected status',
           [result.status, result.stdout, result.stderr])
    assert_includes(result.stdout, 'PASS test/permissions_test.goose::permissions_test::test_later'.b)
    result.stdout
  end

  out = run_case.call('false', 'insufficient_role', 0)
  assert(out.include?('2 passed'.b) && !out.include?('struct fields differ'.b))
  out = run_case.call('true', 'ok', 1)
  diagnostic = "viewer write check: struct fields differ:\n" \
               ".allowed expected: <true> actual: <false>\n" \
               ".reason expected: <ok> actual: <insufficient_role>\n".b
  assert_includes(out, diagnostic.gsub("\n".b, '\\x0A'.b), 'missing ordered diagnostic')
  assert(!out.include?('.effective_role'.b))
  assert(out.include?('1 passed, 1 failed'.b))

  { 'mismatched_types' => 'no matching overload', 'nonstruct' => 'fields requires' }.each do |name, diagnostic|
    source = (Pathname.new(__dir__) / "#{name}.goose.data").read_text
    path = project / "#{name}.goose"
    path.write_text(source.gsub('PACKAGE_PATH', repo.to_s))
    result = run_capture(['goose', 'build', '--debug', path, '-o', project / name],
                         env: env, timeout: 120)
    assert(result.status != 0, 'invalid struct assertion compiled', name)
    assert_includes(result.stdout + result.stderr, diagnostic.b, 'missing diagnostic')
    assert(!(project / name).exist?, 'invalid assertion produced an executable')
  end
end
puts 'struct assertion process tests passed'
