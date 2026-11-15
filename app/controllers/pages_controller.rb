# frozen_string_literal: true

class PagesController < ApplicationController
  before_action :require_authentication, except: %i[about privacy terms]

  def home
    @dashboard = ParticipantDashboard.new(current_user)
    request.env['posebook.dashboard'] = @dashboard
  end

  def about; end
  def privacy; end
  def terms; end
end
