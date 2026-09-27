# frozen_string_literal: true

module CalendarHub
  # Import/export of event mappings and filter rules as a portable JSON
  # document. Sources are referenced by name because ids differ between
  # installs; a null source means the rule is global.
  module RulesTransfer
    FORMAT = "calendar_hub.rules"
    VERSION = 1

    KINDS = {
      event_mappings: {
        model: "EventMapping",
        fields: {
          "source" => :nullable_string,
          "match_type" => :string,
          "pattern" => :string,
          "replacement" => :nullable_string,
          "target_calendar_identifier" => :nullable_string,
          "target_calendar_display_name" => :nullable_string,
          "case_sensitive" => :boolean,
          "active" => :boolean,
        },
        required: ["match_type", "pattern"],
        enums: { "match_type" => EventMapping::MATCH_TYPES.values },
        # Attributes that make two rules "the same rule" for duplicate detection
        identity: ["match_type", "pattern", "case_sensitive", "replacement", "target_calendar_identifier"],
      },
      filter_rules: {
        model: "FilterRule",
        fields: {
          "source" => :nullable_string,
          "field_name" => :string,
          "match_type" => :string,
          "pattern" => :string,
          "case_sensitive" => :boolean,
          "active" => :boolean,
        },
        required: ["field_name", "match_type", "pattern"],
        enums: {
          "field_name" => FilterRule::FIELD_NAMES.values,
          "match_type" => FilterRule::MATCH_TYPES.values,
        },
        identity: ["field_name", "match_type", "pattern", "case_sensitive"],
      },
    }.freeze

    class << self
      def kinds
        KINDS.keys
      end

      def model_for(kind)
        case KINDS.fetch(kind.to_sym)[:model]
        when "EventMapping" then EventMapping
        when "FilterRule" then FilterRule
        end
      end

      def normalize_kinds(kinds)
        list = Array(kinds).map(&:to_sym)
        unknown = list - self.kinds
        raise ArgumentError, "Unknown rule kinds: #{unknown.join(", ")}" if unknown.any?

        self.kinds & list
      end
    end
  end
end
