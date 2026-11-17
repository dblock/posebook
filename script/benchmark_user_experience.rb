# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'vips'
require_relative '../spec/support/database_helpers'

# Measures synthetic requests only in explicitly disposable benchmark databases.
module UserExperienceBenchmark
  # Tracks every fixture ID so cleanup cannot remove another run's records.
  class Fixtures
    include DatabaseHelpers

    VENUES = 20
    USERS = 50
    PHOTOS = 8
    INVITATIONS = 10

    attr_reader :users, :venues, :programs

    def initialize
      @minimum_password_cost = ActiveModel::SecurePassword.min_cost
    end

    def create
      ActiveModel::SecurePassword.min_cost = true
      @token = SecureRandom.hex(4)
      @users = create_users
      @venues = Array.new(VENUES) { |index| create_venue(name: "Benchmark Studio #{index} #{@token}") }
      @programs = create_programs
      create_memberships
      create_bookings
      create_photos
      create_invitations
      self
    end

    def cleanup
      Booking.collection.find(_id: { '$in' => @booking_ids }).delete_many if @booking_ids
      ProgramMembership.collection.find(_id: { '$in' => @membership_ids }).delete_many if @membership_ids
      # Raw fixture writes leave inverse associations cached on their parents.
      [Program, Venue].each { |type| tracked_records.grep(type).select(&:persisted?).each(&:reload) }
      cleanup_records
    ensure
      ActiveModel::SecurePassword.min_cost = @minimum_password_cost
    end

    private

    def create_users
      Array.new(USERS) do |index|
        create_user(name: "Benchmark Model #{index}", email: "benchmark-#{@token}-#{index}@example.test",
                    gender: index.even? ? 'female' : 'male', roles: index == USERS - 1 ? ['system_admin'] : [])
      end
    end

    def create_programs
      venues.flat_map do |venue|
        Array.new(3) do |index|
          create_program(venue: venue, name: "Benchmark Drawing #{index} #{venue.name}",
                         available_weekdays: %w[0 1 2 3 4 5 6], no_consecutive_genders: ['female'])
        end
      end
    end

    def create_memberships
      records = programs.flat_map do |program|
        users.map do |user|
          ProgramMembership.new(program: program, user: user, roles: ['participant'],
                                booking_invited_at: Time.current).as_document
        end
      end
      @membership_ids = records.pluck('_id')
      ProgramMembership.collection.insert_many(records)
    end

    def create_bookings
      records = programs.flat_map.with_index do |program, index|
        past_bookings(program) + upcoming_bookings(program, index)
      end
      @booking_ids = records.pluck('_id')
      Booking.collection.insert_many(records)
    end

    def past_bookings(program)
      users.flat_map.with_index do |user, user_index|
        Array.new(4) { |offset| booking(program, user, Date.current - 1 - (offset * USERS) - user_index) }
      end
    end

    def upcoming_bookings(program, index)
      users.drop(index.even? ? 1 : 0).first(4).map.with_index do |user, offset|
        booking(program, user, Date.current + 1 + offset)
      end
    end

    def booking(program, user, date)
      start = date.in_time_zone('UTC') + 9.hours
      Booking.new(program: program, user: user, date: date, time_zone: 'UTC',
                  starts_at: start, ends_at: start + 2.hours, scheduled_ends_at: start + 2.hours,
                  created_at: start - 1.day, updated_at: start - 1.day).as_document
    end

    def create_photos
      Tempfile.create(['benchmark', '.png']) do |file|
        upload = photo_upload(file)
        venues.each { |venue| location_photos(venue, VenuePhoto, upload) }
        programs.each { |program| location_photos(program, ProgramPhoto, upload) }
        2.times { ProfilePhoto.add(users.first.reload, upload) }
      end
    end

    def photo_upload(file)
      image = Vips::Image.black(300, 450).new_from_image([170, 100, 70])
      file.binmode.write(image.write_to_buffer('.png'))
      file.flush
      Struct.new(:tempfile).new(file)
    end

    def location_photos(owner, type, upload)
      photos = Array.new(PHOTOS) { track_record(type.add(owner, upload)) }
      owner.update!(primary_photo_id: photos.last.id)
    end

    def create_invitations
      [venues.first, programs.first].each do |target|
        INVITATIONS.times { create_coordinator_invitation(target, users.last, email: nil) }
      end
    end
  end

  # Counts database reads and elapsed time without recording arguments or private data.
  class Commands
    def initialize
      @collections = Hash.new(0)
      @pending = {}
      @duration = 0
    end

    def started(event)
      return unless %w[find aggregate distinct count getMore].include?(event.command_name)

      collection = event.command_name == 'getMore' ? event.command['collection'] : event.command[event.command_name]
      @collections[collection] += 1
      @pending[event.request_id] = true
    end

    def succeeded(event)
      @duration += event.duration if @pending.delete(event.request_id)
    end

    def failed(event)
      @pending.delete(event.request_id)
    end

    def result
      { commands: @collections.values.sum, database_ms: (@duration * 1000).round(2),
        collections: @collections.sort.to_h }
    end
  end

  # Warm server-side request times exclude setup, login, browser and network latency.
  class Runner # rubocop:disable Metrics/ClassLength -- Keep the page matrix with its fixture-aware runner.
    def initialize(fixtures, samples:)
      @fixtures = fixtures
      @samples = samples
      @program_path = "/programs/#{fixtures.programs.first.to_param}"
      @venue_path = "/venues/#{fixtures.venues.first.to_param}"
      @month = Date.current.advance(months: 2).strftime('%Y-%m')
      @mongo_version = Mongoid.default_client.database.command(buildInfo: 1).first['version']
    end

    def run
      { fixture: { venues: Fixtures::VENUES, programs: @fixtures.programs.size, users: Fixtures::USERS,
                   memberships: @fixtures.programs.size * Fixtures::USERS,
                   bookings: @fixtures.programs.size * ((Fixtures::USERS * 4) + 4),
                   photos_per_location: Fixtures::PHOTOS, coordinator_invitations_per_location: Fixtures::INVITATIONS },
        environment: { ruby: RUBY_VERSION, rails: Rails.version, mongodb: @mongo_version, samples: @samples,
                       latency: 'Warm in-process Rails requests; excludes browser, network and login.' },
        pages: pages.map { |name, client, path| measure(name, client, path) },
        query_plans: query_plans }
    end

    private

    def client(user = nil)
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.host! 'localhost'
      session.post('/session', params: { email: user.email, password: DatabaseHelpers::TEST_PASSWORD }) if user
      session
    end

    def pages
      admin = client(@fixtures.users.last)
      participant_pages + public_pages + admin_pages(admin) + program_management_pages(admin) +
        venue_management_pages(admin)
    end

    def participant_pages
      participant = client(@fixtures.users.first)
      photo = @fixtures.users.first.reload.primary_profile_photo
      thumbnail = "/participants/#{@fixtures.users.first.id}/photos/#{photo.id}?thumbnail=1"
      [['Venue Directory', participant, '/venues'], ['Participant Home', participant, '/'],
       ['Profile', participant, '/profile'], ['Profile Bookings', participant, '/profile/bookings'],
       ['Booking History', participant, '/profile/history'],
       ['Booking Calendar', participant, "#{@program_path}/calendar?month=#{@month}"],
       ['Profile Thumbnail', participant, thumbnail]] +
        %w[edit security programs applications photos].map do |section|
          ["Profile #{section.titleize}", participant, "/profile/#{section}"]
        end
    end

    def public_pages
      guest = client
      thumbnail = "#{@venue_path}/photos/#{@fixtures.venues.first.primary_photo.id}?thumbnail=1"
      [['Public Home', guest, '/'], ['Venue Overview', guest, @venue_path],
       ['Program Overview', guest, @program_path], ['Venue Programs', guest, "#{@venue_path}/programs"],
       ['Public Calendar', guest, "#{@program_path}/calendar?month=#{@month}"],
       ['Venue Photos', guest, "#{@venue_path}/photos"], ['Venue Thumbnail', guest, thumbnail]] +
        %w[about privacy terms].map { |section| [section.titleize, guest, "/#{section}"] }
    end

    def admin_pages(admin)
      user_path = "/admin/users/#{@fixtures.users.first.id}"
      [['Admin Home', admin, '/'], ['User Directory', admin, '/admin/users'],
       ['Audit History', admin, '/admin/history'], ['Admin User Profile', admin, user_path]] +
        %w[edit bookings programs applications history photos security].map do |section|
          ["Admin User #{section.titleize}", admin, "#{user_path}/#{section}"]
        end
    end

    def program_management_pages(admin)
      %w[calendar history photos edit security schedule schedule/exceptions participants
         coordinators coordinators/new participant_invitations participant_invitations/new
         applications applications/history google_calendar organizer_bookings/new].map do |section|
        ["Program #{section.tr('/', ' ').titleize}", admin, "#{@program_path}/#{section}"]
      end
    end

    def venue_management_pages(admin)
      %w[photos programs edit security coordinators coordinators/new programs/new].map do |section|
        ["Venue #{section.tr('/', ' ').titleize}", admin, "#{@venue_path}/#{section}"]
      end
    end

    def measure(name, client, path)
      client.get(path)
      results = Array.new(@samples) { request(client, path) }
      { name: name, path: path, median_ms: percentile(results.pluck(:ms), 0.5),
        p95_ms: percentile(results.pluck(:ms), 0.95),
        allocations: percentile(results.pluck(:allocations), 0.5), bytes: client.response.body.bytesize,
        database: results.min_by { |result| result[:ms] }.fetch(:database) }
    end

    def request(client, path)
      commands = Commands.new
      Mongoid.default_client.subscribe(Mongo::Monitoring::COMMAND, commands)
      timed_request(client, path).merge(database: commands.result)
    ensure
      Mongoid.default_client.unsubscribe(Mongo::Monitoring::COMMAND, commands) if commands
    end

    def timed_request(client, path)
      allocations = GC.stat(:total_allocated_objects)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.get(path)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      raise "Benchmark request returned #{client.response.status}." unless client.response.status == 200

      { ms: (elapsed * 1000).round(2), allocations: GC.stat(:total_allocated_objects) - allocations }
    end

    def percentile(values, fraction)
      values.sort[(values.size * fraction).ceil - 1]
    end

    def query_plans
      user_id = @fixtures.users.first.id
      upcoming = Booking.upcoming.where(user_id: user_id, :program_id.in => @fixtures.programs.map(&:id))
      { profile_upcoming: explain(upcoming),
        profile_history: explain(Booking.where(user_id: user_id).order_by(date: :desc, id: :desc)
                                       .limit(ParticipantHistory::PER_PAGE)) }
    end

    def explain(criteria)
      command = { find: Booking.collection.name, filter: criteria.selector }
      command.merge!(criteria.options.slice(:sort, :limit, :skip))
      result = Mongoid.default_client.database.command(explain: command, verbosity: 'executionStats').first
      result.fetch('executionStats').slice('nReturned', 'totalKeysExamined', 'totalDocsExamined')
    end
  end

  def self.run(samples:)
    validate!
    [User, Venue, Program, ProgramMembership, VenueMembership, Booking, BookingClaim,
     ProgramScheduleException, HistoryTracker, VenuePhoto, ProgramPhoto, CoordinatorInvitation].each(&:create_indexes)
    fixtures = Fixtures.new
    fixtures.create
    Runner.new(fixtures, samples: samples).run
  ensure
    fixtures&.cleanup
  end

  def self.validate!
    database = Mongoid.default_client.database.name
    unless Rails.env.test? && database.match?(/\Aposebook_test_benchmark(?:_|\z)/)
      raise 'Refusing benchmarks outside a disposable benchmark database.'
    end

    version = Mongoid.default_client.database.command(buildInfo: 1).first['version']
    raise 'Benchmarks require MongoDB 8.0.' unless version.start_with?('8.0.')
  end
end
