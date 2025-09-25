# frozen_string_literal: true

# This migration is intentionally empty.
# We squashed all historical migrations. New databases should be created with:
#   bin/rails db:drop db:create db:schema:load
# Using schema.rb ensures the database matches the current application schema.
class InitialSchemaBaseline < ActiveRecord::Migration[8.0]
  def change
  end
end
