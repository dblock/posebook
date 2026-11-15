# frozen_string_literal: true

require 'open3'

RSpec.describe 'bin/package', :aggregate_failures do # rubocop:disable RSpec/DescribeClass -- Executable script, not a class.
  let(:commands) { [] }
  let(:script) { Object.new }
  let(:success) { instance_double(Process::Status, success?: true) }

  before do
    stub_const(:ARGV.to_s, ['--image', 'posebook-package:existing'])
    allow(script).to receive(:puts)
    allow(Open3).to receive(:capture3) do |*command|
      commands << command
      raise 'Simulated package failure' if command[1] == failing_command

      output = case command[1]
               when 'network' then 'package-network'
               when 'run' then command.include?('mongo:8.0') ? 'package-database' : 'package-application'
               when 'inspect' then 'healthy'
               when 'exec' then 'true'
               else ''
               end
      [output, '', success]
    end
  end

  def run_package
    script.instance_eval(File.read('bin/package'), 'bin/package')
  end

  context 'when database setup fails' do
    let(:failing_command) { 'exec' }

    it 'removes the database and its anonymous volumes without pruning unrelated resources' do
      expect { run_package }.to raise_error('Simulated package failure')
      expect(commands.select { |command| command[1] == 'rm' }).to eq(
        [%w[docker rm --force --volumes package-database]]
      )
      expect(commands.last).to eq(%w[docker network rm package-network])
    end
  end

  context 'when application setup fails' do
    let(:failing_command) { 'port' }

    it 'removes both containers and their anonymous volumes while preserving the supplied image' do
      expect { run_package }.to raise_error('Simulated package failure')
      expect(commands.select { |command| command[1] == 'rm' }).to eq(
        [%w[docker rm --force --volumes package-application], %w[docker rm --force --volumes package-database]]
      )
      expect(commands.last).to eq(%w[docker network rm package-network])
      expect(commands).not_to include(%w[docker image rm posebook-package:existing])
    end
  end
end
