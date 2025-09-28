# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActiveSupport::TestCase
  class TestView
    include ApplicationHelper

    attr_reader :image_tag_calls

    def initialize
      @image_tag_calls = []
    end

    def image_tag(source, **options)
      @image_tag_calls << { source:, options: }
      "tag:#{source}"
    end
  end

  def setup
    @helper = TestView.new
  end

  def test_navigation_link_class_when_active
    assert_equal(
      "rounded-lg px-3 py-2 font-medium transition bg-indigo-500 text-white shadow shadow-indigo-500/20",
      @helper.navigation_link_class(active: true),
    )
  end

  def test_navigation_link_class_when_inactive
    assert_equal(
      "rounded-lg px-3 py-2 font-medium transition text-slate-300 hover:bg-slate-800 hover:text-white",
      @helper.navigation_link_class(active: false),
    )
  end

  def test_status_badge_class_for_cancelled
    assert_equal("text-rose-300", @helper.status_badge_class(:cancelled))
  end

  def test_status_badge_class_for_tentative
    assert_equal("text-amber-300", @helper.status_badge_class("tentative"))
  end

  def test_status_badge_class_for_other_status
    assert_equal("text-emerald-300", @helper.status_badge_class(:confirmed))
  end

  def test_select_class_appends_dropdown_styles
    result = @helper.select_class

    assert_includes(result, @helper.input_class)
    assert_includes(result, "appearance-none pr-8 bg-no-repeat")
    assert_includes(result, "bg-[url('data:image/svg+xml;utf8,<svg")
  end

  def test_flash_classes_for_notice
    assert_equal(
      "rounded-lg px-4 py-3 text-sm border flex items-start justify-between gap-3 border-emerald-700 bg-emerald-500/10 text-emerald-200",
      @helper.flash_classes(:notice),
    )
  end

  def test_flash_classes_for_error
    assert_equal(
      "rounded-lg px-4 py-3 text-sm border flex items-start justify-between gap-3 border-rose-800 bg-rose-950/40 text-rose-200",
      @helper.flash_classes(:error),
    )
  end

  def test_flash_classes_for_success
    assert_equal(
      "rounded-lg px-4 py-3 text-sm border flex items-start justify-between gap-3 border-emerald-700 bg-emerald-500/10 text-emerald-200",
      @helper.flash_classes("success"),
    )
  end

  def test_flash_classes_for_alert
    assert_equal(
      "rounded-lg px-4 py-3 text-sm border flex items-start justify-between gap-3 border-rose-800 bg-rose-950/40 text-rose-200",
      @helper.flash_classes("alert"),
    )
  end

  def test_flash_classes_for_other_type
    assert_equal(
      "rounded-lg px-4 py-3 text-sm border flex items-start justify-between gap-3 border-slate-800 bg-slate-900/70 text-slate-200",
      @helper.flash_classes(:info),
    )
  end

  def test_navigation_link_class_default_behavior
    assert_equal(
      "rounded-lg px-3 py-2 font-medium transition text-slate-300 hover:bg-slate-800 hover:text-white",
      @helper.navigation_link_class,
    )
  end

  def test_status_badge_class_for_nil
    assert_equal("text-emerald-300", @helper.status_badge_class(nil))
  end

  def test_input_class_returns_consistent_styles
    expected = "w-full rounded-lg border border-slate-800 bg-slate-900 px-3 py-2 text-sm text-slate-100 focus:border-indigo-400 focus:outline-none focus:ring-0"

    assert_equal(expected, @helper.input_class)
  end

  def test_calendar_hub_logo_defaults_to_textless
    assert_equal("tag:logos/textless_logo.png", @helper.calendar_hub_logo(class: "h-10"))
    assert_equal(
      { source: "logos/textless_logo.png", options: { alt: "Calendar Hub", class: "h-10" } },
      @helper.image_tag_calls.last,
    )
  end

  def test_calendar_hub_logo_with_text
    assert_equal("tag:logos/text_logo.png", @helper.calendar_hub_logo(type: :text))
    assert_equal(
      { source: "logos/text_logo.png", options: { alt: "Calendar Hub" } },
      @helper.image_tag_calls.last,
    )
  end

  def test_calendar_hub_logo_with_favicon
    assert_equal("tag:logos/favicon.png", @helper.calendar_hub_logo(type: :favicon))
    assert_equal(
      { source: "logos/favicon.png", options: { alt: "Calendar Hub" } },
      @helper.image_tag_calls.last,
    )
  end

  def test_calendar_hub_logo_with_unknown_type
    initial_call_count = @helper.image_tag_calls.size

    assert_nil(
      @helper.calendar_hub_logo(type: :unknown),
    )
    assert_equal(
      initial_call_count,
      @helper.image_tag_calls.size,
    )
  end
end
