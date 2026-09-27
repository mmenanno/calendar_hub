# frozen_string_literal: true

require "test_helper"

module CalendarHub
  module RulesTransfer
    class TokenTest < ActiveSupport::TestCase
      test "round trips a document" do
        raw = { "format" => "calendar_hub.rules", "pattern" => "é ✓" }.to_json

        assert_equal(raw, Token.read(Token.generate(raw)))
      end

      test "does not expose the document in plain text" do
        token = Token.generate({ "pattern" => "SecretPattern" }.to_json)

        refute_includes(token, "SecretPattern")
      end

      test "returns nil for tampered tokens" do
        token = Token.generate("{}")
        tampered = token.dup
        tampered[5] = tampered[5] == "A" ? "B" : "A"

        assert_nil(Token.read(tampered))
      end

      test "returns nil for blank or garbage tokens" do
        assert_nil(Token.read(nil))
        assert_nil(Token.read(""))
        assert_nil(Token.read("garbage"))
      end

      test "expires" do
        token = Token.generate("{}")

        travel(Token::TTL + 1.minute) do
          assert_nil(Token.read(token))
        end
      end
    end
  end
end
