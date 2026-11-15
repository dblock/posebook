# frozen_string_literal: true

module PrimaryPhoto
  extend ActiveSupport::Concern

  included do
    field :primary_photo_id, type: BSON::ObjectId
  end

  module ClassMethods
    def preload_primary_photos(owners)
      owners = owners.to_a
      return owners if owners.empty?

      association = reflect_on_association(:photos)
      photos = selected_primary_photos(owners, association)
      missing = owners.reject { |owner| photos.key?(owner.id) }
      photos.merge!(first_primary_photos(missing, association))
      owners.each { |owner| owner.preload_primary_photo(photos[owner.id]) }
      preload_fallback_venues(owners)
      owners
    end

    private

    def selected_primary_photos(owners, association)
      candidates = primary_photo_candidates(owners, association)
      owners.filter_map do |owner|
        photo = candidates[owner.primary_photo_id]
        [owner.id, photo] if photo && photo[association.foreign_key] == owner.id
      end.to_h
    end

    def primary_photo_candidates(owners, association)
      ids = owners.filter_map(&:primary_photo_id)
      return {} if ids.empty?

      association.klass.where(association.foreign_key => { '$in' => owners.map(&:id) },
                              :id.in => ids).index_by(&:id)
    end

    def first_primary_photos(owners, association)
      return {} if owners.empty?

      foreign_key = association.foreign_key
      pipeline = [
        { '$match' => { foreign_key => { '$in' => owners.map(&:id) } } },
        { '$sort' => { foreign_key => 1, 'created_at' => 1 } },
        { '$group' => { '_id' => "$#{foreign_key}", 'photo_id' => { '$first' => '$_id' } } }
      ]
      ids = association.klass.collection.aggregate(pipeline).pluck('photo_id')
      association.klass.where(:id.in => ids).index_by { |photo| photo[foreign_key] }
    end

    def preload_fallback_venues(owners)
      return unless reflect_on_association(:venue)

      venues = owners.filter_map { |owner| owner.venue unless owner.primary_photo }.uniq(&:id)
      Venue.preload_primary_photos(venues)
    end
  end

  def preload_primary_photo(photo)
    @primary_photo_snapshot = [id, primary_photo_id, photo]
  end

  def primary_photo(photos = nil)
    return photos.find { |photo| photo.id == primary_photo_id } || photos.first if photos
    return @primary_photo_snapshot.last if primary_photo_loaded?

    selected = self.photos.where(id: primary_photo_id).first if primary_photo_id
    selected || self.photos.order_by(created_at: :asc).first
  end

  def reload(...)
    @primary_photo_snapshot = nil
    super
  end

  private

  def primary_photo_loaded?
    @primary_photo_snapshot && @primary_photo_snapshot[0] == id && @primary_photo_snapshot[1] == primary_photo_id
  end
end
