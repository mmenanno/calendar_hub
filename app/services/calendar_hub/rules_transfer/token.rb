# frozen_string_literal: true

require "zlib"

module CalendarHub
  module RulesTransfer
    # Carries an uploaded rules document from the preview step to the apply
    # step without trusting the client: the document is compressed, encrypted
    # and signed, and expires after TTL. The apply step re-validates it.
    module Token
      extend self

      PURPOSE = "calendar_hub.rules_import"
      TTL = 30.minutes

      def generate(raw)
        payload = Base64.strict_encode64(Zlib::Deflate.deflate(raw.to_s))
        encryptor.encrypt_and_sign(payload, expires_in: TTL, purpose: PURPOSE)
      end

      def read(token)
        return if token.blank?

        payload = encryptor.decrypt_and_verify(token.to_s, purpose: PURPOSE)
        return unless payload.is_a?(String)

        Zlib::Inflate.inflate(Base64.strict_decode64(payload)).force_encoding(Encoding::UTF_8)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature, Zlib::Error, ArgumentError
        nil
      end

      private

      def encryptor
        key = Rails.application.key_generator.generate_key(PURPOSE, ActiveSupport::MessageEncryptor.key_len)
        ActiveSupport::MessageEncryptor.new(key)
      end
    end
  end
end
