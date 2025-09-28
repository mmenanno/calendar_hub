# frozen_string_literal: true

module CalendarHub
  module Shared
    class NullObserver
      def start(total: 0); end
      def upsert_success(event); end
      def upsert_error(event, error); end
      def delete_success(event); end
      def delete_error(event, error); end
      def finish(status: :success, message: nil); end
    end
  end
end
