# frozen_string_literal: true

module UserPages
  extend ActiveSupport::Concern

  private

  def load_user_bookings(user)
    @dashboard = user == current_user ? participant_dashboard : ParticipantDashboard.new(user)
  end

  def load_user_history(user)
    @history = ParticipantHistory.new(user, page: params[:page])
    @bookings = @history.bookings
  end

  def load_user_programs(user)
    scope = Program.managed_by(user).and(Program.viewable_by(current_user).selector)
    @programs = Program.preload_primary_photos(scope.includes(:venue).order_by(name: :asc))
  end

  def load_user_applications(user)
    @page = [params[:page].to_i, 1].max
    @applications = ParticipantApplication.where(user_id: user.id).includes(:program)
                                          .order_by(created_at: :desc, id: :desc).skip((@page - 1) * 50).limit(51).to_a
    @more = @applications.length > 50
    @applications = @applications.first(50)
  end
end
