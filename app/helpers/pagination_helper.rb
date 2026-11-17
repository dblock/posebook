# frozen_string_literal: true

module PaginationHelper
  def cursor_page_path(cursor = nil)
    query = request.query_parameters.slice('status', 'event').merge('cursor' => cursor).compact
    query.empty? ? request.path : "#{request.path}?#{query.to_query}"
  end
end
