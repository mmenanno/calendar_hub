# frozen_string_literal: true

tool :dump do
  require "./lib/stash_box/api"

  desc "Dump StashDB GraphQL Schema"
  def run
    GraphQL::Client.dump_schema(StashBox::API::HTTP, StashBox::API::SCHEMA_FILE)
  end
end
