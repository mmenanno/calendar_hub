# frozen_string_literal: true

require "test_helper"

class CalendarSourceImportStartDateTest < ActiveSupport::TestCase
  def setup
    @source = CalendarSource.new(
      name: "Test Source",
      ingestion_url: "https://example.com/calendar.ics",
      calendar_identifier: "test-cal",
    )
  end

  test "sets import_start_date automatically on create" do
    freeze_time do
      @source.save!

      assert_equal(Time.current, @source.import_start_date)
    end
  end

  test "respects manually set import_start_date" do
    custom_date = 1.week.ago
    @source.import_start_date = custom_date
    @source.save!

    assert_equal(custom_date.to_i, @source.import_start_date.to_i)
  end

  test "does not override existing import_start_date" do
    existing_date = 1.month.ago
    @source.import_start_date = existing_date
    @source.save!

    # Update the source without changing import_start_date
    @source.update!(name: "Updated Name")

    assert_equal(existing_date.to_i, @source.import_start_date.to_i)
  end
end
