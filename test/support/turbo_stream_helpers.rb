# frozen_string_literal: true

module TurboStreamHelpers
  def assert_turbo_stream_action(action, target = nil)
    assert_match("turbo-stream", response.body)
    assert_match(action, response.body)
    assert_match(target, response.body) if target
  end

  def assert_turbo_stream_replace(target)
    assert_turbo_stream_action("replace", target)
  end

  def assert_turbo_stream_update(target)
    assert_turbo_stream_action("update", target)
  end

  def assert_turbo_stream_remove(target)
    assert_turbo_stream_action("remove", target)
  end

  def assert_turbo_stream_prepend(target)
    assert_turbo_stream_action("prepend", target)
  end
end
