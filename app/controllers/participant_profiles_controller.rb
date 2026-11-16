# frozen_string_literal: true

class ParticipantProfilesController < ApplicationController
  before_action :require_authentication, only: :photos
  before_action :no_store
  before_action :redirect_own_profile, only: :show

  def show
    @user = User.find(params.expect(:id))
    return redirect_to admin_user_path(@user) if current_user&.system_admin?
    return head :not_found unless profile_visible?

    @photos = @user.public_photos
    @next_booking = next_public_booking
  end

  def photos
    @user = current_user
    @gallery = PhotoGallery.new(@user, current_user)
    @photos = @gallery.photos
  end

  private

  def redirect_own_profile
    redirect_to photos_profile_path if current_user && params[:id] == current_user.id.to_s
  end

  def profile_visible?
    @user.active? || PhotoGallery.new(@user, current_user).private_access?
  end

  def next_public_booking
    return unless @user.active?

    hidden = ProgramMembership.where(user_id: @user.id, photos_hidden: true).distinct(:program_id)
    programs = Program.viewable_by(current_user).where(:id.nin => hidden).distinct(:id)
    Booking.upcoming.where(user_id: @user.id, :program_id.in => programs).order_by(starts_at: :asc).first
  end

  def no_store
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
