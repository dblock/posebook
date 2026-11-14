# frozen_string_literal: true

require 'yaml'

# Checks only human-facing GitHub Actions workflow, job, and step names.
module WorkflowNames
  MINOR_WORDS = %w[a an and as at but by for from in nor of on or per the to via vs with].freeze

  module_function

  def title_case?(name)
    words = name.gsub(/\$\{\{.*?\}\}/, '').scan(/[[:alpha:]][[:alnum:]]*/)
    words.each_with_index.all? do |word, index|
      if MINOR_WORDS.include?(word.downcase) && index.positive? && index < words.length - 1
        word == word.downcase
      else
        word[0] == word[0].upcase
      end
    end
  end

  def names(workflow)
    result = [workflow['name']]
    workflow.fetch('jobs', {}).each_value do |job|
      result << job['name']
      job.fetch('steps', []).each { |step| result << step['name'] }
    end
    result.compact
  end

  def offenses(path)
    workflow = YAML.safe_load_file(path)
    names(workflow).filter_map do |name|
      "#{path}: Use Title Case for display name #{name.inspect}" unless name.is_a?(String) && title_case?(name)
    end
  rescue Psych::Exception => e
    ["#{path}: #{e.message}"]
  end
end

if $PROGRAM_NAME == __FILE__
  errors = ARGV.flat_map { |path| WorkflowNames.offenses(path) }
  warn errors.join("\n") unless errors.empty?
  exit(errors.empty? ? 0 : 1)
end
