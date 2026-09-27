# frozen_string_literal: true

# Export / import of event mappings and filter rules.
#
# Flow: new (upload form) -> preview (validate, show counts, hand back an
# encrypted token holding the raw document) -> apply (decrypt the token and
# re-validate server-side; nothing posted by the client besides the token and
# the chosen options is trusted).
class RulesTransfersController < ApplicationController
  RETURN_PATHS = {
    "event_mappings" => :event_mappings_path,
    "filter_rules" => :filter_rules_path,
  }.freeze

  before_action :set_kind
  before_action :set_options, only: [:preview, :apply]

  def export
    kinds = CalendarHub::RulesTransfer.kinds.map(&:to_s).include?(params[:only]) ? [params[:only]] : CalendarHub::RulesTransfer.kinds
    exporter = CalendarHub::RulesTransfer::Exporter.new(kinds: kinds)
    send_data(exporter.to_json, filename: exporter.filename, type: :json, disposition: "attachment")
  end

  def new; end

  def preview
    raw = read_document
    return render_upload_errors(@input_error) if raw.nil?

    @result = importer_for(raw).preview
    return render_upload_errors(*@result.errors) unless @result.valid?

    @token = CalendarHub::RulesTransfer::Token.generate(raw)
    render(:preview)
  end

  def apply
    raw = CalendarHub::RulesTransfer::Token.read(params[:token])
    return render_upload_errors(t("flashes.rules_transfer.token_invalid")) if raw.nil?

    if @mode == "replace" && params[:confirm_replace] != "1"
      @result = importer_for(raw).preview
      @token = params[:token]
      @errors = [t("flashes.rules_transfer.confirm_replace_required")]
      return render(:preview, status: :unprocessable_content)
    end

    result = importer_for(raw).apply!
    return render_upload_errors(*result.errors) unless result.applied?

    added = result.total(:add)
    notice = if added.zero? && !result.replace?
      t("flashes.rules_transfer.nothing_imported")
    else
      t("flashes.rules_transfer.imported", count: added)
    end
    redirect_to(return_path(result), notice: notice, status: :see_other)
  end

  private

  def set_kind
    @kind = params.fetch(:kind, nil).presence_in(RETURN_PATHS.keys)
  end

  def set_options
    @mode = params.fetch(:mode, nil).presence_in(CalendarHub::RulesTransfer::Importer::MODES) || "append"
    @unknown_sources = params.fetch(:unknown_sources, nil).presence_in(CalendarHub::RulesTransfer::Importer::UNKNOWN_SOURCE_STRATEGIES) || "skip"
  end

  def importer_for(raw)
    CalendarHub::RulesTransfer::Importer.new(raw, mode: @mode, unknown_sources: @unknown_sources)
  end

  # Returns the raw JSON from (in order) a token from a previous preview, an
  # uploaded file, or pasted text. Sets @input_error and returns nil otherwise.
  def read_document
    if params[:token].present?
      raw = CalendarHub::RulesTransfer::Token.read(params[:token])
      @input_error = t("flashes.rules_transfer.token_invalid") if raw.nil?
      return raw
    end

    file = params[:file]
    return file.read(CalendarHub::RulesTransfer::Importer::MAX_BYTES + 1).to_s.force_encoding(Encoding::UTF_8) if file.respond_to?(:read)

    return params[:json].to_s if params[:json].is_a?(String) && params[:json].present?

    @input_error = t("flashes.rules_transfer.no_input")
    nil
  end

  def render_upload_errors(*errors)
    @errors = errors
    render(:new, status: :unprocessable_content)
  end

  # Back to the page the import started from, else the first imported kind
  def return_path(result)
    kind = @kind || result.kinds.first.to_s
    public_send(RETURN_PATHS.fetch(kind, :event_mappings_path))
  end
end
