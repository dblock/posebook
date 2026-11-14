# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstagramProfile, :aggregate_failures do
  it 'accepts handles and profile links and removes tracking information' do
    [' @Participant.Name ', 'Participant.Name', 'instagram.com/Participant.Name', 'http://www.instagram.com/Participant.Name/',
     'https://INSTAGRAM.com/Participant.Name/?igsh=tracking#fragment'].each do |value|
      expect(described_class.normalize(value)).to eq('participant.name')
      expect(described_class.url(value)).to eq('https://www.instagram.com/participant.name/')
    end
  end

  it 'rejects other hosts, unsafe URLs, content paths, and invalid usernames' do
    ['https://instagram.com.evil.test/participant', 'https://evil.test/participant', 'javascript:alert(1)',
     'https://evil.test@instagram.com/participant', 'https://instagram.com:444/participant',
     'https://instagram.com/p/post/', 'https://instagram.com/p/', 'https://instagram.com/reels/',
     'https://instagram.com/stories/participant/', 'https://instagram.com/participant/extra',
     'https://instagram.com/participant%2fother', 'https://[broken', 'participant name', '..', 'participant..name',
     'participant.', 'a' * 31, nil, ''].each do |value|
      expect(described_class.normalize(value)).to be_nil, value.inspect
      expect(described_class.url(value)).to be_nil, value.inspect
    end
  end
end
