# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'

# rubocop:disable-next RSpec/DescribeClass -- Workflow shell behavior has no Ruby class.
RSpec.describe 'CI coverage collection', :aggregate_failures do
  let(:script) do
    workflow = YAML.safe_load_file('.github/workflows/test.yml')
    workflow.dig('jobs', 'test', 'steps').find { |step| step['name'] == 'Combine Coverage Reports' }.fetch('run')
  end

  def with_reports
    Dir.mktmpdir('posebook-ci-coverage') do |temporary|
      directory = File.realpath(temporary)
      FileUtils.cp('.simplecov', directory)
      FileUtils.mkdir_p("#{directory}/app")
      File.write("#{directory}/app/example.rb", "true\nfalse\n")
      yield directory
    end
  end

  def write_report(directory, shard, attempt, lines)
    path = "#{directory}/tmp/test-coverage/posebook-test-#{shard}-#{attempt}"
    FileUtils.mkdir_p(path)
    data = { 'RSpec' => { 'coverage' => { "#{directory}/app/example.rb" => { 'lines' => lines } },
                          'timestamp' => Time.now.to_i } }
    File.write("#{path}/.resultset.json", JSON.generate(data))
  end

  def collect(directory)
    env = { 'SHARD_COUNT' => '2', 'BUNDLE_GEMFILE' => File.expand_path('Gemfile') }
    Open3.capture3(env, 'bash', '-e', '-o', 'pipefail', '-c', script, chdir: directory)
  end

  it 'combines only the latest attempt per shard, including earlier successful workers' do
    with_reports do |directory|
      write_report(directory, 1, 2, [9, 9])
      write_report(directory, 1, 10, [1, 0])
      write_report(directory, 2, 1, [0, 1])
      _output, error, status = collect(directory)
      expect(status).to be_success, error
      data = JSON.parse(File.read("#{directory}/coverage/.resultset.json"))
      expect(data.values.first.fetch('coverage').values.first.fetch('lines')).to eq([1, 1])
      expect(File).to exist("#{directory}/coverage/lcov.info")
    end
  end

  it 'fails rather than uploading incomplete coverage when a shard report is missing' do
    with_reports do |directory|
      write_report(directory, 1, 1, [1, 0])
      _output, _error, status = collect(directory)
      expect(status).not_to be_success
    end
  end
end
