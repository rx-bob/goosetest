# frozen_string_literal: true

# Shared harness support for the independent process/status oracles.
# Every fixture verifier is plain Ruby and owns its disposable resources.

require 'digest'
require 'fileutils'
require 'json'
require 'pathname'
require 'rbconfig'
require 'tempfile'
require 'tmpdir'

module FixtureSupport
  REPO = Pathname.new(File.expand_path('../..', __dir__))
  Result = Struct.new(:status, :stdout, :stderr)

  class Failure < StandardError; end

  module_function

  def repo
    REPO
  end

  def assert(condition, message = nil, context = nil)
    return if condition

    text = message || 'assertion failed'
    text = "#{text}: #{context.inspect}" unless context.nil?
    raise Failure, text
  end

  def assert_equal(expected, actual, message = nil)
    return if expected == actual

    raise Failure, "#{message || 'values differ'}: expected #{expected.inspect} actual #{actual.inspect}"
  end

  def assert_includes(collection, item, message = nil)
    return if collection.include?(item)

    raise Failure, "#{message || 'value missing'}: #{item.inspect} not in #{collection.inspect}"
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def environment(overrides = {})
    ENV.to_h.merge(overrides.transform_keys(&:to_s).transform_values(&:to_s))
  end

  def without_environment(names)
    value = ENV.to_h
    Array(names).each { |name| value.delete(name.to_s) }
    value
  end

  # Run a command with bounded wall time and independent stdout/stderr capture.
  # A timeout is a harness failure unless the caller explicitly inspects it.
  def run_capture(argv, chdir: nil, env: nil, timeout: 120, stdin_data: nil)
    command = argv.map(&:to_s)
    out = Tempfile.new(['goosetest-stdout', '.log'])
    err = Tempfile.new(['goosetest-stderr', '.log'])
    inp = nil
    out.binmode
    err.binmode
    options = { out: out, err: err, pgroup: true }
    options[:chdir] = chdir.to_s unless chdir.nil?
    if env
      options[:unsetenv_others] = true
    end
    unless stdin_data.nil?
      inp = Tempfile.new(['goosetest-stdin', '.bin'])
      inp.binmode
      inp.write(stdin_data)
      inp.rewind
      options[:in] = inp
    end

    spawn_args = env ? [env, *command] : command
    pid = Process.spawn(*spawn_args, options)
    deadline = monotonic + timeout
    status = nil
    loop do
      waited, child_status = Process.waitpid2(pid, Process::WNOHANG)
      if waited
        status = child_status
        break
      end
      if monotonic >= deadline
        kill_group(pid)
        Process.waitpid2(pid)
        raise Failure, "command timed out after #{timeout}s: #{command.inspect}"
      end
      sleep 0.02
    end

    out.rewind
    err.rewind
    stdout = out.read.to_s.b
    stderr = err.read.to_s.b
    code = status.exitstatus || (128 + status.termsig.to_i)
    Result.new(code, stdout, stderr)
  ensure
    inp&.close!
    out&.close!
    err&.close!
  end

  def run_checked(argv, chdir: nil, env: nil, timeout: 120, status: 0, contains: nil,
                  stdin_data: nil)
    result = run_capture(argv, chdir: chdir, env: env, timeout: timeout, stdin_data: stdin_data)
    assert(result.status == status, 'unexpected status',
           [argv, result.status, result.stdout, result.stderr])
    unless contains.nil?
      assert_includes(result.stdout + result.stderr, contains.to_s.b, 'missing output')
    end
    result
  end

  def kill_group(group)
    Process.kill('KILL', -group)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def group_alive?(group)
    Process.kill(0, -group)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def clean_group(group)
    deadline = monotonic + 10
    while group_alive?(group)
      kill_group(group)
      if monotonic >= deadline
        raise Failure, "could not clean owned process group #{group}"
      end
      sleep 0.05
    end
  end

  def process_alive?(pid)
    return true if pid.nil? || pid.zero?

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def stopped?(pid, allow_zombie: false)
    return true if pid.nil? || pid.zero?
    return true unless process_alive?(pid)
    return false unless allow_zombie

    result = run_capture(['/bin/ps', '-p', pid.to_s, '-o', 'stat='], timeout: 3)
    state = result.stdout.strip
    state.empty? || state.start_with?('Z')
  end

  def wait_tree_stopped(pids, timeout: 5)
    deadline = monotonic + timeout
    until pids.each_with_index.all? { |pid, index| stopped?(pid, allow_zombie: index.positive?) }
      assert(monotonic < deadline, 'owned process survived', pids)
      sleep 0.02
    end
  end

  def which(name)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |directory|
      candidate = File.join(directory, name)
      return candidate if File.file?(candidate) && File.executable?(candidate)
    end
    nil
  end

  def ruby_executable
    RbConfig.ruby
  end

  def temp_dir(prefix)
    Dir.mktmpdir(prefix)
  end

  def copy_file(source, destination)
    FileUtils.mkdir_p(File.dirname(destination.to_s))
    FileUtils.copy_file(source.to_s, destination.to_s)
  end

  def copy_tree(source, destination, ignore_names: [])
    source = Pathname.new(source)
    destination = Pathname.new(destination)
    FileUtils.mkdir_p(destination.to_s)
    source.children.sort.each do |child|
      next if ignore_names.include?(child.basename.to_s)

      target = destination / child.basename
      if child.symlink?
        File.symlink(File.readlink(child.to_s), target.to_s)
      elsif child.directory?
        copy_tree(child, target, ignore_names: ignore_names)
      else
        FileUtils.copy_file(child.to_s, target.to_s)
      end
    end
  end

  def recursive_paths(root, pattern = '**/*')
    root = root.to_s
    Dir.glob(File.join(root, pattern), File::FNM_DOTMATCH)
       .reject { |path| %w[. ..].include?(File.basename(path)) }
       .sort
       .map { |path| Pathname.new(path) }
  end

  def digest(path)
    Digest::SHA256.file(path.to_s).hexdigest
  end

  def json_load(path)
    JSON.parse(File.read(path.to_s))
  end

  def json_dump(value)
    JSON.generate(value)
  end

  def materialize_templates(source, destination)
    recursive_paths(source, '**/*.data').each do |template|
      path = destination / template.relative_path_from(Pathname.new(source))
      path = path.with_suffix('')
      FileUtils.mkdir_p(path.dirname.to_s)
      FileUtils.copy_file(template.to_s, path.to_s)
    end
  end

  def check_generated_style(directory, repo, max_line_length: nil)
    directory = Pathname.new(directory)
    run_checked(['goosefmt', 'check', '--config', (Pathname.new(repo) / '.goosefmt.toml').to_s,
                 directory.to_s], timeout: 15)
    recursive_paths(directory, '*.goose').each do |path|
      lines = File.read(path.to_s).lines.map(&:chomp)
      assert(lines.length <= 500, 'generated file exceeds line budget', path)
      starts = lines.each_index.select { |index| lines[index].start_with?('fn ') } + [lines.length]
      starts.each_cons(2) do |first, last|
        function = lines[first...last].join("\n").rstrip
        assert(function.lines.length <= 70, 'generated function exceeds line budget', [path, first])
      end
      if max_line_length
        assert(lines.all? { |line| line.length <= max_line_length }, 'generated line too long', path)
      end
    end
  end

  class OwnedProcess
    attr_reader :pid

    def initialize(argv, chdir: nil, env: nil)
      @stdout_file = Tempfile.new(['goosetest-owned-stdout', '.log'])
      @stderr_file = Tempfile.new(['goosetest-owned-stderr', '.log'])
      @stdout_file.binmode
      @stderr_file.binmode
      options = { out: @stdout_file, err: @stderr_file, pgroup: true }
      options[:chdir] = chdir.to_s unless chdir.nil?
      options[:unsetenv_others] = true if env
      command = argv.map(&:to_s)
      @pid = Process.spawn(*(env ? [env, *command] : command), options)
      @status = nil
    end

    def poll
      return @status unless @status.nil?

      waited, status = Process.waitpid2(pid, Process::WNOHANG)
      @status = status if waited
      @status
    end

    def returncode
      status = poll
      return nil if status.nil?

      status.exitstatus || (128 + status.termsig.to_i)
    end

    def signal(sig)
      Process.kill(sig, pid)
    end

    def kill
      Process.kill('KILL', pid)
    rescue Errno::ESRCH
      nil
    end

    def communicate(timeout: 10)
      deadline = FixtureSupport.monotonic + timeout
      until poll
        if FixtureSupport.monotonic >= deadline
          kill
          Process.waitpid2(pid) unless poll
          raise Failure, "owned process did not finish: #{pid}"
        end
        sleep 0.02
      end
      [read_out, read_err]
    end

    def wait(timeout: 10)
      communicate(timeout: timeout)
      returncode
    end

    def read_out
      @stdout_file.rewind
      @stdout_file.read.to_s.b
    end

    def read_err
      @stderr_file.rewind
      @stderr_file.read.to_s.b
    end

    def close
      @stdout_file.close!
      @stderr_file.close!
    end
  end
end

# Harness conveniences keep the Ruby verifiers direct while remaining ordinary
# stdlib Pathname behavior.
class Pathname
  def read_text
    File.read(to_s)
  end

  def write_text(data)
    File.write(to_s, data)
  end

  def read_bytes
    File.binread(to_s)
  end

  def write_bytes(data)
    File.binwrite(to_s, data)
  end

  def rglob(pattern)
    FixtureSupport.recursive_paths(self, pattern)
  end

  def with_suffix(suffix)
    base = to_s.sub(/\.[^.\/]+\z/, '')
    Pathname.new(suffix.to_s.empty? ? base : base + suffix)
  end

  def symlink_to(target)
    File.symlink(target.to_s, to_s)
  end

  def chmod(mode)
    File.chmod(mode, to_s)
  end

  def mkdir(parents: false)
    parents ? FileUtils.mkdir_p(to_s) : Dir.mkdir(to_s)
  end

  def rmtree
    FileUtils.rm_rf(to_s)
  end

  def unlink(missing_ok: false)
    return if missing_ok && !exist?

    File.unlink(to_s)
  end

  def is_file?
    file?
  end

  def is_dir?
    directory?
  end

  def is_symlink?
    symlink?
  end

  def glob(pattern)
    FixtureSupport.recursive_paths(self, pattern)
  end
end

include FixtureSupport
