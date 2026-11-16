# frozen_string_literal: true

Rails.application.config.filter_parameters += %i[
  passw email phone secret token _key crypt salt certificate otp ssn cvv cvc reason instagram display_name
  gender profile_photo venue_photo photos code state notes message
]
