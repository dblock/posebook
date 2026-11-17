# frozen_string_literal: true

class AuditHistory
  MODELS = [User, Venue, Program, ProgramMembership, ProgramScheduleException,
            NotificationDefaults].index_by(&:name).freeze
  ASSOCIATIONS = { ProgramMembership => %i[user program], ProgramScheduleException => [:program] }.freeze

  attr_reader :pagination

  def initialize(cursor: nil)
    @pagination = CursorPage.new(HistoryTracker.order_by(created_at: :desc), cursor: cursor)
  end

  def entries
    pagination.records
  end

  def model_for(entry)
    return unless entry.association_chain.one?

    MODELS[entry.association_chain.first['name']]
  end

  def subject_for(entry)
    subjects.fetch(model_for(entry), {})[entry.association_chain.first&.fetch('id', nil)]
  end

  def actor_for(entry)
    @actors ||= load_records(User, entries.filter_map(&:modifier_id))
    @actors[entry.modifier_id]
  end

  def changes_for(entry)
    model_for(entry) ? entry.tracked_changes.sort.to_h : {}
  end

  private

  def subjects
    @subjects ||= MODELS.values.index_with do |model|
      ids = entries.select { |entry| model_for(entry) == model }.map { |entry| entry.association_chain.first['id'] }
      load_records(model, ids)
    end
  end

  def load_records(model, ids)
    return {} if ids.empty?

    model.where(:id.in => ids.uniq).includes(*ASSOCIATIONS.fetch(model, [])).index_by(&:id)
  end
end
