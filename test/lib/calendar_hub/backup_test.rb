# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module CalendarHub
  class BackupTest < ActiveSupport::TestCase
    setup do
      @tmpdir = Pathname.new(Dir.mktmpdir("calendar_hub_backup_test"))
      @backup_dir = @tmpdir.join("backups")
      @key_store_path = @tmpdir.join("key_store.json")
      @key_store_path.write('{"credential_key":{"value":"abc"}}')
    end

    teardown do
      FileUtils.rm_rf(@tmpdir)
    end

    test "snapshots every configured sqlite database with VACUUM INTO" do
      path = run_backup

      db_names = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).map { |c| File.basename(c.database) }

      assert_equal(db_names.sort, database_files(path).map { |f| f.basename.to_s }.sort)

      snapshot = SQLite3::Database.new(path.join(db_names.first).to_s, readonly: true)
      begin
        assert_equal("ok", snapshot.get_first_value("PRAGMA integrity_check"))
        assert_equal(CalendarSource.unscoped.count, snapshot.get_first_value("SELECT COUNT(*) FROM calendar_sources"))
      ensure
        snapshot.close
      end
    end

    test "copies the key store with owner-only permissions" do
      path = run_backup
      copied = path.join("key_store.json")

      assert_equal(@key_store_path.read, copied.read)
      assert_equal(0o600, copied.stat.mode & 0o777)
      assert_equal(0o600, database_files(path).first.stat.mode & 0o777)
    end

    test "skips the key store when it does not exist" do
      @key_store_path.delete

      refute_predicate(run_backup.join("key_store.json"), :exist?)
    end

    test "keeps only the newest snapshots" do
      times = (1..4).map { |i| Time.utc(2026, 1, i, 3, 0, 0) }
      times.each { |time| run_backup(now: time, keep: 2) }

      assert_equal(
        ["calendar_hub-20260103-030000", "calendar_hub-20260104-030000"],
        Backup.new(dir: @backup_dir, keep: 2, key_store_path: @key_store_path).snapshots.map { |s| s.basename.to_s },
      )
    end

    test "does not prune unrelated files in the backup directory" do
      @backup_dir.mkpath
      @backup_dir.join("notes.txt").write("keep me")

      run_backup(keep: 1)

      assert_predicate(@backup_dir.join("notes.txt"), :exist?)
    end

    test "cleans up the partial snapshot when a database copy fails" do
      Backup.any_instance.stubs(:snapshot_database).raises(SQLite3::Exception, "boom")

      assert_raises(SQLite3::Exception) { run_backup }
      assert_empty(@backup_dir.children)
    end

    test "reads directory and retention from the environment" do
      with_env(Backup::DIR_ENV_KEY => @backup_dir.to_s, Backup::KEEP_ENV_KEY => "3") do
        assert_equal(@backup_dir.to_s, Backup.default_dir.to_s)
        assert_equal(3, Backup.default_keep)
      end
    end

    test "defaults to storage/backups keeping 7 snapshots" do
      with_env(Backup::DIR_ENV_KEY => nil, Backup::KEEP_ENV_KEY => nil) do
        assert_equal(Rails.root.join("storage/backups"), Backup.default_dir)
        assert_equal(7, Backup.default_keep)
      end
    end

    test "rejects a retention below one" do
      assert_raises(ArgumentError) { Backup.new(dir: @backup_dir, keep: 0, key_store_path: @key_store_path) }
    end

    private

    def database_files(snapshot_path)
      snapshot_path.children.reject { |child| child.basename.to_s == "key_store.json" }
    end

    def run_backup(now: Time.utc(2026, 1, 1, 3, 0, 0), keep: 7)
      Backup.run(dir: @backup_dir, keep: keep, key_store_path: @key_store_path, now: now)
    end

    def with_env(vars)
      original = vars.keys.index_with { |key| ENV.fetch(key, nil) }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      original.each { |key, value| ENV[key] = value }
    end
  end
end
