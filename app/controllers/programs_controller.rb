# frozen_string_literal: true

class ProgramsController < ApplicationController
  before_action :remember_booking_destination, only: :show
  before_action :require_authentication, except: %i[show photos]
  before_action :find_venue, only: %i[new create]
  before_action :find_program, only: %i[show photos edit update]
  before_action :prepare_program_access, only: :show
  before_action :prepare_program_page, only: :show
  rescue_from Mongo::Error::OperationFailure, with: :handle_slug_conflict
  rescue_from LocationActivation::Forbidden, with: -> { head :forbidden }
  rescue_from LocationActivation::Invalid, with: -> { head :bad_request }

  def index
    records = Program.visible_to(current_user).and(Program.viewable_by(current_user).selector)
    @programs = Program.preload_primary_photos(records.includes(:venue).order_by(name: :asc))
  end

  def show
    if @section == 'calendar' && calendar_navigation?
      return render partial: 'programs/calendar',
                    locals: { calendar: @calendar, public_view: !@program_member }
    end

    @booking_history = @calendar.history_for(current_user) if @section == 'history'
  end

  def new
    @program = @venue.programs.new
  end

  def photos; end

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
    return update_activation if params.key?(:active)

    @program = ProgramSettingsUpdate.new(program: @program,
                                         user: current_user).call(program_params)
    if @program.errors.empty?
      redirect_to @program, notice: @program.message('programs.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def update_activation
    @program = LocationActivation.new(location: @program, user: current_user).call(params[:active])
    redirect_to edit_program_path(@program), notice: t('locations.access_updated')
  end

  def prepare_program_access
    @program_coordinator = current_user && @program.managed_by?(current_user)
    @program_member = @program_coordinator || (current_user && @program.participant?(current_user))
    @section = params[:section].presence || default_section
  end

  def prepare_program_page
    return head :not_found unless %w[view calendar history].include?(@section)
    return head :not_found if @section == 'history' && !@program_member

    @calendar = ProgramCalendar.new(@program, month: params[:month])
    load_calendar if @program_member
  end

  def default_section
    params[:month].present? || request.headers['X-Posebook-Calendar-Context'].present? ? 'calendar' : 'view'
  end

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
  end

  def find_program
    public_action = %w[show photos].include?(action_name)
    scope = public_action ? Program.all : Program.managed_by(current_user)
    @program = scope.find(params.expect(:id))
    head :not_found if public_action && !@program.viewable_by?(current_user)
  end

  def program_params
    params.expect(program: [:name, :program_label, :participant_label, :custom_slug, :time_zone, :start_time, :end_time,
                            :pay, :calendar_invitation_lead_minutes,
                            :instructions, :booking_horizon_months,
                            { available_weekdays: [], no_consecutive_genders: [] }])
  end
end
