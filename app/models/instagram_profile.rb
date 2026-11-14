# frozen_string_literal: true

class InstagramProfile
  USERNAME = /\A(?!.*\.\.)[a-z0-9_](?:[a-z0-9._]{0,28}[a-z0-9_])?\z/i
  RESERVED = %w[accounts about developer direct explore legal p reel reels stories].freeze

  def self.normalize(value)
    username = extract_username(value.to_s.strip)
    return unless USERNAME.match?(username.to_s) && RESERVED.exclude?(username.downcase)

    "https://www.instagram.com/#{username.downcase}/"
  end

  def self.extract_username(value)
    return value.delete_prefix('@') if /\A@?[a-z0-9._]{1,30}\z/i.match?(value)

    value = "https://#{value}" unless %r{\Ahttps?://}i.match?(value)
    uri = URI.parse(value)
    uri.path.delete_prefix('/').delete_suffix('/') if profile_host?(uri)
  rescue URI::InvalidURIError
    nil
  end
  private_class_method :extract_username

  def self.profile_host?(uri)
    [URI::HTTP, URI::HTTPS].include?(uri.class) && %w[instagram.com www.instagram.com].include?(uri.host&.downcase) &&
      uri.userinfo.nil? && uri.port == uri.default_port
  end
  private_class_method :profile_host?
end
