# frozen_string_literal: true

module MochaHelpers
  def mock_ingestion_adapter(source, events: [])
    adapter = mock("ingestion_adapter")
    adapter.expects(:fetch_events).returns(events).at_least_once
    source.stubs(:ingestion_adapter).returns(adapter)

    CalendarHub::Ingestion::GenericICSAdapter.stubs(:new).with(source).returns(adapter)
    adapter
  end

  def mock_apple_client(expectations = {})
    client = mock("apple_client")
    expectations.each do |method, return_value|
      client.stubs(method).returns(return_value)
    end
    client
  end

  def stub_routing_error(method_name, error_message = "Routing error")
    Rails.application.routes.url_helpers.stubs(method_name).raises(StandardError, error_message)
  end

  def stub_logger_expectation(level, message_pattern)
    Rails.logger.expects(level).with(regexp_matches(message_pattern))
  end
end
