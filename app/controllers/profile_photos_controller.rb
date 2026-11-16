# frozen_string_literal: true

class ProfilePhotosController < ApplicationController
  include PhotoResponse

  before_action :require_authentication, except: :show
  before_action :find_gallery
  before_action :require_editor, except: :show
  before_action :find_photo, except: :create

  rescue_from ProfileImage::Invalid, with: :invalid_upload
  rescue_from Mongo::Error, with: :storage_unavailable

  def show
    send_photo(@photo)
  end

  def create
    ProfilePhoto.add(@user, params.expect(profile_photo: [:file]).fetch(:file))
    redirect_to gallery_path, notice: t('photos.uploaded'), status: :see_other
  end

  def update
    attributes = params.expect(profile_photo: %i[public primary])
    return update_primary(attributes[:primary]) if attributes.key?(:primary)

    value = attributes.fetch(:public)
    raise ActionController::BadRequest unless %w[0 1].include?(value)

    @photo.change_visibility(@user, value == '1')
    redirect_to gallery_path, notice: t('photos.updated'), status: :see_other
  end

  def destroy
    @photo.remove(@user)
    redirect_to gallery_path, notice: t('photos.deleted'), status: :see_other
  end

  private

  def update_primary(value)
    raise ActionController::BadRequest unless value == '1'
    return head :not_found unless @photo.select_primary(@user).matched_count == 1

    redirect_to gallery_path, notice: t('photos.primary_updated'), status: :see_other
  end

  def find_gallery
    response.headers['Cache-Control'] = 'private, no-store'
    @user = User.find(params.expect(:participant_id))
    @gallery = PhotoGallery.new(@user, current_user)
  end

  def require_editor
    head :forbidden unless @gallery.editable?
  end

  def gallery_path
    @user == current_user ? photos_profile_path : photos_admin_user_path(@user)
  end

  def find_photo
    @photo = @gallery.photos.find { |photo| photo.id.to_s == params[:id] }
    head :not_found unless @photo
  end

  def invalid_upload(error)
    redirect_to gallery_path, alert: error.message, status: :see_other
  end

  def storage_unavailable(error)
    NewRelic::Agent.notice_error(error)
    render plain: I18n.t('photos.unavailable'), status: :service_unavailable
  end
end
