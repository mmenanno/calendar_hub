# frozen_string_literal: true

module EnvHelpers
  # Sets ENV vars for the duration of the block (nil unsets) and restores them.
  def with_env(values)
    originals = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| ENV[key] = value }
  end
end
