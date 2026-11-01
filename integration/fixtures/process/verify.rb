# frozen_string_literal: true

# External lifecycle oracle; adapter results alone cannot establish child cleanup.

require_relative '../support'

driver, child = ARGV[0, 2].map { |value| Pathname.new(value).expand_path }

def record_from(output)
  line = output.force_encoding('UTF-8').lines.last.to_s.strip
  fields = line.split
  assert(fields[0] == 'RESULT', 'missing RESULT record', output)
  {
    'kind' => fields[1],
    'code' => fields[2].to_i,
    'signal' => fields[3].to_i,
    'error' => fields[4].to_i,
    'pid' => fields[5].to_i,
    'reaped' => fields[6],
    'cleanup' => fields[7].to_i
  }
end

def check_reaped(record)
  assert(record['reaped'] == 'true' && record['cleanup'].zero?,
         'child was not reaped', record)
  assert(stopped?(record['pid']), 'child survived', record)
end

def invoke(driver, cwd, executable, *args, scenario: 'normal', environment: nil)
  response = run_capture([driver, scenario, cwd, executable, *args],
                         env: environment, timeout: 8)
  assert(response.status.zero?, 'driver failed', response.stderr)
  [response, record_from(response.stdout)]
end

Dir.mktmpdir('goosetest-process-') do |temporary|
  root = Pathname.new(temporary).realpath
  cwd = root / 'cwd space "quote" $cash;semi'
  cwd.mkdir
  executable = cwd / 'child space "quote" $cash;semi'
  copy_file(child, executable)
  arguments = ['', 'space value', 'double"quote', "single'quote", '$HOME',
               'a;touch injected', '\\slash', "line\nbreak"]
  response, record = invoke(driver, cwd, executable, 'echo', *arguments)
  expected = "cwd=#{cwd}\n" + arguments.map { |value| "arg=#{value}\n" }.join
  assert(response.stdout.start_with?(expected.b), 'argv/cwd mismatch', response.stdout)
  assert_equal("child stderr inherited\n".b, response.stderr, 'stderr mismatch')
  assert(record['kind'] == 'exit' && record['code'].zero?, 'unexpected exit', record)
  check_reaped(record)
  assert(!(cwd / 'injected').exist?, 'shell injection ran')

  inherited = run_capture([driver, 'normal', cwd, executable, 'stdin'],
                          stdin_data: "inherited input\n", timeout: 8)
  assert(inherited.status.zero? &&
         inherited.stdout.start_with?('stdin=inherited input' + "\n"),
         'stdin was not inherited')
  check_reaped(record_from(inherited.stdout))

  [nil, ''].each do |inherited_home|
    environment = ENV.to_h
    if inherited_home.nil?
      environment.delete('GOOSE_HOME')
    else
      environment['GOOSE_HOME'] = inherited_home
    end
    response = run_capture([driver, 'goose-home', cwd, executable,
                            'isolated compiler cache', root / 'compiler cache'],
                           env: environment, timeout: 8)
    assert(response.status.zero?, 'goose-home scenario failed',
           [response.stdout, response.stderr])
    check_reaped(record_from(response.stdout))
  end

  oversized_environment = ENV.to_h
  4100.times { |index| oversized_environment["GT_CACHE_ENV_#{index}"] = 'x' }
  response = run_capture([driver, 'goose-home', cwd, executable,
                          'isolated compiler cache', root / 'compiler cache'],
                         env: oversized_environment, timeout: 8)
  assert(response.status.zero?, 'oversized environment scenario failed', response.stderr)
  rejected = record_from(response.stdout)
  assert(rejected['kind'] == 'invalid' && rejected['error'] != 0 && rejected['pid'].zero?,
         'oversized environment was not rejected', rejected)

  duplicate_env = root / 'duplicate-env-launcher'
  duplicate_source = Pathname.new(__dir__) / 'duplicate_env.c'
  run_checked(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
               duplicate_source, '-o', duplicate_env], timeout: 30)
  response = run_capture([duplicate_env, driver, cwd, executable], timeout: 8)
  assert(response.status.zero?, 'duplicate-env launcher failed',
         [response.stdout, response.stderr])
  check_reaped(record_from(response.stdout))

  _, relative = invoke(driver, cwd, './' + executable.basename.to_s, 'exit', '7')
  assert(relative['kind'] == 'exit' && relative['code'] == 7, 'relative executable', relative)
  check_reaped(relative)

  environment = ENV.to_h.merge('PATH' => cwd.to_s)
  _, searched = invoke(driver, cwd, executable.basename.to_s, 'exit', '127',
                       environment: environment)
  assert(searched['kind'] == 'exit' && searched['code'] == 127, 'PATH search', searched)
  check_reaped(searched)

  _, missing = invoke(driver, cwd, cwd / 'missing', 'exit', '0')
  assert(missing['kind'] == 'launch' && missing['error'] == Errno::ENOENT::Errno,
         'missing executable', missing)
  assert(missing['pid'].zero? && missing['reaped'] == 'false', 'missing executable record', missing)

  script = cwd / 'not-an-executable-format'
  script.write_text("touch shell-fallback-ran\n")
  script.chmod(0o755)
  _, no_shell = invoke(driver, cwd, script, 'unused')
  assert(no_shell['kind'] == 'launch' && no_shell['error'] == Errno::ENOEXEC::Errno,
         'ENOEXEC handling', no_shell)
  assert(!(cwd / 'shell-fallback-ran').exist?, 'shell fallback ran')
  _, no_shell_path = invoke(driver, cwd, script.basename.to_s, 'unused', environment: environment)
  assert(no_shell_path['kind'] == 'launch' && no_shell_path['error'] == Errno::ENOEXEC::Errno,
         'PATH ENOEXEC handling', no_shell_path)
  assert(!(cwd / 'shell-fallback-ran').exist?, 'PATH shell fallback ran')

  started = FixtureSupport.monotonic
  _, search_timeout = invoke(driver, cwd, 'missing-in-every-path-entry', 'unused',
                             scenario: 'deadline',
                             environment: ENV.to_h.merge('PATH' => ':' * 60_000))
  assert(search_timeout['kind'] == 'deadline' && search_timeout['pid'].zero?,
         'PATH search deadline', search_timeout)
  assert(FixtureSupport.monotonic - started < 2, 'PATH search deadline was too slow')

  _, signaled = invoke(driver, cwd, executable, 'signal')
  assert(signaled['kind'] == 'signal' && signaled['signal'] == Signal.list.fetch('USR1'),
         'signal termination', signaled)
  check_reaped(signaled)

  [['deadline', 'wait', nil], ['deadline', 'tree', nil],
   ['normal', 'tree', Signal.list.fetch('INT')],
   ['normal', 'graceful', Signal.list.fetch('TERM')],
   ['normal', 'orphan', nil]].each do |scenario, mode, cancellation|
    ready = root / (scenario + mode + (cancellation.nil? ? 'none' : cancellation.to_s))
    process = FixtureSupport::OwnedProcess.new(
      [driver, scenario, cwd, executable, mode, ready]
    )
    started = FixtureSupport.monotonic
    pids = []
    begin
      ready_by = started + 3
      while FixtureSupport.monotonic < ready_by
        if ready.exist? && ready.read_text.split.length == 2
          pids = ready.read_text.split.map(&:to_i)
          break
        end
        assert(process.poll.nil?, 'driver exited before readiness', process.read_out)
        sleep 0.005
      end
      assert(!pids.empty?, 'child never became ready')
      process.signal(cancellation) if cancellation
      stdout, stderr = process.communicate(timeout: 3)
      elapsed = FixtureSupport.monotonic - started
      assert(process.returncode.zero? && stderr.empty?, 'driver failed', [stdout, stderr])
      record = record_from(stdout)
      expected_kind = if mode == 'orphan'
                        'exit'
                      elsif cancellation
                        'cancel'
                      else
                        'deadline'
                      end
      assert_equal(expected_kind, record['kind'], 'unexpected lifecycle kind')
      assert_equal(0, record['code'], 'orphan exit code') if mode == 'orphan'
      assert_equal(cancellation, record['signal'], 'cancellation signal') if cancellation
      assert(elapsed < 2, 'deadline/grace exceeded generous scheduling allowance', elapsed)
      check_reaped(record)
      until_at = FixtureSupport.monotonic + 2
      while !pids.all? { |pid| stopped?(pid, allow_zombie: true) } &&
            FixtureSupport.monotonic < until_at
        sleep 0.01
      end
      assert(pids.all? { |pid| stopped?(pid, allow_zombie: true) }, 'descendant survived', pids)
    ensure
      if !process.poll.nil?
        process.close
      else
        process.kill
        process.wait(timeout: 5)
        process.close
      end
      pids.each do |pid|
        begin
          Process.kill('KILL', pid) if pid.positive? && !stopped?(pid, allow_zombie: true)
        rescue Errno::ESRCH
          nil
        end
      end
    end
  end
end
puts 'process lifecycle tests passed'
