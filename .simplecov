# frozen_string_literal: true

require 'simplecov-lcov'

SimpleCov::Formatter::LcovFormatter.config do |config|
  config.report_with_single_file = true
  config.single_report_path = 'coverage/lcov.info'
end

SimpleCov.configure do
  formatters [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::LcovFormatter]
  enable_coverage :branch
  cover 'app/**/*.rb', 'script/**/*.rb'
end
