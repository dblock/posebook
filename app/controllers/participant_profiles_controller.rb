# frozen_string_literal: true

class ParticipantProfilesController < ApplicationController
  def show
    response.headers['Cache-Control'] = 'private, no-store'
    @user = User.find(params.expect(:id))
    @gallery = PhotoGallery.new(@user, current_user)
    return head :not_found unless @gallery.accessible?

    @photos = @gallery.photos
  end
end
