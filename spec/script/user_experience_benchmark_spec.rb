# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require_relative '../../script/benchmark_user_experience'

RSpec.describe UserExperienceBenchmark, :aggregate_failures, :database do
  def with_benchmark_fixture
    stub_const('UserExperienceBenchmark::Fixtures::VENUES', 1)
    stub_const('UserExperienceBenchmark::Fixtures::USERS', 6)
    stub_const('UserExperienceBenchmark::Fixtures::PHOTOS', 2)
    fixtures = UserExperienceBenchmark::Fixtures.new
    yield fixtures
  ensure
    fixtures&.cleanup
  end

  it 'rejects non-test environments before booting the application or touching a database' do
    _, errors, status = Open3.capture3({ 'RAILS_ENV' => 'production' }, 'ruby', 'bin/benchmark')
    expect(status).not_to be_success
    expect(errors).to include('Benchmarks require RAILS_ENV=test')
  end

  it 'requires an explicitly disposable benchmark database instead of ordinary application or test data' do
    [nil, 'mongodb://127.0.0.1/posebook_test', 'mongodb://127.0.0.1/posebook_development'].each do |uri|
      _, errors, status = Open3.capture3({ 'RAILS_ENV' => 'test', 'MONGODB_TEST_URI' => uri }, 'ruby', 'bin/benchmark')
      expect(status).not_to be_success
      expect(errors).to match(/Set MONGODB_TEST_URI|require a posebook_test_benchmark/)
    end
  end

  it 'rejects ordinary test databases when invoked directly without the command-line guard' do
    user = create_user
    expect { described_class.run(samples: 1) }.to raise_error(/Refusing benchmarks/)
    expect(User.where(id: user.id)).to exist
  end

  it 'measures real pages and cleans up only its fixtures while retaining existing booking history' do
    existing = track_record(Booking.create!(program: create_program, user: create_user, date: Date.yesterday,
                                            ends_at: 1.day.ago, time_zone: 'UTC'))
    report, fixtures = with_benchmark_fixture do |fixtures|
      fixtures.create
      [UserExperienceBenchmark::Runner.new(fixtures, samples: 1).run, fixtures]
    end
    expect(report[:pages].pluck(:name)).to include('Profile Bookings', 'Booking Calendar', 'Venue Thumbnail')
    expect(Booking.where(:program_id.in => fixtures.programs.map(&:id))).to be_empty
    expect(Program.where(:id.in => fixtures.programs.map(&:id))).to be_empty
    expect(Venue.where(:id.in => fixtures.venues.map(&:id))).to be_empty
    expect(Booking.where(id: existing.id)).to exist
  end

  it 'cleans up partial fixture creation after failure without deleting unrelated accounts' do
    existing = create_user
    failed = nil
    expect do
      with_benchmark_fixture do |fixtures|
        failed = fixtures
        allow(fixtures).to receive(:create_photos).and_raise('Synthetic fixture failure')
        fixtures.create
      end
    end.to raise_error('Synthetic fixture failure')
    expect(Booking.where(:program_id.in => failed.programs.map(&:id))).to be_empty
    expect(Program.where(:id.in => failed.programs.map(&:id))).to be_empty
    expect(Venue.where(:id.in => failed.venues.map(&:id))).to be_empty
    expect(User.where(id: existing.id)).to exist
  end
end
