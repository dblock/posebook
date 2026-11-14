# frozen_string_literal: true

class ProgramSchedulesController < ApplicationController
  before_action :require_authentication
  before_action :find_program
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_conflict

  def show
    @exception = @program.schedule_exceptions.where(date: params[:date]).first ||
                 @program.schedule_exceptions.new(date: params[:date], start_time: @program.start_time)
    load_schedule
  end

  def update
    @exception = ProgramScheduleMutation.new(program: @program,
                                             user: current_user).call(schedule_params)
    if @exception.errors.empty?
      redirect_to program_path(@program, month: @exception.date.strftime('%Y-%m')),
                  notice: @program.message('programs.schedule_saved')
    else
      load_schedule
      render :show, status: :unprocessable_content
    end
  end

  private

  def find_program
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
  end

  def schedule_params
    params.expect(schedule: %i[date mode start_time reason]).to_h.symbolize_keys
  end

  def load_schedule
    @calendar = ProgramCalendar.new(@program)
    @exceptions = @program.schedule_exceptions.where(:date.gte => @calendar.today).order_by(date: :asc)
  end

  def show_conflict(error)
    @exception = @program.schedule_exceptions.new(schedule_params)
    @exception.errors.add(:base, error.message)
    load_schedule
    render :show, status: :unprocessable_content
  end
end
