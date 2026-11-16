# frozen_string_literal: true

module PhotoResponse
  private

  def send_photo(photo)
    thumbnail = params[:thumbnail] == '1'
    response.strong_etag = (thumbnail ? photo.thumbnail_id : photo.image_id).to_s
    response.cache_control.replace(private: true, max_age: 0, must_revalidate: true)
    return head :not_modified if request.fresh?(response)

    send_data photo.bytes(thumbnail: thumbnail),
              type: 'image/webp', disposition: 'inline', filename: 'photo.webp'
  end
end
