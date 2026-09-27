# frozen_string_literal: true

module CalendarHub
  module RulesTransfer
    # Parses and strictly validates a rules document, classifies each row
    # (add / duplicate / unknown source / invalid) and, on #apply!, writes the
    # rows in a single transaction and schedules one resync per affected source.
    class Importer
      MODES = ["append", "replace"].freeze
      UNKNOWN_SOURCE_STRATEGIES = ["skip", "global"].freeze
      MAX_BYTES = 1.megabyte
      MAX_ROWS = 1_000
      MAX_STRING_LENGTH = 1_000
      TOP_LEVEL_KEYS = ["format", "version", "exported_at", *RulesTransfer.kinds.map(&:to_s)].freeze

      def initialize(raw, mode: "append", unknown_sources: "skip")
        raise ArgumentError, "Unknown import mode: #{mode}" unless MODES.include?(mode.to_s)
        raise ArgumentError, "Unknown source strategy: #{unknown_sources}" unless UNKNOWN_SOURCE_STRATEGIES.include?(unknown_sources.to_s)

        @raw = raw.to_s.dup.force_encoding(Encoding::UTF_8)
        @mode = mode.to_s
        @unknown_sources = unknown_sources.to_s
      end

      def preview
        build_result
      end

      def apply!
        result = build_result
        return result unless result.valid?

        affected = Hash.new { |hash, key| hash[key] = Set.new }

        ActiveRecord::Base.transaction do
          result.kinds.each do |kind|
            model = RulesTransfer.model_for(kind)
            if result.replace?
              affected[kind].merge(model.unscoped.distinct.pluck(:calendar_source_id))
              model.unscoped.delete_all
            end
            insert_rows(model, result.rows_to_add(kind), affected[kind])
          end
        end

        result.mark_applied!
        after_apply(affected)
        result
      end

      private

      def build_result
        result = Result.new(mode: @mode, unknown_sources: @unknown_sources)
        document = parse_document(result)
        return result unless result.valid?

        result.kinds.replace(RulesTransfer.kinds.select { |kind| document.key?(kind.to_s) })
        result.kinds.each do |kind|
          result.replaced_counts[kind] = RulesTransfer.model_for(kind).count if result.replace?
          classify_rows(kind, document[kind.to_s], result)
        end
        result
      end

      # -- Document -------------------------------------------------------------

      def parse_document(result)
        return add_error(result, :too_large, limit: ActiveSupport::NumberHelper.number_to_human_size(MAX_BYTES)) if @raw.bytesize > MAX_BYTES
        return add_error(result, :invalid_json) unless @raw.valid_encoding?
        return add_error(result, :blank) if @raw.strip.empty?

        document = parse_json
        return add_error(result, :invalid_json) if document == :invalid

        validate_document(document, result)
        document
      end

      def parse_json
        JSON.parse(@raw, max_nesting: 10)
      rescue JSON::ParserError, EncodingError
        :invalid
      end

      def validate_document(document, result)
        return add_error(result, :not_an_object) unless document.is_a?(Hash)

        add_error(result, :wrong_format, expected: FORMAT) unless document["format"] == FORMAT
        add_error(result, :unsupported_version, version: VERSION) unless document["version"].is_a?(Integer) && document["version"] == VERSION

        unknown = document.keys - TOP_LEVEL_KEYS
        add_error(result, :unknown_keys, keys: unknown.join(", ")) if unknown.any?

        lists = RulesTransfer.kinds.map(&:to_s).select { |key| document.key?(key) }
        return add_error(result, :no_rules) if lists.empty?

        lists.each do |key|
          add_error(result, :not_a_list, key: key) unless document[key].is_a?(Array)
        end
        return unless result.valid?

        total = lists.sum { |key| document[key].size }
        add_error(result, :too_many_rows, limit: MAX_ROWS) if total > MAX_ROWS
      end

      def add_error(result, key, **)
        result.errors << I18n.t("rules_transfer.errors.#{key}", **)
        nil
      end

      # -- Rows -----------------------------------------------------------------

      def classify_rows(kind, raw_rows, result)
        seen = result.replace? ? Set.new : existing_identities(kind)

        raw_rows.each_with_index do |raw_row, index|
          reasons = row_errors(kind, raw_row)
          source_name = raw_row["source"] if raw_row.is_a?(Hash)
          unless reasons.empty?
            result.rows << build_row(kind: kind, index: index, source_name: source_name, status: :invalid, reasons: reasons)
            next
          end

          source_id, unknown = resolve_source(source_name)
          attributes = build_attributes(kind, raw_row).merge("calendar_source_id" => source_id)

          status = if unknown && @unknown_sources == "skip"
            :unknown_source
          elsif seen.add?(identity(kind, attributes))
            :add
          else
            :duplicate
          end

          result.rows << build_row(kind: kind, index: index, attributes: attributes, source_name: source_name, status: status, unknown_source: unknown)
        end
      end

      def build_row(**)
        Result::Row.new(attributes: nil, reasons: [], unknown_source: false, **)
      end

      def row_errors(kind, raw_row)
        return [I18n.t("rules_transfer.errors.row_not_object")] unless raw_row.is_a?(Hash)

        spec = KINDS.fetch(kind)
        reasons = []

        unknown = raw_row.keys - spec[:fields].keys
        reasons << I18n.t("rules_transfer.errors.row_unknown_keys", keys: unknown.join(", ")) if unknown.any?

        spec[:required].each do |field|
          reasons << I18n.t("rules_transfer.errors.row_missing", field: field) if raw_row[field].nil?
        end

        spec[:fields].each do |field, type|
          next if raw_row[field].nil?

          reasons.concat(type_errors(field, type, raw_row[field]))
        end

        spec[:enums].each do |field, allowed|
          value = raw_row[field]
          next if value.nil? || !value.is_a?(String) || allowed.include?(value)

          reasons << I18n.t("rules_transfer.errors.row_enum", field: field, allowed: allowed.join(", "))
        end

        pattern = raw_row["pattern"]
        if pattern.is_a?(String)
          reasons << I18n.t("rules_transfer.errors.row_blank", field: "pattern") if pattern.strip.empty?
          regex_problem = regex_error(pattern) if raw_row["match_type"] == "regex"
          reasons << regex_problem if regex_problem
        end

        reasons.concat(model_errors(kind, raw_row)) if reasons.empty?
        reasons
      end

      def type_errors(field, type, value)
        case type
        when :string, :nullable_string
          return [I18n.t("rules_transfer.errors.row_type", field: field, type: "string")] unless value.is_a?(String)
          return [I18n.t("rules_transfer.errors.row_too_long", field: field, limit: MAX_STRING_LENGTH)] if value.length > MAX_STRING_LENGTH
        when :boolean
          return [I18n.t("rules_transfer.errors.row_type", field: field, type: "true/false")] unless [true, false].include?(value)
        end
        []
      end

      def regex_error(pattern)
        Regexp.new(pattern)
        nil
      rescue RegexpError => exception
        I18n.t("rules_transfer.errors.row_regex", message: exception.message)
      end

      # Reuse model validations (e.g. mappings need a replacement or destination)
      def model_errors(kind, raw_row)
        record = RulesTransfer.model_for(kind).new(build_attributes(kind, raw_row))
        return [] if record.valid?

        record.errors.full_messages
      end

      def build_attributes(kind, raw_row)
        fields = KINDS.fetch(kind)[:fields].keys - ["source"]
        attributes = fields.index_with { |field| raw_row[field] }
        attributes["case_sensitive"] = false if attributes["case_sensitive"].nil?
        attributes["active"] = true if attributes["active"].nil?
        attributes
      end

      def resolve_source(name)
        return [nil, false] if name.nil?

        id = source_ids_by_name[name]
        id ? [id, false] : [nil, true]
      end

      def source_ids_by_name
        @source_ids_by_name ||= CalendarSource.order(:id).pluck(:name, :id).reverse.to_h
      end

      def identity(kind, attributes)
        [attributes["calendar_source_id"], *KINDS.fetch(kind)[:identity].map { |field| attributes[field] }]
      end

      def existing_identities(kind)
        columns = ["calendar_source_id", *KINDS.fetch(kind)[:identity]]
        RulesTransfer.model_for(kind).unscoped.pluck(*columns).to_set
      end

      # -- Apply ----------------------------------------------------------------

      # insert_all skips per-record callbacks on purpose: those would enqueue a
      # resync per row. after_apply schedules them once per affected source.
      def insert_rows(model, rows, affected_source_ids)
        return if rows.empty?

        start = (model.unscoped.maximum(:position) || -1) + 1
        records = rows.each_with_index.map do |row, offset|
          row.attributes.merge("position" => start + offset)
        end
        model.insert_all!(records) # rubocop:disable Rails/SkipsModelValidations -- rows were validated against the model in #row_errors
        affected_source_ids.merge(records.pluck("calendar_source_id"))
      end

      def after_apply(affected)
        mapping_sources = expand_sources(affected[:event_mappings])
        filter_sources = expand_sources(affected[:filter_rules])

        clear_name_mapper_cache unless affected[:event_mappings].empty?

        # Same mechanisms EventMapping / FilterRule callbacks use, once per source
        mapping_sources.select(&:syncable?).each { |source| SyncCalendarJob.perform_later(source.id) }
        filter_sources.each { |source| SyncFilterRulesJob.perform_later(calendar_source_id: source.id) }
      end

      # A nil id means a global rule changed, which affects every active source
      def expand_sources(source_ids)
        return [] if source_ids.empty?
        return CalendarSource.active.to_a if source_ids.include?(nil)

        CalendarSource.where(id: source_ids.to_a).to_a
      end

      def clear_name_mapper_cache
        ["global", *CalendarSource.unscoped.ids].each do |key|
          Rails.cache.delete("name_mapper/active_mappings/#{key}")
        end
      end
    end
  end
end
