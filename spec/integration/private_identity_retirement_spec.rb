# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PrivateIdentityRetirement, :aggregate_failures, :database do
  def expect_private_user(user)
    expect(user.reload).to have_attributes(display_name: nil, instagram_tagging_allowed: false)
  end

  def expect_retired_users(with_photos, without_photos, already_public, inactive)
    [with_photos, without_photos, inactive].each { |user| expect_private_user(user) }
    expect(with_photos.profile_photos.map(&:public?)).to eq([false, false])
    expect(already_public.reload).to have_attributes(display_name: 'Public Name', instagram_tagging_allowed: true)
    expect(inactive).not_to be_active
    expect_legacy_fields_removed([with_photos, without_photos, already_public, inactive])
  end

  def expect_legacy_fields_removed(users)
    users.each do |user|
      expect(User.collection.find(_id: user.id).first).not_to have_key('public_profile_private')
    end
  end

  def set_legacy_privacy(private_users, already_public)
    private_users.each do |user|
      User.collection.find(_id: user.id).update_one('$set' => { 'public_profile_private' => true })
    end
    User.collection.find(_id: already_public.id).update_one('$set' => { 'public_profile_private' => false })
  end

  it 'preserves affected users’ privacy and clears the legacy field from every user' do
    with_photos = track_record(create_user(display_name: 'Saved Name', instagram_handle: 'saved.handle',
                                           instagram_tagging_allowed: true))
    public_photo = with_photos.profile_photos.create!(public: true)
    private_photo = with_photos.profile_photos.create!(public: false)
    without_photos = track_record(create_user(display_name: 'Another Saved Name', instagram_handle: 'another.handle',
                                              instagram_tagging_allowed: true))
    already_public = track_record(create_user(display_name: 'Public Name', instagram_handle: 'public.handle',
                                              instagram_tagging_allowed: true))
    inactive = track_record(create_user(active: false, display_name: 'Inactive Name',
                                        instagram_handle: 'inactive.handle', instagram_tagging_allowed: true))

    set_legacy_privacy([with_photos, without_photos, inactive], already_public)

    described_class.call

    expect_retired_users(with_photos, without_photos, already_public, inactive)
    expect(with_photos.profile_photos.map(&:id)).to contain_exactly(public_photo.id, private_photo.id)

    described_class.call
    expect(with_photos.reload).to have_attributes(display_name: nil, instagram_tagging_allowed: false)
  end
end
