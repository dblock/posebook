# frozen_string_literal: true

module Admin
  module HistoryHelper
    def audit_actor(entry, history)
      return 'System / Anonymous' unless entry.modifier_id

      actor = history.actor_for(entry)
      actor ? audit_record_link(actor) : "Deleted account (#{entry.modifier_id})"
    end

    def audit_subject(entry, history)
      subject = history.subject_for(entry)
      model = history.model_for(entry)
      label = model&.model_name&.human || 'Record'
      target = subject ? audit_subject_link(subject) : audit_deleted_subject(entry, model)
      safe_join([tag.strong(label), tag.br, target])
    end

    def audit_action(entry)
      { 'create' => 'Created', 'update' => 'Updated', 'destroy' => 'Deleted' }.fetch(entry.action, 'Changed')
    end

    def audit_value(value)
      case value
      when nil then 'Not set'
      when true then 'Yes'
      when false then 'No'
      when Time, Date then render('shared/date', value: value, zone: 'UTC', format: :compact)
      when Array, Hash then value.to_json
      else value.as_json.to_s.presence || 'Empty'
      end
    end

    private

    def audit_deleted_subject(entry, model)
      name = entry.modified['name'].presence || entry.original['name'].presence if model&.tracked?('name')
      name ||= entry.association_chain.first&.fetch('id', nil)
      "#{name || 'Unknown record'} (Unavailable)"
    end

    def audit_record_link(record)
      return 'Unavailable' unless record

      path = case record
             when User then admin_user_path(record)
             when Venue then venue_path(record)
             when Program then program_path(record)
             end
      link_to record.name, path
    end

    def audit_subject_link(subject)
      case subject
      when ProgramMembership then audit_membership_link(subject)
      when ProgramScheduleException then audit_schedule_exception_link(subject)
      else audit_record_link(subject)
      end
    end

    def audit_schedule_exception_link(subject)
      return 'Unavailable' unless subject.program

      date = render('shared/date', value: subject.date, zone: subject.program.time_zone, format: :compact)
      link_to safe_join([subject.program.name, ': ', date]),
              program_schedule_path(subject.program, date: subject.date.iso8601)
    end

    def audit_membership_link(membership)
      identity = [audit_record_link(membership.user), ' at ', audit_record_link(membership.program)]
      if membership.program && membership.roles.include?('participant')
        identity += [' ', link_to('Settings', edit_program_participant_path(membership.program, membership))]
      end
      safe_join(identity)
    end
  end
end
