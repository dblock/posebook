# frozen_string_literal: true

class VenuePhotosController < ApplicationController
  before_action :require_authentication, except: :show
  before_action :find_venue
  before_action :find_photo, except: :create

  rescue_from ProfileImage::Invalid, with: :invalid_upload
  rescue_from Mongo::Error, with: :storage_unavailable

  def show
    response.headers['Cache-Control'] = 'no-store'
    send_data @photo.bytes(thumbnail: params[:thumbnail] == '1'),
              type: 'image/webp', disposition: 'inline', filename: 'photo.webp'
  end

  def create
    VenuePhoto.add(@venue, params.expect(venue_photo: [:file]).fetch(:file))
    redirect_to photos_venue_path(@venue), notice: t('photos.venue_uploaded'), status: :see_other
  end

  def destroy
    @photo.destroy!
    redirect_to photos_venue_path(@venue), notice: t('photos.deleted'), status: :see_other
  end

  private

  def find_venue
    @venue = Venue.find(params.expect(:venue_id))
    head :forbidden unless action_name == 'show' || @venue.coordinated_by?(current_user)
  end

  def find_photo
    @photo = @venue.photos.find(params.expect(:id))
  end

  def invalid_upload(error)
    redirect_to photos_venue_path(@venue), alert: error.message, status: :see_other
  end

  def storage_unavailable(error)
    NewRelic::Agent.notice_error(error)
    render plain: t('photos.unavailable'), status: :service_unavailable
  end
end
