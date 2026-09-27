# frozen_string_literal: true

require "test_helper"

class RulesTransfersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def rules_document(filter_rules: nil, event_mappings: nil)
    doc = { "format" => "calendar_hub.rules", "version" => 1 }
    doc["filter_rules"] = filter_rules if filter_rules
    doc["event_mappings"] = event_mappings if event_mappings
    doc.to_json
  end

  def filter_row(**attrs)
    { "source" => nil, "field_name" => "title", "match_type" => "contains", "pattern" => "Imported", "case_sensitive" => false, "active" => true }.merge(attrs.stringify_keys)
  end

  def upload(json)
    Rack::Test::UploadedFile.new(StringIO.new(json), "application/json", original_filename: "rules.json")
  end

  def token_for(json)
    CalendarHub::RulesTransfer::Token.generate(json)
  end

  # -- Export -----------------------------------------------------------------

  test "export downloads all rules as a dated JSON attachment" do
    travel_to(Time.utc(2026, 9, 26, 12)) do
      get export_rules_url
    end

    assert_response(:success)
    assert_equal("application/json", response.media_type)
    assert_match(/attachment; filename="calendar-hub-rules-20260926.json"/, response.headers["Content-Disposition"])

    body = response.parsed_body

    assert_equal("calendar_hub.rules", body["format"])
    assert_equal(EventMapping.count, body["event_mappings"].size)
    assert_equal(FilterRule.count, body["filter_rules"].size)
  end

  test "export can be limited to one kind" do
    get export_rules_url(only: "filter_rules")

    body = response.parsed_body

    refute(body.key?("event_mappings"))
    assert(body.key?("filter_rules"))
  end

  test "export ignores unknown kinds and exports everything" do
    get export_rules_url(only: "calendar_sources")

    body = response.parsed_body

    assert(body.key?("event_mappings"))
    assert(body.key?("filter_rules"))
  end

  # -- New --------------------------------------------------------------------

  test "new renders the upload form" do
    get new_rules_import_url(kind: "filter_rules")

    assert_response(:success)
    assert_select("form[action=?][enctype=?]", preview_rules_import_path, "multipart/form-data")
    assert_select("input[type=file][name=file]")
    assert_select("textarea[name=json]")
  end

  test "new renders inside the modal frame for turbo frame requests" do
    get new_rules_import_url(kind: "event_mappings"), headers: { "Turbo-Frame" => "modal" }

    assert_response(:success)
    assert_select("turbo-frame#modal .modal-card")
  end

  # -- Preview ----------------------------------------------------------------

  test "preview from an uploaded file shows counts without changing anything" do
    json = rules_document(filter_rules: [filter_row, filter_row(pattern: "Meeting"), filter_row(match_type: "nope")])

    assert_no_difference("FilterRule.count") do
      post preview_rules_import_url, params: { file: upload(json), kind: "filter_rules" }
    end

    assert_response(:success)
    assert_select("[data-count=add-filter_rules]", "1")
    assert_select("[data-count=duplicate-filter_rules]", "1")
    assert_select("[data-count=invalid-filter_rules]", "1")
    assert_select("input[type=hidden][name=token]")
  end

  test "preview accepts pasted JSON" do
    post preview_rules_import_url, params: { json: rules_document(filter_rules: [filter_row]) }

    assert_response(:success)
    assert_select("[data-count=add-filter_rules]", "1")
  end

  test "preview lists unknown sources with a strategy select" do
    post preview_rules_import_url, params: { json: rules_document(filter_rules: [filter_row(source: "Elsewhere")]) }

    assert_response(:success)
    assert_includes(response.body, "Elsewhere")
    assert_select("select[name=unknown_sources]")
  end

  test "preview can be refreshed from a token with different options" do
    json = rules_document(filter_rules: [filter_row(source: "Elsewhere")])

    post preview_rules_import_url, params: { token: token_for(json), unknown_sources: "global" }

    assert_response(:success)
    assert_select("[data-count=add-filter_rules]", "1")
  end

  test "preview re-renders the form with errors for an invalid document" do
    post preview_rules_import_url, params: { json: "{nope" }

    assert_response(:unprocessable_content)
    assert_includes(response.body, "not valid JSON")
    assert_select("input[type=file][name=file]")
  end

  test "preview requires some input" do
    post preview_rules_import_url

    assert_response(:unprocessable_content)
    assert_includes(response.body, I18n.t("flashes.rules_transfer.no_input"))
  end

  test "preview rejects oversized uploads" do
    json = rules_document(filter_rules: []) + (" " * CalendarHub::RulesTransfer::Importer::MAX_BYTES)

    post preview_rules_import_url, params: { file: upload(json) }

    assert_response(:unprocessable_content)
    assert_includes(response.body, "too large")
  end

  test "preview rejects a tampered token" do
    post preview_rules_import_url, params: { token: "tampered" }

    assert_response(:unprocessable_content)
    assert_includes(response.body, I18n.t("flashes.rules_transfer.token_invalid"))
  end

  test "preview falls back to safe defaults for unknown option values" do
    post preview_rules_import_url, params: { json: rules_document(filter_rules: [filter_row]), mode: "wipe", unknown_sources: "guess" }

    assert_response(:success)
    assert_select("input[type=radio][name=mode][value=append][checked]")
  end

  # -- Apply ------------------------------------------------------------------

  test "apply imports from the token and redirects back with a notice" do
    json = rules_document(filter_rules: [filter_row, filter_row(pattern: "Second")])

    clear_enqueued_jobs
    assert_difference("FilterRule.count", 2) do
      post apply_rules_import_url, params: { token: token_for(json), kind: "filter_rules" }
    end

    assert_redirected_to(filter_rules_path)
    assert_equal(I18n.t("flashes.rules_transfer.imported", count: 2), flash[:notice])
    assert_enqueued_jobs(CalendarSource.active.count, only: SyncFilterRulesJob)
  end

  test "apply redirects to mappings when importing from the mappings page" do
    json = rules_document(event_mappings: [{ "match_type" => "contains", "pattern" => "New", "replacement" => "Renamed" }])

    post apply_rules_import_url, params: { token: token_for(json), kind: "event_mappings" }

    assert_redirected_to(event_mappings_path)
  end

  test "apply ignores any rule data posted alongside the token" do
    json = rules_document(filter_rules: [filter_row(pattern: "FromToken")])

    post apply_rules_import_url, params: {
      token: token_for(json),
      json: rules_document(filter_rules: [filter_row(pattern: "Injected")]),
      filter_rules: [filter_row(pattern: "Injected2")],
    }

    assert(FilterRule.exists?(pattern: "FromToken"))
    refute(FilterRule.exists?(pattern: "Injected"))
    refute(FilterRule.exists?(pattern: "Injected2"))
  end

  test "apply rejects a tampered token" do
    token = token_for(rules_document(filter_rules: [filter_row]))
    tampered = token.sub(/.\z/) { |char| char == "A" ? "B" : "A" }

    assert_no_difference("FilterRule.count") do
      post apply_rules_import_url, params: { token: tampered }
    end

    assert_response(:unprocessable_content)
    assert_includes(response.body, I18n.t("flashes.rules_transfer.token_invalid"))
  end

  test "apply rejects a token signed for a different purpose" do
    forged = Rails.application.message_verifier("other").generate(rules_document(filter_rules: [filter_row]))

    assert_no_difference("FilterRule.count") do
      post apply_rules_import_url, params: { token: forged }
    end

    assert_response(:unprocessable_content)
  end

  test "apply rejects an expired token" do
    token = token_for(rules_document(filter_rules: [filter_row]))

    travel(CalendarHub::RulesTransfer::Token::TTL + 1.minute) do
      assert_no_difference("FilterRule.count") do
        post apply_rules_import_url, params: { token: token }
      end
    end

    assert_response(:unprocessable_content)
  end

  test "apply in replace mode requires explicit confirmation" do
    json = rules_document(filter_rules: [filter_row(pattern: "Only")])

    assert_no_difference("FilterRule.count") do
      post apply_rules_import_url, params: { token: token_for(json), mode: "replace" }
    end

    assert_response(:unprocessable_content)
    assert_includes(response.body, I18n.t("flashes.rules_transfer.confirm_replace_required"))
  end

  test "apply in replace mode with confirmation replaces existing rules" do
    json = rules_document(filter_rules: [filter_row(pattern: "Only")])

    post apply_rules_import_url, params: { token: token_for(json), mode: "replace", confirm_replace: "1", kind: "filter_rules" }

    assert_redirected_to(filter_rules_path)
    assert_equal(["Only"], FilterRule.pluck(:pattern))
  end

  test "apply maps unknown sources to global when requested" do
    json = rules_document(filter_rules: [filter_row(source: "Elsewhere")])

    post apply_rules_import_url, params: { token: token_for(json), unknown_sources: "global" }

    assert_nil(FilterRule.find_by!(pattern: "Imported").calendar_source_id)
  end

  test "apply reports when nothing was imported" do
    json = rules_document(filter_rules: [filter_row(pattern: "Meeting")])

    post apply_rules_import_url, params: { token: token_for(json), kind: "filter_rules" }

    assert_redirected_to(filter_rules_path)
    assert_equal(I18n.t("flashes.rules_transfer.nothing_imported"), flash[:notice])
  end

  # -- Page integration -------------------------------------------------------

  test "mappings and filters pages link to export and import" do
    get event_mappings_url

    assert_select("a[href=?]", export_rules_path(only: "event_mappings"))
    assert_select("a[href=?]", new_rules_import_path(kind: "event_mappings"))

    get filter_rules_url

    assert_select("a[href=?]", export_rules_path(only: "filter_rules"))
    assert_select("a[href=?]", new_rules_import_path(kind: "filter_rules"))
  end
end
