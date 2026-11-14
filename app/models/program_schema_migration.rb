# frozen_string_literal: true

class ProgramSchemaMigration
  COLLECTIONS = {
    'drawing_sessions' => 'programs',
    'drawing_session_memberships' => 'program_memberships',
    'drawing_session_schedule_exceptions' => 'program_schedule_exceptions',
    'model_bookings' => 'bookings',
    'model_booking_claims' => 'booking_claims',
    'model_invitations' => 'participant_invitations'
  }.freeze
  FIELDS = {
    'drawing_session_id' => 'program_id',
    'model_booking_id' => 'booking_id',
    'model_pay' => 'pay',
    'model_paused' => 'participant_paused',
    'model_pause_reason' => 'participant_pause_reason',
    'session_schema_version' => 'program_schema_version'
  }.freeze
  ROLES = { 'model' => 'participant', 'session_coordinator' => 'program_coordinator' }.freeze

  def self.call(client = Mongoid.default_client)
    new(client).call
  end

  def initialize(client)
    @client = client
  end

  def call
    rename_collections
    (COLLECTIONS.values + %w[venues venue_memberships venue_schedule_exceptions history_trackers]).each do |name|
      next unless @client.database.collection_names.include?(name)

      collection = @client[name]
      remove_legacy_indexes(collection)
      collection.find.each { |record| convert_record(collection, record) }
    end
  end

  private

  def rename_collections
    COLLECTIONS.each do |old, current|
      names = @client.database.collection_names
      next unless names.include?(old)

      raise "Cannot convert #{old}: #{current} already exists." if names.include?(current)

      database = @client.database.name
      @client.use('admin').database.command(renameCollection: "#{database}.#{old}", to: "#{database}.#{current}")
    end
  end

  def remove_legacy_indexes(collection)
    collection.indexes.each do |index|
      collection.indexes.drop_one(index['name']) if index['key'].keys.intersect?(FIELDS.keys)
    end
  end

  def convert_record(collection, record)
    converted = converted_record(collection.name, record)
    return if converted == record

    collection.find(_id: record['_id']).update_one(
      '$set' => converted.except('_id'), '$unset' => (record.keys - converted.keys).index_with(true)
    )
  end

  def converted_record(name, record)
    converted = renamed_fields(record)
    converted = { 'program_label' => 'Session', 'participant_label' => 'Model' }.merge(converted) if name == 'programs'
    converted.merge!(renamed_history(record)) if name == 'history_trackers'
    converted
  end

  def renamed_history(record)
    { 'scope' => renamed_scope(record['scope']),
      'association_chain' => record.fetch('association_chain', []).map do |part|
        part.merge('name' => renamed_scope(part['name']))
      end }
  end

  def renamed_fields(value)
    case value
    when Hash
      renamed_hash(value)
    when Array
      value.map { |entry| renamed_fields(entry) }
    else
      value
    end
  end

  def renamed_hash(value)
    value.each_with_object({}) do |(key, entry), result|
      renamed = renamed_key(key, value)
      result[renamed] = if key == 'roles' && entry.is_a?(Array)
                          entry.map { |role| ROLES.fetch(role, role) }
                        else
                          renamed_fields(entry)
                        end
    end
  end

  def renamed_key(key, value)
    renamed = FIELDS.fetch(key, key)
    if renamed != key && value.key?(renamed) && value[renamed] != value[key]
      raise "Conflicting legacy field #{key} and #{renamed}."
    end

    renamed
  end

  def renamed_scope(value)
    value.to_s.sub(/\ADrawingSession/, 'Program').sub(/\Adrawing_session/, 'program')
         .sub(/\AModelBooking/, 'Booking').sub(/\Amodel_booking/, 'booking')
         .sub(/\AModelInvitation/, 'ParticipantInvitation').sub(/\Amodel_invitation/, 'participant_invitation')
  end
end
