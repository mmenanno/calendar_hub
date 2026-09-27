# frozen_string_literal: true

# Rejects regex-type rules whose pattern does not compile, so an invalid
# pattern is caught when it is saved instead of silently never matching.
module RegexPatternValidation
  extend ActiveSupport::Concern

  included do
    validate :pattern_must_be_valid_regex, if: -> { match_type == "regex" && pattern.present? }
  end

  private

  def pattern_must_be_valid_regex
    Regexp.new(pattern)
  rescue RegexpError => exception
    errors.add(:pattern, :invalid_regex, message: "is not a valid regular expression (#{exception.message})")
  end
end
