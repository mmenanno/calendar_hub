# frozen_string_literal: true

class EventMappingsController < ApplicationController
  include Toggleable
  include Reorderable
  include Duplicatable

  before_action :set_mapping, only: [:destroy]

  def index
    @mappings = EventMapping.includes(:calendar_source).order(:position, :created_at)
  end

  def reorder
    reorder_records(EventMapping)
  end

  def toggle
    mapping = EventMapping.find(params[:id])
    toggle_field(mapping, :active, "flashes.mappings", row_partial: "event_mappings/row", locals: { mapping: mapping })
  end

  def test
    sample = params[:sample_title].to_s
    source = CalendarSource.find_by(id: params[:calendar_source_id]) if params[:calendar_source_id].present?
    @input = sample
    @output = CalendarHub::NameMapper.apply(sample, source: source)
    render(turbo_stream: turbo_stream.replace(
      "mapping_test_result",
      partial: "event_mappings/test_result",
      locals: { input: @input, output: @output },
    ))
  end

  def edit
    @mapping = EventMapping.find(params[:id])
  end

  def create
    @mapping = EventMapping.new(event_mapping_params)
    if @mapping.save
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: [
            turbo_stream.prepend(
              "mappings-rows",
              render_to_string(partial: "event_mappings/row", locals: { mapping: @mapping }),
            ),
            turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.mappings.added") }),
            turbo_stream.replace("new_mapping_form", render_to_string(partial: "event_mappings/new_form")),
          ])
        end
        format.html { redirect_back_or_to(event_mappings_path, notice: t("flashes.mappings.added")) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: @mapping.errors.full_messages.to_sentence, variant: :error }), status: :unprocessable_content)
        end
        format.html { redirect_back_or_to(event_mappings_path, alert: @mapping.errors.full_messages.to_sentence) }
      end
    end
  end

  def update
    @mapping = EventMapping.find(params[:id])
    if @mapping.update(event_mapping_params)
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: [
            turbo_stream.replace(view_context.dom_id(@mapping, :row), partial: "event_mappings/row", locals: { mapping: @mapping }),
            turbo_stream.update("modal", ""),
            turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.mappings.saved") }),
          ])
        end
        format.html { redirect_to(event_mappings_path) }
      end
    else
      render(partial: "event_mappings/form_row", locals: { mapping: @mapping }, status: :unprocessable_content)
    end
  end

  def duplicate
    original = EventMapping.find(params[:id])
    duplicate_record(original, row_partial: "event_mappings/row", success_message_key: "flashes.mappings", locals: { mapping: original })
  end

  def destroy
    mapping = @mapping
    row_id = view_context.dom_id(mapping, :row)
    mapping.destroy!
    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.remove(row_id),
          turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.mappings.removed") }),
        ])
      end
      format.html { redirect_back_or_to(event_mappings_path, notice: t("flashes.mappings.removed")) }
    end
  end

  private

  def set_mapping
    @mapping = EventMapping.find(params[:id])
  end

  def event_mapping_params
    params.expect(event_mapping: [:calendar_source_id, :match_type, :pattern, :replacement, :case_sensitive, :position, :active])
  end
end
