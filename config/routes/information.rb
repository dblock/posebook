# frozen_string_literal: true

%i[about privacy terms].each { |page| get page.to_s, to: "pages##{page}" }
