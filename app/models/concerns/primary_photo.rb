# frozen_string_literal: true

module PrimaryPhoto
  extend ActiveSupport::Concern

  included do
    field :primary_photo_id, type: BSON::ObjectId
  end

  PUBLIC_SELECTOR = { 'public' => { '$ne' => false } }.freeze

  module ClassMethods
    def preload_primary_photos(owners, series: false)
      owners = owners.to_a
      return owners if owners.empty?

      association = reflect_on_association(:photos)
      photos = selected_primary_photos(owners, association)
      missing = owners.reject { |owner| photos.key?(owner.id) }
      photos.merge!(first_primary_photos(missing, association))
      owners.each { |owner| owner.preload_primary_photo(photos[owner.id]) }
      preload_photo_series(owners, association) if series
      preload_fallback_venues(owners, series: series)
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

      association.klass.where(PUBLIC_SELECTOR).where(association.foreign_key => { '$in' => owners.map(&:id) },
                                                     :id.in => ids).index_by(&:id)
    end

    def first_primary_photos(owners, association)
      return {} if owners.empty?

      foreign_key = association.foreign_key
      pipeline = [
        { '$match' => PUBLIC_SELECTOR.merge(foreign_key => { '$in' => owners.map(&:id) }) },
        { '$sort' => { foreign_key => 1, 'created_at' => 1 } },
        { '$group' => { '_id' => "$#{foreign_key}", 'photo_id' => { '$first' => '$_id' } } }
      ]
      ids = association.klass.collection.aggregate(pipeline).pluck('photo_id')
      association.klass.where(:id.in => ids).index_by { |photo| photo[foreign_key] }
    end

    def preload_photo_series(owners, association)
      owners = owners.select(&:primary_photo)
      return if owners.empty?

      foreign_key = association.foreign_key
      photos = association.klass.where(PUBLIC_SELECTOR).where(foreign_key => { '$in' => owners.map(&:id) })
                          .order_by(created_at: :asc).pluck(foreign_key, :id).group_by(&:first)
      owners.each { |owner| owner.preload_public_photo_ids(photos.fetch(owner.id, []).map(&:last)) }
    end

    def preload_fallback_venues(owners, series:)
      return unless reflect_on_association(:venue)

      venues = owners.filter_map { |owner| owner.venue unless owner.primary_photo }.uniq(&:id)
      Venue.preload_primary_photos(venues, series: series)
    end
  end

  def preload_primary_photo(photo)
    @primary_photo_snapshot = [id, primary_photo_id, photo]
  end

  def primary_photo(photos = nil)
    return primary_photo_from(photos) if photos
    return @primary_photo_snapshot.last if primary_photo_loaded?

    public_photos = self.photos.where(PUBLIC_SELECTOR)
    selected = public_photos.where(id: primary_photo_id).first if primary_photo_id
    selected || public_photos.order_by(created_at: :asc).first
  end

  def preload_public_photo_ids(ids)
    @public_photo_ids_snapshot = [id, primary_photo_id, ids]
  end

  def public_photo_ids
    unless @public_photo_ids_snapshot&.first(2) == [id, primary_photo_id]
      preload_public_photo_ids(photos.where(PUBLIC_SELECTOR).order_by(created_at: :asc).pluck(:id))
    end
    @public_photo_ids_snapshot.last
  end

  def reload(...)
    @primary_photo_snapshot = nil
    @public_photo_ids_snapshot = nil
    super
  end

  private

  def primary_photo_from(photos)
    photos = photos.reject { |photo| photo.attributes['public'] == false }
    photos.find { |photo| photo.id == primary_photo_id } || photos.first
  end

  def primary_photo_loaded?
    @primary_photo_snapshot && @primary_photo_snapshot[0] == id && @primary_photo_snapshot[1] == primary_photo_id
  end
end
