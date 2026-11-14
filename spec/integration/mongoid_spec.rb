# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/scaffold_document'

RSpec.describe Mongoid do
  it 'persists and reads a document through the configured Rails client' do
    document = ScaffoldDocument.create!(message: 'Posebook')

    expect(ScaffoldDocument.find(document.id).message).to eq('Posebook')
  ensure
    document&.destroy!
  end
end
