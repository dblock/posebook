# frozen_string_literal: true

class DrawingSessionSchedulesController < ApplicationController
  before_action :require_authentication
  before_action :find_drawing_session
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_conflict

  def show
    @exception = @drawing_session.schedule_exceptions.where(date: params[:date]).first ||
                 @drawing_session.schedule_exceptions.new(date: params[:date], start_time: @drawing_session.start_time)
    load_schedule
  end

  def update
    @exception = DrawingSessionScheduleMutation.new(drawing_session: @drawing_session,
                                                    user: current_user).call(schedule_params)
    if @exception.errors.empty?
      redirect_to drawing_session_path(@drawing_session, month: @exception.date.strftime('%Y-%m')),
                  notice: t('drawing_sessions.schedule_saved')
    else
      load_schedule
      render :show, status: :unprocessable_content
    end
  end

  private

  def find_drawing_session
    @drawing_session = DrawingSession.managed_by(current_user).find(params.expect(:drawing_session_id))
  end

  def schedule_params
    params.expect(schedule: %i[date mode start_time reason]).to_h.symbolize_keys
  end

  def load_schedule
    @calendar = DrawingSessionCalendar.new(@drawing_session)
    @exceptions = @drawing_session.schedule_exceptions.where(:date.gte => @calendar.today).order_by(date: :asc)
  end

  def show_conflict(error)
    @exception = @drawing_session.schedule_exceptions.new(schedule_params)
    @exception.errors.add(:base, error.message)
    load_schedule
    render :show, status: :unprocessable_content
  end
end
