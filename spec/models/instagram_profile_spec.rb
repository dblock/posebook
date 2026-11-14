# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstagramProfile, :aggregate_failures do
  it 'accepts handles and profile links and removes tracking information' do
    [' @Artist.Name ', 'Artist.Name', 'instagram.com/Artist.Name', 'http://www.instagram.com/Artist.Name/',
     'https://INSTAGRAM.com/Artist.Name/?igsh=tracking#fragment'].each do |value|
      expect(described_class.normalize(value)).to eq('artist.name')
      expect(described_class.url(value)).to eq('https://www.instagram.com/artist.name/')
    end
  end

  it 'rejects other hosts, unsafe URLs, content paths, and invalid usernames' do
    ['https://instagram.com.evil.test/artist', 'https://evil.test/artist', 'javascript:alert(1)',
     'https://evil.test@instagram.com/artist', 'https://instagram.com:444/artist',
     'https://instagram.com/p/post/', 'https://instagram.com/p/', 'https://instagram.com/reels/',
     'https://instagram.com/stories/artist/', 'https://instagram.com/artist/extra',
     'https://instagram.com/artist%2fother', 'https://[broken', 'artist name', '..', 'artist..name',
     'artist.', 'a' * 31, nil, ''].each do |value|
      expect(described_class.normalize(value)).to be_nil, value.inspect
      expect(described_class.url(value)).to be_nil, value.inspect
    end
  end
end
