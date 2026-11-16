# frozen_string_literal: true

class VenuePhotosController < ApplicationController
  include PhotoResponse

  before_action :require_authentication, except: :show
  before_action :find_venue
  before_action :find_photo, except: :create

  rescue_from ProfileImage::Invalid, with: :invalid_upload
  rescue_from Mongo::Error, with: :storage_unavailable

  def show
    send_photo(@photo)
  end

  def create
    VenuePhoto.add(@venue, params.expect(venue_photo: [:file]).fetch(:file))
    redirect_to photos_venue_path(@venue), notice: t('photos.venue_uploaded'), status: :see_other
  end

  def update
    attributes = params.expect(venue_photo: %i[public primary])
    if attributes[:primary] == '1'
      @photo.select_primary
      redirect_to photos_venue_path(@venue), notice: t('photos.venue_primary_updated'), status: :see_other
    else
      raise ActionController::BadRequest unless %w[0 1].include?(attributes[:public])

      @photo.change_visibility(attributes[:public] == '1')
      redirect_to photos_venue_path(@venue), notice: t('photos.updated'), status: :see_other
    end
  end

  def destroy
    @photo.destroy!
    redirect_to photos_venue_path(@venue), notice: t('photos.deleted'), status: :see_other
  end

  private

  def find_venue
    @venue = Venue.find(params.expect(:venue_id))
    return head :not_found if action_name == 'show' && !@venue.viewable_by?(current_user)

    head :forbidden unless action_name == 'show' || @venue.coordinated_by?(current_user)
  end

  def find_photo
    scope = @venue.coordinated_by?(current_user) ? @venue.photos : @venue.photos.visible
    @photo = scope.find(params.expect(:id))
  end

  def invalid_upload(error)
    redirect_to photos_venue_path(@venue), alert: error.message, status: :see_other
  end

  def storage_unavailable(error)
    NewRelic::Agent.notice_error(error)
    render plain: t('photos.unavailable'), status: :service_unavailable
  end
end
