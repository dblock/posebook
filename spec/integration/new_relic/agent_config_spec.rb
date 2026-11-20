# frozen_string_literal: true

require 'rails_helper'
require 'erb'
require 'yaml'

RSpec.describe NewRelic::Agent, '.config', :aggregate_failures do
  def settings(license)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('NEW_RELIC_LICENSE_KEY', '').and_return(license)
    YAML.safe_load(ERB.new(Rails.root.join('config/newrelic.yml').read).result, aliases: true)
  end

  it 'keeps production monitoring optional when the license is absent or blank' do
    ['', '  '].each do |license|
      expect(settings(license).dig('production', 'agent_enabled')).to be(false)
    end
  end

  it 'enables production with a license without enabling development or tests or embedding the key' do
    configured = settings('not-a-real-license')
    expect(configured.dig('production', 'agent_enabled')).to be(true)
    expect(configured.dig('development', 'agent_enabled')).to be(false)
    expect(configured.dig('test', 'agent_enabled')).to be(false)
    expect(configured.to_s).not_to include('not-a-real-license')
    expect(described_class.config[:agent_enabled]).to be(false)
  end

  it 'reports exception messages, request attributes, and logs in production without request parameters' do
    production = settings('not-a-real-license').fetch('production')
    expect(production.dig('strip_exception_messages', 'enabled')).to be(false)
    expect(production.dig('application_logging', 'enabled')).to be(true)
    expect(production).not_to have_key('attributes')
    expect(production['capture_params']).to be(false)
    expect(production.dig('mongo', 'capture_queries')).to be(false)
    expect(production.dig('browser_monitoring', 'auto_instrument')).to be(false)
  end
end
