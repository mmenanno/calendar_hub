# frozen_string_literal: true

module CredentialHelpers
  # Ciphertext encrypted with a key other than the current one, as left
  # behind when key_store.json is lost or replaced.
  def foreign_ciphertext(payload)
    key = SecureRandom.hex(CalendarHub::CredentialEncryption::KEY_BYTES)
    CalendarHub::CredentialEncryption.send(:build_encryptor, key).encrypt_and_sign(payload.to_json)
  end
end
