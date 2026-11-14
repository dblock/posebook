# frozen_string_literal: true

class ScaffoldDocument
  include Mongoid::Document

  store_in collection: 'scaffold_checks'
  field :message, type: String
end
