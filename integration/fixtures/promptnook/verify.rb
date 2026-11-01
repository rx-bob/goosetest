# frozen_string_literal: true

# Verify a Promptnook-shaped domain/native split without application services.

require_relative '../support'

cli = Pathname.new(ARGV.fetch(0)).expand_path
fixture = Pathname.new(__dir__)
repo = fixture.parent.parent.parent
DOMAIN_ID = 'core::tests/core/workspace_tree_test.goose::workspace_tree_test::' \
            'test_workspace_tree_order_and_nesting'
DATABASE_ID = 'database::tests/database/native_state_test.goose::native_state_test::' \
              'test_native_resource_is_open_during_body'
RESOURCE = 'db/goosetest-owned.fixture'

def run_fixture(argv, cwd, env, status = 0)
  result = run_capture(argv, chdir: cwd, env: env, timeout: 240)
  assert(result.status == status, 'unexpected status',
         [argv, result.status, result.stdout, result.stderr])
  result
end

def append_snapshot(project, template, snapshot, fixture)
  target = project / template
  target.parent.mkdir(parents: true)
  target.write_bytes(target.read_bytes + (fixture / snapshot).read_bytes)
end

manifest = json_load(fixture / 'provenance.json')
manifest['snapshots'].each do |record|
  assert_equal(record['sha256'], digest(fixture / record['snapshot']), 'snapshot digest')
end

Dir.mktmpdir('goosetest-promptnook-adoption-') do |temporary|
  work = Pathname.new(temporary).realpath
  project = work / 'promptnook-shaped consumer'
  project.mkdir
  (work / 'goosetest').symlink_to(repo)
  env = environment('GOOSE_HOME' => (work / 'cache').to_s)

  # Keep application-shaped paths at project root; only selected pure source
  # declarations are snapshotted into these modules.
  materialize_templates(fixture / 'consumer', project)
  (project / 'users').mkdir
  append_snapshot(project, 'workspaces/tree.goose', 'production/workspaces/tree.goose.data', fixture)
  append_snapshot(project, 'mcp_protocol/json_parser.goose',
                  'production/mcp_protocol/json_member_last.goose.data', fixture)
  (project / 'goosetest.json').write_text(json_dump(
    'version' => 1,
    'targets' => [
      { 'name' => 'core', 'entry' => 'goosetest_core.goose',
        'tests' => [{ 'path' => 'tests/core', 'kind' => 'unit' }],
        'mirror' => { 'policy' => 'off', 'pairs' => [] } },
      { 'name' => 'database', 'entry' => 'goosetest_database.goose',
        'tests' => [{ 'path' => 'tests/database', 'kind' => 'integration' }],
        'mirror' => { 'policy' => 'off', 'pairs' => [] } }
    ]
  ))

  %w[users workspaces db tests/core tests/database].each do |path|
    assert((project / path).directory?, 'missing project directory', path)
  end
  listed = run_fixture([cli, 'list', '--project', project, '--target', 'core'], work, env)
  ids = listed.stdout.force_encoding('UTF-8').scan(/^(?:unit|integration)  (\S+)  \(/).flatten
  assert_equal([DOMAIN_ID], ids, 'domain inventory')

  # Core remains independent from the deliberately absent database link input.
  %w[debug optimized].each do |profile|
    args = [cli, 'test', '--project', project, '--target', 'core', '--profile', profile, '--offline']
    result = run_fixture(args, work, env)
    assert_includes(result.stdout, "PASS #{DOMAIN_ID} (".b, "domain run #{profile}")
    assert_includes(result.stdout, '1 passed, 0 failed'.b)
    assert(!(project / 'goosetest_generated/database/tests').exist?)
    assert(!(project / RESOURCE).exist?)
  end

  missing = run_fixture([cli, 'test', '--project', project, '--target', 'database',
                         '--profile', 'debug'], work, env, 2)
  assert_includes(missing.stderr, 'compilation for target database'.b)
  assert_includes(missing.stderr, 'unavailable_libsql.c'.b)
  assert(!(project / 'goosetest_generated/database/completion').exist?)

  # This placeholder satisfies only the stand-in's optional link boundary; it
  # is not libSQL and the test never imports or calls Promptnook database code.
  optional_source = project / 'db/unavailable_libsql.c'
  optional_source.write_text("int pn_fixture_optional_database_link(void) { return 1; }\n")
  2.times do |invocation|
    result = run_fixture([cli, 'test', '--project', project, '--target', 'database',
                          '--profile', 'debug'], work, env)
    assert_includes(result.stdout, "PASS #{DATABASE_ID} (".b, "database run #{invocation}")
    assert_includes(result.stdout, '1 passed, 0 failed'.b)
    assert(!(project / RESOURCE).exist?, 'database fixture must remove its owned resource')
  end

  # Core can be rerun after the database target without importing its sidecar.
  run_fixture([cli, 'test', '--project', project, '--target', 'core',
               '--profile', 'optimized', '--offline'], work, env)
  assert(!(project / RESOURCE).exist?)
end
puts 'Promptnook-shaped adoption passed: unchanged tree behavior, core/database isolation, fresh native state, owned resource cleanup'
