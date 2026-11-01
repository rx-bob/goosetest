# frozen_string_literal: true

# Run independent failure/completeness oracles with parent-owned resource cleanup.

require_relative 'support'

REPO = Pathname.new(__dir__).parent.parent
MAX_LOG_BYTES = 8 * 1024 * 1024
STAGE_SECONDS = 900

def run_owned(label, argv, env, work)
  output = Tempfile.new(['goosetest-owned', '.log'])
  output.binmode
  pid = Process.spawn(env, *argv.map(&:to_s), out: output, err: output, pgroup: true,
                      unsetenv_others: true)
  problem = nil
  reaped = false
  begin
    deadline = FixtureSupport.monotonic + STAGE_SECONDS
    status = nil
    loop do
      waited, child_status = Process.waitpid2(pid, Process::WNOHANG)
      if waited
        status = child_status
        reaped = true
        break
      end
      if FixtureSupport.monotonic >= deadline
        problem = 'parent deadline exceeded'
        break
      end
      if File.size(output.path) > MAX_LOG_BYTES
        problem = 'parent output budget exceeded'
        break
      end
      sleep 0.05
    end
    if problem
      FixtureSupport.kill_group(pid)
      _, status = Process.waitpid2(pid)
      reaped = true
    end
    size = File.size(output.path)
    problem = 'parent output budget exceeded' if size > MAX_LOG_BYTES
    text = File.binread(output.path, MAX_LOG_BYTES).to_s.force_encoding('UTF-8').scrub
    return_code = status.exitstatus || (128 + status.termsig.to_i)
    if problem || return_code != 0
      raise FixtureSupport::Failure, "#{label}: #{problem || "exit #{return_code}"}\n#{text}"
    end
    if FixtureSupport.group_alive?(pid)
      raise FixtureSupport::Failure, "#{label}: owned process group survived: #{pid}\n#{text}"
    end
    $stdout.puts("PASS oracle: #{label}")
    $stdout.flush
  ensure
    unless reaped
      FixtureSupport.kill_group(pid)
      Process.waitpid(pid) rescue nil
    end
    FixtureSupport.clean_group(pid)
    output.close!
  end
end

def main
  Dir.mktmpdir('goosetest-verification-') do |temporary|
    work = Pathname.new(temporary)
    scratch = work / 'scratch'
    scratch.mkdir
    env = FixtureSupport.environment(
      'GOOSE_HOME' => (work / 'cache').to_s,
      'TMPDIR' => scratch.to_s,
      'RUBYOPT' => '',
      'RUBYLIB' => ''
    )
    cli = work / 'goosetest'
    oracle = work / 'cli-oracle'
    process_oracle = work / 'process-oracle'
    process_child = work / 'process-child'
    [['main.goose', cli],
     ['test_support/oracles/cli_test.goose', oracle],
     ['test_support/oracles/process_test.goose', process_oracle]].each do |source, binary|
      run_owned("build #{source}", ['goose', 'build', '--debug', REPO / source, '-o', binary],
                env, work)
    end
    run_owned('build process child',
              ['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
               REPO / 'integration/fixtures/process/child.c', '-o', process_child], env, work)
    matrices = [
      ['self_host', [cli]], ['cli', [cli, oracle]], ['execution', [cli]],
      ['artifacts', [cli]], ['limits', [cli]], ['configured', [cli]], ['targets', [cli]],
      ['profiles', [cli]],
      ['process', [process_oracle, process_child]],
      ['disabled', [cli]],
      ['selection', [cli]], ['lifecycle', [cli]], ['suite', [cli]],
      ['goosefmt', [cli]], ['silly', [cli]],
      ['promptnook', [cli]]
    ]
    matrices.each do |name, arguments|
      path = REPO / 'integration' / 'fixtures' / name / 'verify.rb'
      run_owned(name, [FixtureSupport.ruby_executable, path, *arguments], env, work)
    end
  end
  puts 'independent self-host and failure-contract verification passed'
end

main
