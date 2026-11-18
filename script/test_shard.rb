# frozen_string_literal: true

index, count, seed = ARGV.shift(3).map { |value| Integer(value, 10, exception: false) }
abort 'Usage: ruby script/test_shard.rb INDEX COUNT SEED [spec options]' unless
  index && count&.positive? && index.between?(0, count - 1) && seed

files = Dir.glob('spec/**/*_spec.rb').shuffle(random: Random.new(seed))
shard = files.each_with_index.filter_map { |file, position| file if position % count == index }
abort "No spec files assigned to shard #{index + 1} of #{count}" if shard.empty?

puts "Running shard #{index + 1} of #{count} with #{shard.size} spec files (seed #{seed})"
exec 'bundle', 'exec', 'rspec', *ARGV, *shard # rubocop:disable Spellcheck/Spelling -- Executable name.
