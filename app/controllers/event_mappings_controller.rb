# frozen_string_literal: true

class EventMappingsController < ApplicationController
  before_action :set_mapping, only: [:destroy]

  def index
    @mappings = EventMapping.includes(:calendar_source).order(:position, :created_at)
  end

  def reorder
    ids = Array(params[:order]).map(&:to_i)
    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, idx|
        if (m = EventMapping.find_by(id: id))
          m.update!(position: idx)
        end
      end
    end
    head(:ok)
  end

  def toggle
    mapping = EventMapping.find(params[:id])
    mapping.update!(active: !mapping.active?)
    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.replace(view_context.dom_id(mapping, :row), partial: "event_mappings/row", locals: { mapping: mapping }),
          turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t(mapping.active? ? "flashes.mappings.enabled" : "flashes.mappings.disabled") }),
        ])
      end
      format.html { redirect_to(event_mappings_path) }
    end
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
            turbo_stream.replace("new_mapping_form", render_to_string(inline: <<~ERB)
              <div id="new_mapping_form" class="rounded-2xl border border-slate-800 bg-slate-900/70 p-5" data-controller="collapsible" data-collapsible-key-value="add-rule" data-collapsible-default-open-value="false" data-collapsible-remember-value="false">
                <div class="mb-3 flex items-center justify-between">
                  <h2 class="text-lg font-semibold">Add Rule</h2>
                  <button type="button" class="cursor-pointer rounded-lg border border-slate-700 px-3 py-1 text-xs text-slate-200 hover:border-slate-500" data-action="collapsible#toggle">
                    <span data-collapsible-target="label">Show</span>
                    <span data-collapsible-target="icon" class="ml-1 inline-block transition-transform">▾</span>
                  </button>
                </div>
                <div data-collapsible-target="content" class="hidden">
                  <%= form_with model: EventMapping.new, url: event_mappings_path, class: "grid gap-3", data: { controller: "mapping-form" } do |f| %>
                    <div>
                      <label class="mb-1 block text-[11px] font-semibold uppercase tracking-wide text-slate-400">Source</label>
                      <div class="select-chevron">
                        <%= f.collection_select(:calendar_source_id, CalendarSource.order(:name), :id, :name, { include_blank: "All" }, class: select_class) %>
                      </div>
                    </div>
                    <div>
                      <label class="mb-1 block text-[11px] font-semibold uppercase tracking-wide text-slate-400">Match</label>
                      <div class="select-chevron wide-select">
                        <%= f.select(:match_type, EventMapping::MATCH_TYPES.values.map { |t| [t.humanize, t] }, {}, class: select_class, data: { mapping_form_target: "match", action: "change->mapping-form#validate" }) %>
                      </div>
                    </div>
                    <div>
                      <%= f.label(:pattern, class: "mb-1 block text-[11px] font-semibold uppercase tracking-wide text-slate-400") %>
                      <%= f.text_field(:pattern, required: true, placeholder: "e.g. In-Person Counselling", class: input_class, data: { mapping_form_target: "pattern", action: "input->mapping-form#validate" }) %>
                      <p data-mapping-form-target="error" class="mt-1 hidden text-xs text-rose-300">Invalid regular expression</p>
                    </div>
                    <div>
                      <%= f.label(:replacement, class: "mb-1 block text-[11px] font-semibold uppercase tracking-wide text-slate-400") %>
                      <%= f.text_field(:replacement, required: true, placeholder: "Michael Therapy - In Person", class: input_class) %>
                    </div>
                    <label class="inline-flex items-center gap-2 text-xs text-slate-400">
                      <%= f.check_box(:case_sensitive) %>
                      Case sensitive
                    </label>
                    <%= f.submit("Add Mapping", class: "rounded-lg bg-indigo-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-indigo-400", data: { mapping_form_target: "submit" }) %>
                  <% end %>
                </div>
              </div>
            ERB
            ),
          ])
        end
        format.html { redirect_back(fallback_location: event_mappings_path, notice: t("flashes.mappings.added")) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: @mapping.errors.full_messages.to_sentence, variant: :error }), status: :unprocessable_entity)
        end
        format.html { redirect_back(fallback_location: event_mappings_path, alert: @mapping.errors.full_messages.to_sentence) }
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
      render(partial: "event_mappings/form_row", locals: { mapping: @mapping }, status: :unprocessable_entity)
    end
  end

  def duplicate
    original = EventMapping.find(params[:id])
    copy = original.dup
    copy.position = EventMapping.maximum(:position).to_i + 1
    copy.save!
    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.after(
            view_context.dom_id(original, :row),
            render_to_string(partial: "event_mappings/row", locals: { mapping: copy }),
          ),
          turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.mappings.duplicated") }),
        ])
      end
      format.html { redirect_to(event_mappings_path, notice: t("flashes.mappings.duplicated")) }
    end
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
      format.html { redirect_back(fallback_location: event_mappings_path, notice: t("flashes.mappings.removed")) }
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
