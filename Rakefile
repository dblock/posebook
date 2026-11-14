# frozen_string_literal: true

require_relative 'config/application'

Rails.application.load_tasks

desc 'Lint Ruby, Markdown, spelling, and workflow display names'
# rubocop:disable Rails/RakeEnvironment -- Tooling tasks must not initialize Rails or connect to MongoDB.
task :lint do
  sh 'bundle exec rubocop'
  ruby 'script/lint_workflows.rb', *Dir.glob('.github/workflows/*.{yml,yaml}')
end

desc 'Build and smoke test the application Docker image'
task :package do
  ruby 'bin/package'
end
# rubocop:enable Rails/RakeEnvironment

task default: %i[spec lint]
