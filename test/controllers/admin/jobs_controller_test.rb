# frozen_string_literal: true

require "test_helper"

module Admin
  class JobsControllerTest < ActionDispatch::IntegrationTest
    test "clear_metrics empties cache and redirects" do
      Rails.cache.write("calendar_hub:last_sync_metrics", [{ source_id: 1, fetched: 2, upserts: 2, deletes: 0, canceled: 0, duration_ms: 10, at: Time.current }])
      post clear_metrics_admin_jobs_path

      assert_redirected_to admin_jobs_path
      assert_empty Rails.cache.read("calendar_hub:last_sync_metrics") || []
    end
  end
end
