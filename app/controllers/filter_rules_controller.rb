# frozen_string_literal: true

class FilterRulesController < ApplicationController
  before_action :set_filter_rule, only: [:destroy, :edit, :update, :toggle, :duplicate]

  def index
    @filter_rules = FilterRule.includes(:calendar_source).order(:position, :created_at)
  end

  def reorder
    ids = Array(params[:order]).map(&:to_i)
    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, idx|
        if (rule = FilterRule.find_by(id: id))
          rule.update!(position: idx)
        end
      end
    end
    head(:ok)
  end

  def toggle
    @filter_rule.update!(active: !@filter_rule.active?)

    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.replace(view_context.dom_id(@filter_rule, :row), partial: "filter_rules/row", locals: { filter_rule: @filter_rule }),
          turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t(@filter_rule.active? ? "flashes.filter_rules.enabled" : "flashes.filter_rules.disabled") }),
        ])
      end
      format.html { redirect_to(filter_rules_path) }
    end
  end

  def test
    sample_title = params[:sample_title].to_s
    sample_description = params[:sample_description].to_s
    sample_location = params[:sample_location].to_s
    source = CalendarSource.find_by(id: params[:calendar_source_id]) if params[:calendar_source_id].present?

    test_event = Struct.new(:title, :description, :location, :calendar_source).new(
      sample_title,
      sample_description,
      sample_location,
      source,
    )

    @should_filter = CalendarHub::EventFilter.should_filter?(test_event)
    @test_input = { title: sample_title, description: sample_description, location: sample_location }

    render(turbo_stream: turbo_stream.replace(
      "filter_test_result",
      partial: "filter_rules/test_result",
      locals: { input: @test_input, should_filter: @should_filter },
    ))
  end

  def edit
    @filter_rule = FilterRule.find(params[:id])
  end

  def create
    @filter_rule = FilterRule.new(filter_rule_params)
    if @filter_rule.save
      if @filter_rule.calendar_source
        CalendarHub::FilterSyncService.new(source: @filter_rule.calendar_source).sync_filter_rules
      else
        CalendarSource.active.find_each do |source|
          CalendarHub::FilterSyncService.new(source: source).sync_filter_rules
        end
      end

      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: [
            turbo_stream.prepend("filter_rules_list", partial: "filter_rules/row", locals: { filter_rule: @filter_rule }),
            turbo_stream.replace("new_filter_rule_form", partial: "filter_rules/form", locals: { filter_rule: FilterRule.new }),
            turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.filter_rules.created") }),
          ])
        end
        format.html { redirect_to(filter_rules_path, notice: t("flashes.filter_rules.created")) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: turbo_stream.replace(
            "new_filter_rule_form",
            partial: "filter_rules/form",
            locals: { filter_rule: @filter_rule },
          ))
        end
        format.html { render(:index, status: :unprocessable_entity) }
      end
    end
  end

  def update
    @filter_rule = FilterRule.find(params[:id])
    if @filter_rule.update(filter_rule_params)
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: [
            turbo_stream.replace(view_context.dom_id(@filter_rule, :row), partial: "filter_rules/row", locals: { filter_rule: @filter_rule }),
            turbo_stream.update("modal", ""),
            turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.filter_rules.updated") }),
          ])
        end
        format.html { redirect_to(filter_rules_path, notice: t("flashes.filter_rules.updated")) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: turbo_stream.replace(
            view_context.dom_id(@filter_rule),
            partial: "filter_rules/form_row",
            locals: { filter_rule: @filter_rule },
          ))
        end
        format.html { render(:edit, status: :unprocessable_entity) }
      end
    end
  end

  def destroy
    @filter_rule.destroy!

    if @filter_rule.calendar_source
      CalendarHub::FilterSyncService.new(source: @filter_rule.calendar_source).sync_filter_rules
    else
      CalendarSource.active.find_each do |source|
        CalendarHub::FilterSyncService.new(source: source).sync_filter_rules
      end
    end

    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.remove(view_context.dom_id(@filter_rule, :row)),
          turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.filter_rules.deleted") }),
        ])
      end
      format.html { redirect_to(filter_rules_path, notice: t("flashes.filter_rules.deleted")) }
    end
  end

  def duplicate
    copy = @filter_rule.dup
    copy.position = FilterRule.maximum(:position).to_i + 1
    copy.save!

    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.after(
            view_context.dom_id(@filter_rule, :row),
            render_to_string(partial: "filter_rules/row", locals: { filter_rule: copy }),
          ),
          turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: t("flashes.filter_rules.duplicated") }),
        ])
      end
      format.html { redirect_to(filter_rules_path, notice: t("flashes.filter_rules.duplicated")) }
    end
  end

  private

  def set_filter_rule
    @filter_rule = FilterRule.find(params[:id])
  end

  def filter_rule_params
    params.expect(filter_rule: [:calendar_source_id, :match_type, :pattern, :field_name, :case_sensitive, :active, :position])
  end
end
