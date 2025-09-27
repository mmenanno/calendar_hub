# frozen_string_literal: true

class AddCredentialCiphertextToAppSettings < ActiveRecord::Migration[8.0]
  def change
    add_column(:app_settings, :apple_credentials_ciphertext, :text)
  end
end
