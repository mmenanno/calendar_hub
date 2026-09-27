# frozen_string_literal: true

module CalendarHub
  module RulesTransfer
    # Outcome of previewing or applying an import. Document-level problems are
    # collected in #errors (nothing can be imported); row-level problems live on
    # each Row (that row is skipped, the rest still import).
    class Result
      STATUSES = [:add, :duplicate, :unknown_source, :invalid].freeze

      Row = Data.define(:kind, :index, :attributes, :source_name, :status, :reasons, :unknown_source) do
        STATUSES.each do |status_name|
          define_method(:"#{status_name}?") { status == status_name }
        end

        def global_fallback?
          unknown_source && add?
        end
      end

      attr_reader :errors, :rows, :kinds, :mode, :unknown_sources, :replaced_counts

      def initialize(mode:, unknown_sources:)
        @mode = mode
        @unknown_sources = unknown_sources
        @errors = []
        @rows = []
        @kinds = []
        @replaced_counts = {}
        @applied = false
      end

      def valid?
        errors.empty?
      end

      def applied?
        @applied
      end

      def mark_applied!
        @applied = true
      end

      def replace?
        mode == "replace"
      end

      def rows_for(kind)
        rows.select { |row| row.kind == kind.to_sym }
      end

      def count(kind, status)
        rows_for(kind).count { |row| row.status == status }
      end

      def total(status)
        rows.count { |row| row.status == status }
      end

      def replaced_count(kind)
        replaced_counts.fetch(kind.to_sym, 0)
      end

      def unknown_source_names
        rows.select(&:unknown_source).map(&:source_name).uniq.sort
      end

      def rows_to_add(kind)
        rows_for(kind).select(&:add?)
      end
    end
  end
end
