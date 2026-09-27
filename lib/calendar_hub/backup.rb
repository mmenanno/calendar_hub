# frozen_string_literal: true

require "fileutils"
require "sqlite3"

module CalendarHub
  # Writes a consistent snapshot of every SQLite database configured for the
  # current environment (via VACUUM INTO, safe while the app is running) plus
  # the key store into a timestamped directory, then prunes old snapshots.
  #
  #   CalendarHub::Backup.run # => #<Pathname storage/backups/calendar_hub-20260101-030000>
  #
  # Configure with CALENDAR_HUB_BACKUP_DIR (default storage/backups) and
  # CALENDAR_HUB_BACKUP_KEEP (default 7 snapshots).
  class Backup
    DIR_ENV_KEY = "CALENDAR_HUB_BACKUP_DIR"
    KEEP_ENV_KEY = "CALENDAR_HUB_BACKUP_KEEP"
    DEFAULT_KEEP = 7
    PREFIX = "calendar_hub-"
    SNAPSHOT_PATTERN = /\A#{PREFIX}\d{8}-\d{6}\z/
    BUSY_TIMEOUT_MS = 30_000

    class << self
      def run(**)
        new(**).run
      end

      def default_dir
        ENV[DIR_ENV_KEY].presence || Rails.root.join("storage/backups")
      end

      def default_keep
        Integer(ENV.fetch(KEEP_ENV_KEY, DEFAULT_KEEP))
      end
    end

    attr_reader :dir, :keep

    def initialize(dir: self.class.default_dir, keep: self.class.default_keep, env: Rails.env,
      key_store_path: CalendarHub::KeyStore.instance.store_path, now: Time.now.utc)
      raise ArgumentError, "keep must be at least 1" if keep < 1

      @dir = Pathname.new(dir).expand_path
      @keep = keep
      @env = env
      @key_store_path = Pathname.new(key_store_path)
      @now = now
    end

    def run
      target = dir.join("#{PREFIX}#{@now.strftime("%Y%m%d-%H%M%S")}")
      partial = dir.join(".#{target.basename}.partial")
      FileUtils.rm_rf(partial)
      FileUtils.mkdir_p(partial, mode: 0o700)

      database_paths.each { |path| snapshot_database(path, partial.join(path.basename)) }
      copy_key_store(partial)

      FileUtils.rm_rf(target)
      File.rename(partial, target)
      prune
      target
    ensure
      FileUtils.rm_rf(partial) if partial&.exist?
    end

    # Snapshot directories, oldest first.
    def snapshots
      return [] unless dir.directory?

      dir.children.select { |child| child.directory? && SNAPSHOT_PATTERN.match?(child.basename.to_s) }.sort
    end

    private

    def database_paths
      ActiveRecord::Base.configurations.configs_for(env_name: @env).filter_map do |db_config|
        next unless db_config.adapter.to_s.start_with?("sqlite")
        next if db_config.database.blank? || db_config.database.start_with?(":memory:", "file::memory:")

        path = Pathname.new(File.expand_path(db_config.database, Rails.root))
        path if path.exist?
      end.uniq
    end

    def snapshot_database(source, destination)
      db = SQLite3::Database.new(source.to_s)
      db.busy_timeout = BUSY_TIMEOUT_MS
      db.execute("VACUUM INTO ?", [destination.to_s])
      destination.chmod(0o600)
    ensure
      db&.close
    end

    # Also copies key_store.json.bak (the store as it was before the last key
    # rotation), in case credentials encrypted with the previous key remain.
    def copy_key_store(destination_dir)
      { @key_store_path => "key_store.json", previous_key_store_path => "key_store.json.bak" }.each do |source, name|
        next unless source.exist?

        destination = destination_dir.join(name)
        FileUtils.cp(source, destination)
        destination.chmod(0o600)
      end
    end

    def previous_key_store_path
      Pathname.new("#{@key_store_path}#{CalendarHub::KeyStore::BACKUP_SUFFIX}")
    end

    def prune
      snapshots[0...-keep].each { |old| FileUtils.rm_rf(old) }
    end
  end
end
