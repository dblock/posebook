# frozen_string_literal: true

class PagesController < ApplicationController
  helper_method :participant_dashboard
  before_action :require_authentication, except: %i[about privacy terms]

  def home; end

  def about; end
  def privacy; end
  def terms; end
end
