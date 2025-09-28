# frozen_string_literal: true

module CalendarHub
  class UrlOptions
    # Returns a hash suitable for url helpers: { host:, protocol:, port: optional }
    class << self
      def for_links
        settings = AppSetting.instance

        # Choose host with precedence: settings -> default_url_options -> ENV
        host = settings.try(:app_host).presence || Rails.application.routes.default_url_options[:host] || ENV.fetch("APP_HOST", "localhost")
        protocol = settings.try(:app_protocol).presence || ENV.fetch("APP_PROTOCOL", "http")
        port = settings.try(:app_port).presence

        # Extract port if the host already includes one (e.g., "localhost:3000")
        host, host_port = split_host_port(host)
        port ||= ENV["APP_PORT"].presence || host_port

        opts = { host: host, protocol: protocol }
        port_i = port.to_i if port
        # Always include the port when explicitly provided (fixes localhost links in Apple apps)
        opts[:port] = port_i if port_i && port_i > 0
        opts
      end

      def split_host_port(host)
        if host&.match?(/:\d+$/)
          [host.sub(/:\d+$/, ""), host.split(":").last]
        else
          [host, nil]
        end
      end
      private :split_host_port
    end
  end
end
