# frozen_string_literal: true

class PagesController < ApplicationController
  helper_method :participant_dashboard
  before_action :require_authentication, except: %i[home about privacy terms]

  def home
    return redirect_to new_registration_path unless User.exists?

    prepare_management_home if current_user
    @sessions = UpcomingSessions.new.to_a unless current_user
  end

  def about; end
  def privacy; end
  def terms; end

  private

  def prepare_management_home
    programs = Program.managed_by(current_user).includes(:venue).order_by(name: :asc)
    @managed_programs = Program.preload_primary_photos(programs, series: true)
    @management_home = current_user.system_admin? || @managed_programs.any? ||
                       Venue.coordinated_by(current_user).exists?
    prepare_submitted_applications if @management_home
  end

  def prepare_submitted_applications
    @submitted_status = params[:status].presence || 'pending'
    return head :bad_request unless %w[pending declined accepted withdrawn all].include?(@submitted_status)

    @submitted_pagination = CursorPage.new(submitted_applications_scope, cursor: params[:cursor])
    @submitted_applications = @submitted_pagination.records
  end

  def submitted_applications_scope
    records = ParticipantApplication.where(:program_id.in => @managed_programs.map(&:id), :status.ne => 'draft')
    records = records.where(status: @submitted_status) unless @submitted_status == 'all'
    records.includes(program: :venue).order_by(created_at: :desc)
  end
end
