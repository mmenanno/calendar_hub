# frozen_string_literal: true

desc("Tools for FlareSolverr")

tool :check do
  desc("Health check FlareSolverr and print cookie TTLs for configured warm_urls")
  long_desc("Fetches each warm URL via FlareSolverr, writes cookies to the store, and prints summary")

  def run
    require_relative "../config/environment"

    configuration = Rails.configuration.flaresolverr
    if configuration&.url.blank?
      puts("FlareSolverr URL not configured")
      return
    end

    puts("Endpoint: #{configuration.url}")
    warm_urls = Array(configuration.warm_urls)
    client = FlaresolverrClient.new
    store = FlaresolverrCookieStore.new

    warm_urls.each do |url|
      print("Fetching #{url} ... ")
      result = client.get_html(url)
      host = URI.parse(url).host
      header = store.write_from_cookies(host, result[:cookies])
      entry = Rails.cache.send(:read_entry, "flaresolverr:cookies:#{host}")
      ttl = entry&.expires_at
      puts("ok (cookies=#{header&.split(";")&.size || 0}, ttl=#{ttl})")
    rescue => error
      puts("failed: #{error.class} #{error.message}")
    end
  end
end
