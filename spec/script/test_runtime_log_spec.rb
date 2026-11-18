# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tempfile'
require 'tmpdir'
require 'yaml'
require_relative '../../script/test_runtime_log'

RSpec.describe TestRuntimeLog, :aggregate_failures do
  def with_log(contents)
    Tempfile.create(['runtimes', '.log']) do |file|
      file.write(contents)
      file.flush
      yield file.path
    end
  end

  let(:files) { %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb spec/d_spec.rb] }

  it 'uses timings with sufficient current files, ignoring deleted files and estimating new files' do
    with_log("spec/a_spec.rb:10\nspec/b_spec.rb:0\nspec/deleted_spec.rb:90\n") do |path|
      expect(described_class.group_by(path, files)).to eq('runtime')
    end
  end

  it 'uses file sizes when too few current files have timings' do
    with_log("spec/a_spec.rb:10\nspec/deleted_spec.rb:90\n") do |path|
      expect(described_class.group_by(path, files)).to eq('filesize')
    end
  end

  it 'uses file sizes for empty or malformed reports' do
    # rubocop:disable-next Spellcheck/Spelling -- Invalid numeric fixtures exercise report validation.
    ['', 'broken', 'spec/a_spec.rb:-1', 'spec/a_spec.rb:Infinity', 'spec/a_spec.rb:NaN',
     "spec/a_spec.rb:1\nspec/a_spec.rb:2\n"].each do |contents|
      with_log(contents) do |path|
        expect(described_class.group_by(path, files)).to eq('filesize')
      end
    end
  end

  it 'uses file sizes when the timing artifact is absent' do
    with_log('') do |path|
      output, _error, status = Open3.capture3('ruby', 'script/test_runtime_log.rb', 'group-by', "#{path}.missing")
      expect(status).to be_success
      expect(output).to eq("filesize\n")
    end
  end

  it 'combines disjoint shard logs into a deterministic report through the CLI' do
    with_log("spec/b_spec.rb:20\n") do |second|
      with_log("spec/a_spec.rb:10\n") do |first|
        output, error, status = Open3.capture3('ruby', 'script/test_runtime_log.rb', 'combine', second, first)
        expect(status).to be_success
        expect(error).to be_empty
        expect(output).to eq("spec/a_spec.rb:10.0\nspec/b_spec.rb:20.0\n")
      end
    end
  end

  it 'rejects duplicate measurements rather than publishing an ambiguous baseline' do
    with_log("spec/a_spec.rb:10\n") do |path|
      _output, error, status = Open3.capture3('ruby', 'script/test_runtime_log.rb', 'combine', path, path)
      expect(status).not_to be_success
      expect(error).to include('Duplicate test timings')
    end
  end

  describe 'workflow history restoration' do
    let(:restore_step) do
      workflow = YAML.safe_load_file('.github/workflows/test.yml')
      workflow.dig('jobs', 'history', 'steps').find { |step| step['id'] == 'history' }.fetch('run')
    end
    let(:github_cli) do
      # rubocop:disable-next Spellcheck/Spelling -- This heredoc is executable Ruby for a fake GitHub CLI.
      <<~RUBY
        #!/usr/bin/env ruby
        File.open('calls', 'a') { |file| file.puts(ARGV.join(' ')) }
        mode = ENV.fetch('HISTORY_TEST_MODE')
        exit 1 if mode == 'unavailable'
        if ARGV.first == 'api'
          if ARGV[1].include?('workflows/test.yml/runs?')
            puts "102\\n101"
          elsif ARGV[1].include?('/101/artifacts') && mode != 'expired'
            puts '500'
          end
        else
          File.write('tmp/test-runtime-history/runtimes.log', "spec/a_spec.rb:10\\nspec/b_spec.rb:20\\n")
          exit 1 if mode == 'download-failure'
        end
      RUBY
    end

    def prepare_restore(directory)
      FileUtils.mkdir_p(["#{directory}/script", "#{directory}/spec"])
      FileUtils.cp('script/test_runtime_log.rb', "#{directory}/script")
      File.write("#{directory}/gh", github_cli)
      File.chmod(0o755, "#{directory}/gh")
      %w[a b].each { |name| File.write("#{directory}/spec/#{name}_spec.rb", '') }
    end

    def restore_history(mode)
      Dir.mktmpdir('posebook-timing-history') do |directory|
        prepare_restore(directory)
        env = { 'PATH' => "#{directory}:#{ENV.fetch('PATH')}", 'GH_REPO' => 'example/posebook',
                'GITHUB_OUTPUT' => "#{directory}/outputs", 'HISTORY_TEST_MODE' => mode }
        command = ['bash', '-e', '-o', 'pipefail', '-c', restore_step]
        _output, _error, status = Open3.capture3(env, *command, chdir: directory)
        expect(status).to be_success
        [File.read("#{directory}/outputs"), File.read("#{directory}/calls")]
      end
    end

    it 'selects one retained master baseline and enables runtime grouping' do
      output, calls = restore_history('available')
      expect(output).to eq("group_by=runtime\n")
      expect(calls).to include('branch=master&event=push&status=success', 'run download 101')
      expect(calls).not_to include('run download 102')
    end

    it 'selects filesize grouping for every worker when history cannot be restored' do
      %w[unavailable expired download-failure].each do |mode|
        output, _calls = restore_history(mode)
        expect(output).to eq("group_by=filesize\n")
      end
    end
  end
end
