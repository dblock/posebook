# frozen_string_literal: true

Rails.application.config.session_store :cookie_store, key: '_posebook_session', expire_after: 7.days,
                                                      httponly: true, same_site: :lax
