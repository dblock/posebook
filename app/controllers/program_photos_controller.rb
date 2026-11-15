# frozen_string_literal: true

class ProgramPhotosController < ApplicationController
  before_action :require_authentication, except: :show
  before_action :find_program
  before_action :find_photo, except: :create

  rescue_from ProfileImage::Invalid, with: :invalid_upload
  rescue_from Mongo::Error, with: :storage_unavailable

  def show
    response.headers['Cache-Control'] = 'no-store'
    send_data @photo.bytes(thumbnail: params[:thumbnail] == '1'),
              type: 'image/webp', disposition: 'inline', filename: 'photo.webp'
  end

  def create
    ProgramPhoto.add(@program, params.expect(program_photo: [:file]).fetch(:file))
    redirect_to photos_program_path(@program), notice: t('photos.program_uploaded'), status: :see_other
  end

  def update
    ProgramSettingsUpdate.new(program: @program, user: current_user).call(primary_photo_id: @photo.id)
    redirect_to photos_program_path(@program), notice: t('photos.program_primary_updated'), status: :see_other
  end

  def destroy
    @photo.destroy!
    redirect_to photos_program_path(@program), notice: t('photos.deleted'), status: :see_other
  end

  private

  def find_program
    @program = Program.find(params.expect(:program_id))
    return head :not_found if action_name == 'show' && !@program.viewable_by?(current_user)

    head :forbidden unless action_name == 'show' || @program.managed_by?(current_user)
  end

  def find_photo
    @photo = @program.photos.find(params.expect(:id))
  end

  def invalid_upload(error)
    redirect_to photos_program_path(@program), alert: error.message, status: :see_other
  end

  def storage_unavailable(error)
    NewRelic::Agent.notice_error(error)
    render plain: t('photos.unavailable'), status: :service_unavailable
  end
end
