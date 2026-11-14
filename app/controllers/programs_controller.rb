# frozen_string_literal: true

class ProgramsController < ApplicationController
  before_action :remember_booking_destination, only: :show
  before_action :require_authentication, except: :show
  before_action :find_venue, only: %i[new create]
  before_action :find_program, only: %i[show edit update]
  rescue_from Mongo::Error::OperationFailure, with: :handle_slug_conflict

  def index
    @programs = Program.visible_to(current_user).order_by(name: :asc)
  end

  def show
    @calendar = ProgramCalendar.new(@program, month: params[:month])
    @program_coordinator = current_user && @program.managed_by?(current_user)
    @program_member = @program_coordinator || (current_user && @program.participant?(current_user))
    load_calendar if @program_member
    if calendar_navigation?
      return render partial: 'programs/calendar',
                    locals: { calendar: @calendar, public_view: !@program_member }
    end

    @invitations = @program.participant_invitations.order_by(created_at: :desc) if @program_coordinator
  end

  def new
    @program = @venue.programs.new
  end

  def edit; end

  def create
    @program = @venue.programs.new(program_params)
    if @program.save
      redirect_to @program, notice: @program.message('programs.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @program = ProgramSettingsUpdate.new(program: @program,
                                         user: current_user).call(program_params)
    if @program.errors.empty?
      redirect_to @program, notice: @program.message('programs.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def find_venue
    @venue = Venue.coordinated_by(current_user).find(params.expect(:venue_id))
  end

  def calendar_navigation?
    response.headers['Vary'] = [response.headers['Vary'], 'X-Posebook-Calendar-Context'].compact.join(', ')
    supplied = request.headers['X-Posebook-Calendar-Context']
    supplied.present? && supplied == helpers.calendar_access_context(
      !@program_member, manager: @program_coordinator, program: @program, booking: @my_booking
    )
  end

  def remember_booking_destination
    return if current_user || params[:booking_invitation] != '1'

    session[:booking_program] = params[:id]
    require_authentication
  end

  def handle_slug_conflict(error)
    raise error unless error.code == 11_000

    @program.errors.add(:custom_slug, :taken)
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end

  def load_calendar
    @booking_access = BookingAccess.new(@program.memberships.participants.where(user_id: current_user.id).first)
    @can_book = @booking_access.allowed?
    @my_booking = @calendar.current_booking(current_user)
    @booking_history = @calendar.history_for(current_user)
  end

  def find_program
    scope = action_name == 'show' ? Program.all : Program.managed_by(current_user)
    @program = scope.find(params.expect(:id))
  end

  def program_params
    params.expect(program: [:name, :program_label, :participant_label, :custom_slug, :time_zone, :start_time, :end_time,
                            :pay,
                            :instructions, :booking_horizon_months,
                            { available_weekdays: [], no_consecutive_genders: [] }])
  end
end
