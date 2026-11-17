# frozen_string_literal: true

module NotificationTemplates
  extend ActiveSupport::Concern

  included do
    validates :subject, length: { maximum: 200 }
    validates :body, length: { maximum: 10_000 }
    validate :validate_templates
    validate :validate_action_links
    validate { errors.add(:subject, 'must be a single line') if subject.to_s.match?(/[\r\n]/) }
  end

  def title = I18n.t("booking_notifications.#{kind}.title")

  def description = I18n.t("booking_notifications.#{kind}.description")

  def placeholders
    NotificationCatalog.placeholders(kind)
  end

  def template(field)
    public_send(field).presence || inherited_template(field)
  end

  def inherited_template(field)
    parent_attributes[field].presence || I18n.t("booking_notifications.#{kind}.#{field}")
  end

  def render(values)
    %w[subject body].index_with do |field|
      text = template(field).gsub(/\{([^{}]+)\}/) { values.fetch(Regexp.last_match(1)) }
      field == 'subject' ? text.squish : text
    end
  end

  private

  def validate_templates
    %w[subject body].each do |field|
      unknown = public_send(field).to_s.scan(/\{([^{}]*)\}/).flatten - placeholders
      errors.add(field, "contains unknown placeholders: #{unknown.uniq.join(', ')}") if unknown.any?
    end
  end

  def validate_action_links
    NotificationCatalog::REQUIRED_LINKS.fetch(kind, []).each do |link|
      errors.add(:body, "must include {#{link}}") unless template('body').include?("{#{link}}")
      errors.add(:subject, 'cannot include action links') if template('subject').include?("{#{link}}")
    end
  end
end
