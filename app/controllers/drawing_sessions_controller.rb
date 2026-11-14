# frozen_string_literal: true

class DrawingSessionsController < ApplicationController
  before_action :remember_booking_destination, only: :show
  before_action :require_authentication, except: :show
  before_action :find_venue, only: %i[new create]
  before_action :find_drawing_session, only: %i[show edit update]
  rescue_from Mongo::Error::OperationFailure, with: :handle_slug_conflict

  def index
    @drawing_sessions = DrawingSession.visible_to(current_user).order_by(name: :asc)
  end

  def show
    @calendar = DrawingSessionCalendar.new(@drawing_session, month: params[:month])
    @session_coordinator = current_user && @drawing_session.managed_by?(current_user)
    @drawing_session_member = @session_coordinator || (current_user && @drawing_session.model?(current_user))
    load_calendar if @drawing_session_member
    if calendar_navigation?
      return render partial: 'drawing_sessions/calendar',
                    locals: { calendar: @calendar, public_view: !@drawing_session_member }
    end

    @invitations = @drawing_session.model_invitations.order_by(created_at: :desc) if @session_coordinator
  end

  def new
    @drawing_session = @venue.drawing_sessions.new
  end

  def edit; end

  def create
    @drawing_session = @venue.drawing_sessions.new(drawing_session_params)
    if @drawing_session.save
      redirect_to @drawing_session, notice: t('drawing_sessions.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @drawing_session = DrawingSessionSettingsUpdate.new(drawing_session: @drawing_session,
                                                        user: current_user).call(drawing_session_params)
    if @drawing_session.errors.empty?
      redirect_to @drawing_session, notice: t('drawing_sessions.updated')
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
      !@drawing_session_member, manager: @session_coordinator, drawing_session: @drawing_session, booking: @my_booking
    )
  end

  def remember_booking_destination
    return if current_user || params[:booking_invitation] != '1'

    session[:booking_drawing_session] = params[:id]
    require_authentication
  end

  def handle_slug_conflict(error)
    raise error unless error.code == 11_000

    @drawing_session.errors.add(:custom_slug, :taken)
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end

  def load_calendar
    @booking_access = ModelBookingAccess.new(@drawing_session.memberships.models.where(user_id: current_user.id).first)
    @can_book = @booking_access.allowed?
    @my_booking = @calendar.current_booking(current_user)
    @booking_history = @calendar.history_for(current_user)
  end

  def find_drawing_session
    scope = action_name == 'show' ? DrawingSession.all : DrawingSession.managed_by(current_user)
    @drawing_session = scope.find(params.expect(:id))
  end

  def drawing_session_params
    params.expect(drawing_session: [:name, :custom_slug, :time_zone, :start_time, :model_pay,
                                    :instructions, :booking_horizon_months,
                                    { available_weekdays: [], no_consecutive_genders: [] }])
  end
end
