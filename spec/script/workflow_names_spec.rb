# frozen_string_literal: true

require 'open3'
require 'tempfile'
require_relative '../../script/lint_workflows'

RSpec.describe WorkflowNames, :aggregate_failures do
  def with_workflow(contents)
    Tempfile.create(['workflow', '.yml']) do |file|
      file.write(contents)
      file.flush
      yield file.path
    end
  end

  let(:invalid_names) do
    <<~YAML
      name: run tests
      jobs:
        lowercase_job:
          name: Run tests
          environment:
            name: production
          steps:
            - name: Run tests
              uses: owner/action@v1
            - uses: owner/action@v1
    YAML
  end

  describe '.title_case?' do
    it 'accepts minor words, proper names, acronyms, and expressions' do
      expect(described_class.title_case?('Set Up Ruby and MongoDB')).to be(true)
      expect(described_class.title_case?('Test Ruby ${{ matrix.entry.ruby }}')).to be(true)
    end

    it 'rejects lowercase major words and capitalized internal minor words' do
      expect(described_class.title_case?('Run tests')).to be(false)
      expect(described_class.title_case?('Setup And Validation')).to be(false)
    end
  end

  describe '.offenses' do
    it 'checks workflow, job, and step display names, not identifiers or arbitrary name fields' do
      with_workflow(invalid_names) do |path|
        expect(described_class.offenses(path).length).to eq(3)
      end
    end

    it 'accepts a workflow with no display names' do
      with_workflow("jobs:\n  test:\n    runs-on: ubuntu-latest\n") do |path|
        expect(described_class.offenses(path)).to be_empty
      end
    end

    it 'accepts title-case display names' do
      with_workflow("name: Run Tests\n") do |path|
        expect(described_class.offenses(path)).to be_empty
      end
    end

    it 'reports malformed YAML' do
      with_workflow('jobs: [') do |path|
        expect(described_class.offenses(path).first).to include(path, 'did not find')
      end
    end

    it 'rejects non-string display names' do
      with_workflow("name: 123\n") do |path|
        expect(described_class.offenses(path).first).to include('123')
      end
    end
  end

  it 'exits unsuccessfully with diagnostics for an invalid display name' do
    with_workflow("name: run tests\n") do |path|
      _output, error, status = Open3.capture3('ruby', 'script/lint_workflows.rb', path)
      expect(status.exitstatus).to eq(1)
      expect(error).to include('Use Title Case')
    end
  end

  it 'exits successfully for valid display names' do
    with_workflow("name: Run Tests\n") do |path|
      _output, error, status = Open3.capture3('ruby', 'script/lint_workflows.rb', path)
      expect(status).to be_success
      expect(error).to be_empty
    end
  end
end
