# frozen_string_literal: true

class VenueProgramMigration
  SESSION_FIELDS = %w[name custom_slug _slugs time_zone pay instructions booking_horizon_months available_weekdays
                      no_consecutive_genders start_time schedule_revision created_at updated_at version].freeze
  BOOKING_MODELS = [Booking, BookingClaim, ParticipantInvitation].freeze
  LOCATION_FIELDS = %w[name custom_slug _slugs created_at updated_at version].freeze

  def self.call
    new.call
  end

  def call
    Venue.collection.find('program_schema_version' => { '$exists' => false }).each { |record| migrate(record['_id']) }
    BookingClaim.create_indexes
    BOOKING_MODELS.each { |participant| finish_relationships(participant.collection) }
  end

  private

  def migrate(id)
    Venue.with_session do |session|
      session.with_transaction do
        record = Venue.collection.find({ _id: id, 'program_schema_version' => { '$exists' => false } },
                                       session: session).first
        migrate_record(record, session) if record
      end
    end
  end

  def migrate_record(record, session)
    id = record['_id']
    insert_session(record, session)
    BOOKING_MODELS.each do |participant|
      participant.collection.update_many({ venue_id: id }, { '$set' => { program_id: id } }, session: session)
    end
    move_records(:venue_memberships, ProgramMembership, id, session)
    move_records(:venue_schedule_exceptions, ProgramScheduleException, id, session)
    copy_session_history(id, session)
    mark_venue(id, session)
  end

  def insert_session(record, session)
    attributes = record.slice(*SESSION_FIELDS).merge('_id' => record['_id'], 'venue_id' => record['_id'])
    Program.collection.insert_one(Program.new(attributes).as_document, session: session)
  end

  def mark_venue(id, session)
    removed = (SESSION_FIELDS - LOCATION_FIELDS).index_with { true }
    Venue.collection.find(_id: id).update_one(
      { '$set' => { program_schema_version: 1 }, '$unset' => removed }, session: session
    )
  end

  def move_records(collection_name, participant, id, session)
    collection = Mongoid.default_client[collection_name]
    selector = { venue_id: id }
    selector[:roles] = { '$nin' => ['venue_coordinator'] } if participant == ProgramMembership
    collection.find(selector, session: session).each { |record| move_record(participant, record, session) }
    collection.delete_many(selector, session: session)
  end

  def move_record(participant, record, session)
    record['program_id'] = record.delete('venue_id')
    if record['roles']
      record['roles'] = record['roles'].map do |role|
        role == 'manage_schedule' ? 'program_coordinator' : role
      end
    end
    participant.collection.insert_one(record, session: session)
    move_record_history(record['_id'], session)
  end

  def move_record_history(id, session)
    HistoryTracker.collection.find({ 'association_chain.id' => id }, session: session).to_a.each do |record|
      changes = { 'scope' => renamed_scope(record['scope']),
                  'association_chain' => renamed_chain(record['association_chain']) }
      HistoryTracker.collection.find(_id: record['_id']).update_one({ '$set' => changes }, session: session)
    end
  end

  def copy_session_history(id, session)
    HistoryTracker.collection.find({ 'association_chain.id' => id }, session: session).to_a.each do |record|
      next if renamed_scope(record['scope']) == record['scope'].to_s

      copy = session_history_copy(record)
      HistoryTracker.collection.insert_one(copy, session: session) if copy
    end
  end

  def session_history_copy(record)
    copy = record.merge('_id' => BSON::ObjectId.new, 'scope' => renamed_scope(record['scope']),
                        'association_chain' => renamed_chain(record['association_chain']))
    %w[original modified].each { |key| copy[key] = (copy[key] || {}).slice(*SESSION_FIELDS) }
    copy unless copy['original'].empty? && copy['modified'].empty?
  end

  def renamed_scope(value)
    value.to_s.sub(/\AVenue/, 'Program').sub(/\Avenue/, 'program')
  end

  def renamed_chain(chain)
    chain.map { |part| part.merge('name' => renamed_scope(part['name'])) }
  end

  def finish_relationships(collection)
    # Install the replacement unique claim indexes before removing legacy venue indexes.
    collection.indexes.to_a.each do |index|
      drop_index(collection, index['name']) if index['key'].key?('venue_id')
    end
    collection.update_many({ 'program_id' => { '$exists' => true } }, { '$unset' => { venue_id: true } })
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 26
  end

  def drop_index(collection, name)
    collection.indexes.drop_one(name)
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 27
  end
end
