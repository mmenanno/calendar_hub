# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module RulesTransfer
    class ExporterTest < ActiveSupport::TestCase
      test "exports a versioned document with both kinds by default" do
        travel_to(Time.utc(2026, 9, 26, 12, 0, 0)) do
          document = Exporter.new.as_json

          assert_equal("calendar_hub.rules", document["format"])
          assert_equal(1, document["version"])
          assert_equal("2026-09-26T12:00:00Z", document["exported_at"])
          assert_equal(EventMapping.count, document["event_mappings"].size)
          assert_equal(FilterRule.count, document["filter_rules"].size)
        end
      end

      test "exports mappings in position order with source names" do
        mappings = Exporter.new.as_json["event_mappings"]

        assert_equal(["Meeting", "^(.*) - (.*)", "Daily Standup", "Old Pattern", "URGENT"], mappings.pluck("pattern"))
        assert_equal(
          {
            "source" => "Provider Source",
            "match_type" => "contains",
            "pattern" => "Meeting",
            "replacement" => "Team Meeting",
            "target_calendar_identifier" => nil,
            "target_calendar_display_name" => nil,
            "case_sensitive" => false,
            "active" => true,
          },
          mappings.first,
        )
        assert_nil(mappings.third["source"])
      end

      test "exports filter rules with field names and null source for global rules" do
        rule = Exporter.new.as_json["filter_rules"].first

        assert_equal(
          {
            "source" => nil,
            "field_name" => "title",
            "match_type" => "contains",
            "pattern" => "Meeting",
            "case_sensitive" => false,
            "active" => true,
          },
          rule,
        )
      end

      test "exports only the requested kind" do
        document = Exporter.new(kinds: [:filter_rules]).as_json

        refute(document.key?("event_mappings"))
        assert_equal(FilterRule.count, document["filter_rules"].size)
      end

      test "keeps the name of an archived source" do
        calendar_sources(:provider).soft_delete!

        mappings = Exporter.new(kinds: [:event_mappings]).as_json["event_mappings"]

        assert_equal("Provider Source", mappings.first["source"])
      end

      test "rejects unknown kinds" do
        assert_raises(ArgumentError) { Exporter.new(kinds: [:calendar_sources]) }
      end

      test "builds a dated filename" do
        travel_to(Time.utc(2026, 9, 26, 12)) do
          assert_equal("calendar-hub-rules-20260926.json", Exporter.new.filename)
          assert_equal("calendar-hub-mappings-20260926.json", Exporter.new(kinds: [:event_mappings]).filename)
          assert_equal("calendar-hub-filters-20260926.json", Exporter.new(kinds: [:filter_rules]).filename)
        end
      end

      test "to_json produces parseable JSON" do
        parsed = JSON.parse(Exporter.new.to_json)

        assert_equal("calendar_hub.rules", parsed["format"])
      end
    end
  end
end
