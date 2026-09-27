# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module RulesTransfer
    class ImporterTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      def document(event_mappings: nil, filter_rules: nil, **overrides)
        doc = { "format" => "calendar_hub.rules", "version" => 1, "exported_at" => "2026-09-26T12:00:00Z" }
        doc["event_mappings"] = event_mappings unless event_mappings.nil?
        doc["filter_rules"] = filter_rules unless filter_rules.nil?
        doc.merge(overrides.stringify_keys).to_json
      end

      def mapping_row(**attrs)
        {
          "source" => nil,
          "match_type" => "contains",
          "pattern" => "Imported",
          "replacement" => "Renamed",
          "target_calendar_identifier" => nil,
          "target_calendar_display_name" => nil,
          "case_sensitive" => false,
          "active" => true,
        }.merge(attrs.stringify_keys)
      end

      def filter_row(**attrs)
        {
          "source" => nil,
          "field_name" => "title",
          "match_type" => "contains",
          "pattern" => "Imported",
          "case_sensitive" => false,
          "active" => true,
        }.merge(attrs.stringify_keys)
      end

      def comparable_export
        Exporter.new.as_json.except("exported_at")
      end

      # -- Round trip -----------------------------------------------------------

      test "export then import into an empty database recreates identical rules" do
        original = comparable_export
        json = Exporter.new.to_json

        EventMapping.delete_all
        FilterRule.delete_all

        result = Importer.new(json).apply!

        assert_predicate(result, :applied?)
        assert_equal(original, comparable_export)
      end

      test "re-importing an export in append mode skips everything as duplicates" do
        json = Exporter.new.to_json

        assert_no_difference(["EventMapping.count", "FilterRule.count"]) do
          result = Importer.new(json).apply!

          assert_equal(0, result.count(:event_mappings, :add))
          assert_equal(EventMapping.count, result.count(:event_mappings, :duplicate))
          assert_equal(FilterRule.count, result.count(:filter_rules, :duplicate))
        end
      end

      # -- Document validation --------------------------------------------------

      test "rejects malformed JSON" do
        result = Importer.new("{not json").preview

        refute_predicate(result, :valid?)
        assert_match(/not valid JSON/i, result.errors.to_sentence)
      end

      test "rejects input that is not valid UTF-8" do
        result = Importer.new("{\"format\": \"\xFF\"}".b).preview

        refute_predicate(result, :valid?)
        assert_match(/not valid JSON/i, result.errors.to_sentence)
      end

      test "rejects blank input" do
        result = Importer.new("   ").preview

        refute_predicate(result, :valid?)
      end

      test "rejects documents that are too large" do
        huge = document(event_mappings: []) + (" " * Importer::MAX_BYTES)

        result = Importer.new(huge).preview

        refute_predicate(result, :valid?)
        assert_match(/too large/i, result.errors.to_sentence)
      end

      test "rejects a non-object top level" do
        result = Importer.new("[]").preview

        refute_predicate(result, :valid?)
      end

      test "rejects the wrong format marker" do
        result = Importer.new(document(event_mappings: [], format: "something.else")).preview

        refute_predicate(result, :valid?)
        assert_match(/format/i, result.errors.to_sentence)
      end

      test "rejects unsupported versions" do
        result = Importer.new(document(event_mappings: [], version: 2)).preview

        refute_predicate(result, :valid?)
        assert_match(/version/i, result.errors.to_sentence)
      end

      test "rejects a string version" do
        result = Importer.new(document(event_mappings: [], version: "1")).preview

        refute_predicate(result, :valid?)
      end

      test "rejects documents with no rule lists" do
        result = Importer.new(document).preview

        refute_predicate(result, :valid?)
      end

      test "rejects rule lists that are not arrays" do
        result = Importer.new(document(filter_rules: { "pattern" => "x" })).preview

        refute_predicate(result, :valid?)
      end

      test "rejects unknown top-level keys" do
        result = Importer.new(document(event_mappings: [], calendar_sources: [])).preview

        refute_predicate(result, :valid?)
        assert_match(/calendar_sources/, result.errors.to_sentence)
      end

      test "rejects documents with too many rows" do
        rows = Array.new(Importer::MAX_ROWS + 1) { |i| filter_row(pattern: "p#{i}") }

        result = Importer.new(document(filter_rules: rows)).preview

        refute_predicate(result, :valid?)
        assert_match(/too many/i, result.errors.to_sentence)
      end

      test "does not apply an invalid document" do
        assert_no_difference("FilterRule.count") do
          result = Importer.new(document(filter_rules: [filter_row], version: 9)).apply!

          refute_predicate(result, :applied?)
        end
      end

      # -- Row validation -------------------------------------------------------

      INVALID_FILTER_ROWS = {
        { "match_type" => "fuzzy" } => /match_type must be one of/,
        { "field_name" => "attendees" } => /field_name must be one of/,
        { "pattern" => "" } => /pattern can't be blank/,
        { "case_sensitive" => "yes" } => %r{case_sensitive must be true/false},
        { "match_type" => "regex", "pattern" => "([unclosed" } => /Invalid regular expression/,
        { "color" => "red" } => /Unknown keys: color/,
        { "pattern" => 42 } => /pattern must be string/,
        { "source" => 7 } => /source must be string/,
        { "pattern" => "x" * 1_001 } => /longer than/,
      }.freeze

      test "flags invalid rows and still imports valid ones" do
        rows = [filter_row(pattern: "Good"), "not an object", *INVALID_FILTER_ROWS.keys.map { |attrs| filter_row(**attrs) }]

        result = Importer.new(document(filter_rules: rows)).apply!

        assert_predicate(result, :applied?)
        assert_equal(1, result.count(:filter_rules, :add))
        assert_equal(rows.size - 1, result.count(:filter_rules, :invalid))
        assert(FilterRule.exists?(pattern: "Good"))
      end

      test "explains why each invalid row was rejected" do
        rows = ["not an object", *INVALID_FILTER_ROWS.keys.map { |attrs| filter_row(**attrs) }]
        expected = [/JSON object/, *INVALID_FILTER_ROWS.values]

        reasons = Importer.new(document(filter_rules: rows)).preview.rows_for(:filter_rules).map { |row| row.reasons.to_sentence }

        expected.zip(reasons).each { |pattern, reason| assert_match(pattern, reason) }
      end

      test "flags mappings that have neither a replacement nor a destination" do
        rows = [mapping_row(replacement: nil)]

        result = Importer.new(document(event_mappings: rows)).preview

        assert_equal(1, result.count(:event_mappings, :invalid))
      end

      test "accepts mappings with only a destination override" do
        rows = [mapping_row(replacement: nil, target_calendar_identifier: "Work")]

        result = Importer.new(document(event_mappings: rows)).preview

        assert_equal(1, result.count(:event_mappings, :add))
      end

      test "requires match_type and pattern" do
        row = filter_row.except("match_type")

        result = Importer.new(document(filter_rules: [row])).preview

        assert_equal(1, result.count(:filter_rules, :invalid))
        assert_match(/match_type/, result.rows_for(:filter_rules).first.reasons.to_sentence)
      end

      test "defaults optional booleans" do
        row = filter_row.except("case_sensitive", "active", "source")

        Importer.new(document(filter_rules: [row])).apply!
        rule = FilterRule.find_by!(pattern: "Imported")

        refute(rule.case_sensitive)
        assert(rule.active)
        assert_nil(rule.calendar_source_id)
      end

      # -- Duplicates -----------------------------------------------------------

      test "skips rows that duplicate existing rules" do
        existing = filter_rules(:provider_standup_filter)
        row = filter_row(source: "Provider Source", pattern: existing.pattern, field_name: "title", match_type: "contains")

        result = Importer.new(document(filter_rules: [row, filter_row])).preview

        assert_equal(1, result.count(:filter_rules, :duplicate))
        assert_equal(1, result.count(:filter_rules, :add))
      end

      test "treats a different source as a distinct rule" do
        row = filter_row(source: "Shared ICS Feed", pattern: "Standup")

        result = Importer.new(document(filter_rules: [row])).preview

        assert_equal(1, result.count(:filter_rules, :add))
      end

      test "skips duplicate rows within the same document" do
        result = Importer.new(document(filter_rules: [filter_row, filter_row])).apply!

        assert_equal(1, result.count(:filter_rules, :add))
        assert_equal(1, result.count(:filter_rules, :duplicate))
        assert_equal(1, FilterRule.where(pattern: "Imported").count)
      end

      # -- Unknown sources ------------------------------------------------------

      test "skips rows referencing unknown sources by default" do
        rows = [filter_row(source: "Nowhere"), filter_row(source: "Nowhere", pattern: "Other")]

        result = Importer.new(document(filter_rules: rows)).apply!

        assert_equal(["Nowhere"], result.unknown_source_names)
        assert_equal(2, result.count(:filter_rules, :unknown_source))
        refute(FilterRule.exists?(pattern: "Imported"))
      end

      test "can import rows with unknown sources as global rules" do
        rows = [filter_row(source: "Nowhere")]

        result = Importer.new(document(filter_rules: rows), unknown_sources: "global").apply!

        assert_equal(["Nowhere"], result.unknown_source_names)
        assert_equal(1, result.count(:filter_rules, :add))
        assert_nil(FilterRule.find_by!(pattern: "Imported").calendar_source_id)
      end

      test "archived sources count as unknown" do
        calendar_sources(:provider).soft_delete!

        result = Importer.new(document(filter_rules: [filter_row(source: "Provider Source")])).preview

        assert_equal(["Provider Source"], result.unknown_source_names)
      end

      test "maps known source names to ids" do
        Importer.new(document(event_mappings: [mapping_row(source: "Shared ICS Feed")])).apply!

        assert_equal(calendar_sources(:ics_feed).id, EventMapping.find_by!(pattern: "Imported").calendar_source_id)
      end

      # -- Positions ------------------------------------------------------------

      test "appends new rules after existing ones preserving document order" do
        max = FilterRule.maximum(:position)
        rows = [filter_row(pattern: "First"), filter_row(pattern: "Second")]

        Importer.new(document(filter_rules: rows)).apply!

        assert_equal(max + 1, FilterRule.find_by!(pattern: "First").position)
        assert_equal(max + 2, FilterRule.find_by!(pattern: "Second").position)
      end

      # -- Replace mode ---------------------------------------------------------

      test "replace mode deletes existing rules of the imported kinds only" do
        mapping_count = EventMapping.count
        rows = [filter_row(pattern: "Only")]

        result = Importer.new(document(filter_rules: rows), mode: "replace").apply!

        assert_predicate(result, :applied?)
        assert_equal(["Only"], FilterRule.pluck(:pattern))
        assert_equal(0, FilterRule.first.position)
        assert_equal(mapping_count, EventMapping.count)
      end

      test "replace mode does not treat existing rules as duplicates" do
        existing = filter_rules(:global_meeting_filter)
        row = filter_row(pattern: existing.pattern)

        result = Importer.new(document(filter_rules: [row]), mode: "replace").preview

        assert_equal(1, result.count(:filter_rules, :add))
        assert_equal(FilterRule.count, result.replaced_count(:filter_rules))
      end

      test "rejects unknown modes and strategies" do
        assert_raises(ArgumentError) { Importer.new("{}", mode: "merge") }
        assert_raises(ArgumentError) { Importer.new("{}", unknown_sources: "guess") }
      end

      # -- Side effects ---------------------------------------------------------

      test "enqueues one filter resync per affected source rather than per row" do
        provider = calendar_sources(:provider)
        rows = Array.new(3) { |i| filter_row(source: "Provider Source", pattern: "p#{i}") }

        clear_enqueued_jobs
        Importer.new(document(filter_rules: rows)).apply!

        filter_jobs = enqueued_jobs.select { |job| job["job_class"] == "SyncFilterRulesJob" }

        assert_equal(1, filter_jobs.size)
        assert_equal(provider.id, filter_jobs.first["arguments"].first["calendar_source_id"])
      end

      test "enqueues one calendar sync per active source for global mappings" do
        rows = Array.new(3) { |i| mapping_row(pattern: "p#{i}") }

        clear_enqueued_jobs
        Importer.new(document(event_mappings: rows)).apply!

        sync_jobs = enqueued_jobs.select { |job| job["job_class"] == "SyncCalendarJob" }
        expected = CalendarSource.active.select(&:syncable?).map(&:id)

        assert_equal(expected.sort, sync_jobs.map { |job| job["arguments"].first }.sort)
      end

      test "enqueues nothing when nothing changes" do
        json = Exporter.new.to_json

        clear_enqueued_jobs
        Importer.new(json).apply!

        assert_empty(enqueued_jobs)
      end

      test "replace mode resyncs sources whose rules were removed" do
        rows = [filter_row(source: "Shared ICS Feed", pattern: "Only")]

        clear_enqueued_jobs
        Importer.new(document(filter_rules: rows), mode: "replace").apply!

        # Global filters existed and were removed, so every active source is affected
        source_ids = enqueued_jobs.select { |job| job["job_class"] == "SyncFilterRulesJob" }.map { |job| job["arguments"].first["calendar_source_id"] }

        assert_equal(CalendarSource.active.ids.sort, source_ids.sort)
      end

      test "clears the name mapper cache after importing mappings" do
        Rails.cache.expects(:delete).with("name_mapper/active_mappings/global").at_least_once
        Rails.cache.stubs(:delete).with(Not(equals("name_mapper/active_mappings/global")))

        Importer.new(document(event_mappings: [mapping_row])).apply!
      end
    end
  end
end
