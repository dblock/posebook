# frozen_string_literal: true

# Validates timing snapshots before all CI workers choose the same grouping mode.
module TestRuntimeLog
  module_function

  def entry(line)
    file, separator, duration = line.chomp.rpartition(':')
    seconds = Float(duration)
    if separator.empty? || file.empty? || !seconds.finite? || seconds.negative?
      raise ArgumentError, 'Invalid test timing'
    end

    [file, seconds]
  end

  def read(paths)
    raise ArgumentError, 'No runtime logs supplied' if paths.empty?

    entries = paths.flat_map { |path| File.readlines(path).map { |line| entry(line) } }
    raise ArgumentError, 'Duplicate test timings' unless entries.map(&:first).uniq.length == entries.length

    entries.to_h
  end

  def group_by(path, files = Dir.glob('spec/**/*_spec.rb'))
    timings = read([path])
    known = files.count { |file| timings.key?(file) }
    known.positive? && known * 2 >= files.length ? 'runtime' : 'filesize'
  rescue Errno::ENOENT, ArgumentError => e
    warn "Test timings unavailable (#{e.message}); using file-size groups."
    'filesize'
  end
end

if $PROGRAM_NAME == __FILE__
  case ARGV.shift
  when 'group-by'
    puts TestRuntimeLog.group_by(ARGV.fetch(0))
  when 'combine'
    puts(TestRuntimeLog.read(ARGV).sort.map { |file, seconds| "#{file}:#{seconds}" })
  else
    abort 'Usage: ruby script/test_runtime_log.rb group-by LOG | combine LOG...'
  end
end
