# frozen_string_literal: true

require "test_helper"

class CalendarSourceUnarchiveTest < ActionDispatch::IntegrationTest
  test "unarchive turbo stream includes all expected elements" do
    archived_source = calendar_sources(:archived_source)

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    # Should contain turbo-stream actions for:
    # 1. Removing the source card from archived section
    assert_match(/turbo-stream.*action="remove".*target="#{Regexp.escape(dom_id(archived_source, :card))}"/, response.body)

    # 2. Prepending the source to active sources list
    assert_match(/turbo-stream.*action="prepend".*target="sources-list"/, response.body)

    # 3. Showing success toast
    assert_match(/turbo-stream.*action="append".*target="toast-anchor"/, response.body)
    assert_match(/Source unarchived/, response.body)

    # 4. Either removing archived section or replacing it (depending on remaining count)
    assert_match(/turbo-stream.*action="(remove|replace)".*target="archived-sources/, response.body)
  end

  test "unarchive last archived source removes entire archived section" do
    # Ensure we only have one archived source
    CalendarSource.unscoped.where.not(deleted_at: nil).where.not(id: calendar_sources(:archived_source).id).destroy_all

    archived_source = calendar_sources(:archived_source)

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    # Should remove the entire archived-sources section
    assert_match(/turbo-stream.*action="remove".*target="archived-sources"/, response.body)
  end

  test "unarchive with remaining archived sources updates archived section" do
    # Create another archived source to ensure section is updated, not removed
    another_archived = CalendarSource.create!(
      name: "Another Archived",
      ingestion_url: "https://example.com/another.ics",
      calendar_identifier: "another",
      active: false,
      deleted_at: 1.hour.ago,
    )

    archived_source = calendar_sources(:archived_source)

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    # Should replace the archived section (not remove it)
    assert_match(/turbo-stream.*action="replace".*target="archived-sources-section"/, response.body)
    refute_match(/turbo-stream.*action="remove".*target="archived-sources"/, response.body)

    # Cleanup
    another_archived.destroy!
  end

  test "unarchive updates source state correctly" do
    archived_source = calendar_sources(:archived_source)

    refute_predicate archived_source, :active?
    refute_nil archived_source.deleted_at

    patch unarchive_calendar_source_path(archived_source),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    archived_source.reload

    assert_predicate archived_source, :active?
    assert_nil archived_source.deleted_at
  end

  test "unarchive route exists and is accessible" do
    archived_source = calendar_sources(:archived_source)

    # Route should exist
    assert_recognizes(
      { controller: "calendar_sources", action: "unarchive", id: archived_source.id.to_s },
      { path: "/calendar_sources/#{archived_source.id}/unarchive", method: :patch },
    )

    # Should be accessible via path helper
    assert_equal "/calendar_sources/#{archived_source.id}/unarchive", unarchive_calendar_source_path(archived_source)
  end

  private

  def dom_id(record, prefix = nil)
    ActionView::RecordIdentifier.dom_id(record, prefix)
  end
end
