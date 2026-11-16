# frozen_string_literal: true

module UserPages
  extend ActiveSupport::Concern

  private

  def load_user_bookings(user)
    @dashboard = user == current_user ? participant_dashboard : ParticipantDashboard.new(user)
  end

  def load_user_history(user)
    @history = ParticipantHistory.new(user, cursor: params[:cursor])
    @bookings = @history.bookings
  end

  def load_user_programs(user)
    scope = Program.managed_by(user).and(Program.viewable_by(current_user).selector)
    @programs = Program.preload_primary_photos(scope.includes(:venue).order_by(name: :asc), series: true)
  end

  def load_user_applications(user)
    records = ParticipantApplication.where(user_id: user.id).includes(:program).order_by(created_at: :desc)
    @pagination = CursorPage.new(records, cursor: params[:cursor])
    @applications = @pagination.records
  end
end
