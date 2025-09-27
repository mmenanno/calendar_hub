# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_26_160000) do
  create_table "app_settings", force: :cascade do |t|
    t.string "default_time_zone", default: "UTC", null: false
    t.string "default_calendar_identifier"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_host"
    t.string "app_protocol", default: "http", null: false
    t.integer "app_port"
    t.string "apple_username"
    t.string "apple_app_password"
    t.integer "default_sync_frequency_minutes", default: 60, null: false
    t.text "apple_credentials_ciphertext"
  end

  create_table "calendar_event_audits", force: :cascade do |t|
    t.integer "calendar_event_id", null: false
    t.string "action", null: false
    t.json "changes_from", default: {}
    t.json "changes_to", default: {}
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_event_id", "occurred_at"], name: "idx_on_calendar_event_id_occurred_at_49966bf71e"
    t.index ["calendar_event_id"], name: "index_calendar_event_audits_on_calendar_event_id"
  end

  create_table "calendar_events", force: :cascade do |t|
    t.integer "calendar_source_id", null: false
    t.string "external_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "location"
    t.string "time_zone", default: "UTC", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "status", default: "confirmed", null: false
    t.datetime "source_updated_at"
    t.datetime "synced_at"
    t.string "fingerprint"
    t.json "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "sync_exempt", default: false, null: false
    t.boolean "all_day", default: false, null: false
    t.index ["all_day"], name: "index_calendar_events_on_all_day"
    t.index ["calendar_source_id", "external_id"], name: "index_calendar_events_on_calendar_source_id_and_external_id", unique: true
    t.index ["calendar_source_id", "starts_at"], name: "idx_events_source_starts"
    t.index ["calendar_source_id"], name: "index_calendar_events_on_calendar_source_id"
    t.index ["starts_at"], name: "index_calendar_events_on_starts_at"
    t.index ["status"], name: "index_calendar_events_on_status"
    t.index ["sync_exempt"], name: "index_calendar_events_on_sync_exempt"
  end

  create_table "calendar_sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "ingestion_url"
    t.string "calendar_identifier"
    t.string "sync_token"
    t.datetime "last_synced_at"
    t.json "settings", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "credentials"
    t.integer "sync_window_start_hour"
    t.integer "sync_window_end_hour"
    t.datetime "deleted_at"
    t.integer "sync_frequency_minutes"
    t.boolean "auto_sync_enabled", default: true, null: false
    t.string "ics_feed_etag"
    t.string "ics_feed_last_modified"
    t.string "last_change_hash"
    t.datetime "import_start_date"
    t.index ["active"], name: "index_calendar_sources_on_active"
    t.index ["auto_sync_enabled"], name: "index_calendar_sources_on_auto_sync_enabled"
    t.index ["calendar_identifier"], name: "index_calendar_sources_on_calendar_identifier"
    t.index ["deleted_at"], name: "index_calendar_sources_on_deleted_at"
    t.index ["import_start_date"], name: "index_calendar_sources_on_import_start_date"
    t.index ["sync_frequency_minutes"], name: "index_calendar_sources_on_sync_frequency_minutes"
  end

  create_table "event_mappings", force: :cascade do |t|
    t.integer "calendar_source_id"
    t.string "match_type", default: "contains", null: false
    t.string "pattern", null: false
    t.string "replacement", null: false
    t.boolean "case_sensitive", default: false, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_source_id", "active", "position"], name: "idx_on_calendar_source_id_active_position_f8d680a321"
    t.index ["calendar_source_id"], name: "index_event_mappings_on_calendar_source_id"
  end

  create_table "filter_rules", force: :cascade do |t|
    t.integer "calendar_source_id"
    t.string "match_type", default: "contains", null: false
    t.string "pattern", null: false
    t.string "field_name", default: "title", null: false
    t.boolean "case_sensitive", default: false, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_source_id", "active", "position"], name: "idx_filter_rules_source_active_position"
    t.index ["calendar_source_id"], name: "index_filter_rules_on_calendar_source_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.binary "payload", limit: 536870912, null: false
    t.datetime "created_at", null: false
    t.integer "channel_hash", limit: 8, null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sync_attempts", force: :cascade do |t|
    t.integer "calendar_source_id", null: false
    t.string "status", default: "queued", null: false
    t.integer "total_events", default: 0, null: false
    t.integer "upserts", default: 0, null: false
    t.integer "deletes", default: 0, null: false
    t.integer "errors_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_source_id"], name: "index_sync_attempts_on_calendar_source_id"
  end

  create_table "sync_event_results", force: :cascade do |t|
    t.integer "sync_attempt_id", null: false
    t.integer "calendar_event_id"
    t.string "external_id", null: false
    t.string "action", null: false
    t.boolean "success", default: true, null: false
    t.text "error_message"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_event_id"], name: "index_sync_event_results_on_calendar_event_id"
    t.index ["sync_attempt_id", "external_id"], name: "index_sync_event_results_on_sync_attempt_id_and_external_id"
    t.index ["sync_attempt_id"], name: "index_sync_event_results_on_sync_attempt_id"
  end

  add_foreign_key "calendar_event_audits", "calendar_events"
  add_foreign_key "calendar_events", "calendar_sources"
  add_foreign_key "event_mappings", "calendar_sources"
  add_foreign_key "filter_rules", "calendar_sources"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "sync_attempts", "calendar_sources"
  add_foreign_key "sync_event_results", "calendar_events"
  add_foreign_key "sync_event_results", "sync_attempts"
end
