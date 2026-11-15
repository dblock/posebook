# frozen_string_literal: true

class PagesController < ApplicationController
  helper_method :participant_dashboard
  before_action :require_authentication, except: %i[about privacy terms]

  def home
    programs = Program.managed_by(current_user).includes(:venue).order_by(name: :asc)
    @managed_programs = Program.preload_primary_photos(programs)
  end

  def about; end
  def privacy; end
  def terms; end
end
