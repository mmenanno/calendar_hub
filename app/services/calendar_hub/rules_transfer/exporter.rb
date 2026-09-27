# frozen_string_literal: true

module CalendarHub
  module RulesTransfer
    class Exporter
      FILENAME_PREFIXES = {
        [:event_mappings, :filter_rules] => "calendar-hub-rules",
        [:event_mappings] => "calendar-hub-mappings",
        [:filter_rules] => "calendar-hub-filters",
      }.freeze

      attr_reader :kinds

      def initialize(kinds: RulesTransfer.kinds)
        @kinds = RulesTransfer.normalize_kinds(kinds)
        raise ArgumentError, "At least one rule kind is required" if @kinds.empty?
      end

      def as_json(*)
        document = {
          "format" => FORMAT,
          "version" => VERSION,
          "exported_at" => Time.current.utc.iso8601,
        }
        kinds.each { |kind| document[kind.to_s] = rows_for(kind) }
        document
      end

      def to_json(*)
        JSON.pretty_generate(as_json)
      end

      def filename
        "#{FILENAME_PREFIXES.fetch(kinds)}-#{Time.current.strftime("%Y%m%d")}.json"
      end

      private

      def rows_for(kind)
        fields = KINDS.fetch(kind)[:fields].keys - ["source"]
        RulesTransfer.model_for(kind).order(:position, :created_at, :id).map do |record|
          { "source" => source_names[record.calendar_source_id] }.merge(fields.index_with { |field| record.public_send(field) })
        end
      end

      # Includes archived sources so their rules keep a reference by name rather
      # than silently turning into global rules.
      def source_names
        @source_names ||= CalendarSource.unscoped.pluck(:id, :name).to_h
      end
    end
  end
end
