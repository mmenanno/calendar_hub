# frozen_string_literal: true

module WebMockHelpers
  def stub_ics_request(source, status: 200, body: nil, headers: {})
    body ||= file_fixture("provider.ics").read
    default_headers = {
      "Content-Type" => "text/calendar",
      "ETag" => '"test-etag"',
      "Last-Modified" => Time.current.httpdate,
    }

    stub_request(:get, source.ingestion_url)
      .to_return(status: status, body: body, headers: default_headers.merge(headers))
  end

  def stub_ics_request_with_auth(source, username: "testuser", password: "testpass", **options)
    stub_ics_request(source, **options)
      .with(headers: { "Authorization" => basic_auth_header(username, password) })
  end

  def stub_ics_304_not_modified(source)
    stub_request(:get, source.ingestion_url)
      .to_return(status: 304, body: "")
  end

  def stub_ics_error(source, status: 500, message: "Internal Server Error")
    stub_request(:get, source.ingestion_url)
      .to_return(status: status, body: message)
  end

  def stub_caldav_discovery(base_url: "https://caldav.example.test")
    stub_request(:propfind, "#{base_url}/.well-known/caldav")
      .to_return(status: 301, headers: { "Location" => "#{base_url}/principals/user/" })

    stub_request(:propfind, "#{base_url}/principals/user/")
      .to_return(status: 207, body: caldav_principal_response(base_url))

    stub_request(:propfind, "#{base_url}/calendars/user/")
      .to_return(status: 207, body: caldav_calendars_response(base_url))
  end

  def stub_caldav_upsert(base_url: "https://caldav.example.test", calendar: "Work", uid: "test-uid", status: 201)
    stub_request(:put, "#{base_url}/calendars/user/#{calendar}/#{uid}.ics")
      .to_return(status: status)
  end

  def stub_caldav_delete(base_url: "https://caldav.example.test", calendar: "Work", uid: "test-uid", status: 204)
    stub_request(:delete, "#{base_url}/calendars/user/#{calendar}/#{uid}.ics")
      .to_return(status: status)
  end

  private

  def basic_auth_header(username, password)
    "Basic #{Base64.strict_encode64("#{username}:#{password}")}"
  end

  def caldav_principal_response(base_url)
    <<~XML
      <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
        <d:response>
          <d:propstat>
            <d:prop>
              <cal:calendar-home-set>
                <d:href>#{base_url}/calendars/user/</d:href>
              </cal:calendar-home-set>
            </d:prop>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
  end

  def caldav_calendars_response(base_url)
    <<~XML
      <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
        <d:response>
          <d:href>#{base_url}/calendars/user/Work/</d:href>
          <d:propstat>
            <d:prop>
              <d:displayname>Work</d:displayname>
              <d:resourcetype>
                <d:collection/>
                <cal:calendar/>
              </d:resourcetype>
            </d:prop>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
  end
end
