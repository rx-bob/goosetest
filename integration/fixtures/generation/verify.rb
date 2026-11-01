# frozen_string_literal: true

# Compile generated consumers without rewriting authored package roots or sidecars.

require_relative '../support'

generator = Pathname.new(ARGV.fetch(0)).expand_path
repo = Pathname.new(__dir__).parent.parent.parent

def call_fixture(generator, args, cwd, environment, status = 0)
  result = run_capture(args, chdir: cwd, env: environment, timeout: 120)
  assert(result.status == status, 'unexpected status',
         [args, result.stdout, result.stderr])
  result.stdout
end

def snapshot(directory)
  recursive_paths(directory, '**/*').select(&:file?).each_with_object({}) do |path, result|
    result[path.relative_path_from(Pathname.new(directory)).to_s] = path.read_bytes
  end
end

def generate(generator, project, env, repo)
  destination = project / 'goosetest_generated'
  destination.rmtree if destination.exist?
  call_fixture(generator, [generator, project, destination], project.parent, env)
  check_generated_style(destination, repo, max_line_length: 120)
  second = project.parent / 'second-generation'
  second.rmtree if second.exist?
  call_fixture(generator, [generator, project, second], project.parent, env)
  assert_equal(snapshot(destination), snapshot(second), 'generation is not deterministic')
end

def build_run(project, work, env, name, status = 0)
  binary = work / name
  run_checked(['goose', 'build', '--debug', project / 'goosetest_root.goose', '-o', binary],
              chdir: work, env: env, timeout: 120)
  run_capture([binary], chdir: work, env: env, timeout: 120).tap do |result|
    assert(result.status == status, 'unexpected status', [name, result.status, result.stdout, result.stderr])
  end.stdout.force_encoding('UTF-8')
end

def literal(data)
  '"' + data.bytes.map { |byte| format('\\x%02X', byte) }.join + '"'
end

Dir.mktmpdir('goosetest-generation-') do |temporary|
  work = Pathname.new(temporary).realpath
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)
  project = work / 'consumer with spaces'
  copy_tree(repo / 'examples/basic', project)
  (work / 'package').symlink_to(repo)
  root = project / 'goosetest_root.goose'
  root.write_text(
    "// Authored once.\nimport goosetest from \"../package\";\n" \
    "import addon from \"../native library\";\n\nimport goosetest_generated.runner;\n\n" \
    "fn main() {\n    exit(goosetest_generated::run_all());\n}\n"
  )
  addon = work / 'native library'
  (addon / 'native').mkdir(parents: true)
  (addon / 'addon.goose').write_text(
    "namespace addon;\nextern \"addon_value\" fn value() -> i32;\n"
  )
  (addon / 'addon.build').write_text('c_sources = ["native/addon_value.c"];' + "\n")
  (addon / 'native/addon_value.c').write_text(
    "#include <stdint.h>\nint32_t addon_value(void) { return 40; }\n"
  )
  (project / 'native').mkdir
  (project / 'native/root_value.c').write_text(
    "#include <stdint.h>\nint32_t root_value(void) { return 2; }\n"
  )
  sidecar = project / 'goosetest_root.build'
  sidecar.write_text('c_sources = ["native/root_value.c"];' + "\n")
  authored = [root.read_bytes, sidecar.read_bytes, snapshot(addon)]
  generate(generator, project, env, repo)
  output = build_run(project, work, env, 'basic')
  assert_equal(4, output.scan('PASS ').length, 'basic passing rows')
  assert_includes(output, 'Cases: 4 passed')

  # New valid source/unit pair and integration suite: no root or registration edits.
  (project / 'src/native.goose').write_text(
    "namespace native_source;\nimport addon;\n" \
    "extern \"root_value\" fn root_value() -> i32;\n" \
    "fn value() -> i32 { return addon::value() + root_value(); }\n"
  )
  (project / 'test/native_test.goose').write_text(
    "namespace native_test;\nimport goosetest;\nimport src.native;\n" \
    'fn test_native(t: goosetest::Test&) { t.assert_eq(42, native_source::value()); }'
  )
  (project / 'integration').mkdir(parents: true)
  label = "quote\" slash\\ newline\n nul\0 utf8\xC3\xA9".b
  (project / 'integration/label_test.goose').write_text(
    "namespace label_test;\nimport goosetest;\n" \
    "// @DisplayName(#{literal(label)})\nfn test_label(t: goosetest::Test&) {\n" \
    "    let identity = t.results.cases[t.current_case].identity;\n" \
    "    t.assert_eq(#{literal(label)}, " \
    "goosetest::metadata_text(t.results, identity.display_name));\n}\n"
  )
  File.open((project / 'integration/label_test.goose').to_s, 'a') do |stream|
    stream.write("// @DisplayName(#{literal("\x01".b * 1024)})\n" \
                 "fn test_long_label(t: goosetest::Test&) {\n" \
                 "    let identity = t.results.cases[t.current_case].identity;\n" \
                 "    let label = goosetest::metadata_text(t.results, identity.display_name);\n" \
                 "    t.assert_eq(1024, label.len);\n" \
                 "    for byte in label { t.assert_eq(1 as u8, byte); }\n}\n")
  end
  generate(generator, project, env, repo)
  output = build_run(project, work, env, 'native-and-label')
  assert_equal(7, output.scan('PASS ').length, 'native passing rows')
  assert_includes(output, 'Cases: 7 passed')
  assert_equal(authored, [root.read_bytes, sidecar.read_bytes, snapshot(addon)],
               'authored sources changed')

  # Hard failure preserves original attribution and still runs later cases once.
  failed = project / 'test/native_test.goose'
  failed.write_text(failed.read_text.sub('t.assert_eq(42, native_source::value());',
                                         't.assert_eq(99, native_source::value()); print("NEVER");'))
  failed.write_text(failed.read_text.sub('import src.native;',
                                         "import src.native;\nimport std;"))
  generate(generator, project, env, repo)
  output = build_run(project, work, env, 'failure', 1)
  assert_includes(output, 'FAIL test/native_test.goose::native_test::test_native (test/native_test.goose:5)')
  assert(output.include?('expected: <99>') && output.include?('actual: <42>') &&
         !output.include?('NEVER'), 'failure diagnostics')

  # Large fixture forces two dispatch levels; limits/verify.rb checks the original per-root/module caps.
  large = work / 'large project'
  (large / 'src').mkdir(parents: true)
  (large / 'test').mkdir
  (large / 'goosetest_root.goose').write_bytes(root.read_bytes)
  expected = []
  7.times do |mod|
    (large / "src/m#{mod}.goose").write_text("namespace source_#{mod};\n")
    body = "namespace tests_#{mod};\nimport goosetest;\nimport std;\n"
    50.times do |test_case|
      name = "test_#{test_case}"
      body += "fn #{name}(t: goosetest::Test&) { print(\"VISIT #{mod}:#{test_case}\"); " \
              "t.assert_true(true); }\n"
      expected << "VISIT #{mod}:#{test_case}"
    end
    (large / "test/m#{mod}_test.goose").write_text(body)
  end
  generate(generator, large, env, repo)
  assert((large / 'goosetest_generated/dispatch_1_0.goose').exist?)
  output = build_run(large, work, env, 'large')
  assert_equal(expected, output.lines.map(&:chomp).select { |line| line.start_with?('VISIT ') },
               'dispatch visit order')
  assert_equal(350, output.scan('PASS ').length, 'large passing rows')
  assert_includes(output, 'Cases: 350 passed')
  assert_equal(authored, [root.read_bytes, sidecar.read_bytes, snapshot(addon)],
               'authored sources changed after large run')
end
puts 'generation compile tests passed'
