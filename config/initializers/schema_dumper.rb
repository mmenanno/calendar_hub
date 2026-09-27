# frozen_string_literal: true

# RetentionJob runs `PRAGMA optimize`, which may ANALYZE and create SQLite's
# internal statistics tables. They aren't part of the app schema.
ActiveRecord::SchemaDumper.ignore_tables |= [/\Asqlite_stat\d\z/]
