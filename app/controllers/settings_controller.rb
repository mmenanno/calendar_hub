# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :set_settings
  before_action :set_unreadable_credentials, only: [:show, :edit, :update]

  def show; end
  def edit; end

  def update
    attrs = settings_params
    # Trim trailing/leading spaces on all string fields
    attrs.each { |k, v| attrs[k] = v.strip if v.is_a?(String) }
    # Preserve existing Apple password when left blank
    attrs[:apple_app_password] = @settings.apple_app_password if attrs.key?(:apple_app_password) && attrs[:apple_app_password].blank?

    if @settings.update(attrs)
      respond_to do |format|
        format.turbo_stream do
          render(turbo_stream: turbo_stream.append(
            "toast-anchor",
            partial: "shared/toast",
            locals: { message: t("flashes.settings.saved"), variant: :success },
          ))
        end
        format.html { redirect_to(edit_settings_path, notice: t("flashes.settings.saved")) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render(:edit, status: :unprocessable_content)
        end
        format.html do
          flash.now[:alert] = t("flashes.settings.review_errors")
          render(:edit, status: :unprocessable_content)
        end
      end
    end
  end

  def reset
    @settings.clear_apple_credentials
    @settings.update!(
      default_time_zone: "UTC",
      default_calendar_identifier: nil,
      app_host: nil,
      app_protocol: "http",
      app_port: nil,
    )
    respond_to do |format|
      msg = t("flashes.settings.reset")
      format.turbo_stream do
        render(turbo_stream: [
          turbo_stream.replace("settings-form", partial: "settings/form", locals: { settings: @settings }),
          toast_stream(msg, variant: :success),
        ])
      end
      format.html { redirect_to(edit_settings_path, notice: msg) }
    end
  end

  def rotate_credential_key
    AppSetting.instance.rotate_credentials_key!

    respond_to do |format|
      msg = t("flashes.settings.key_rotated")
      format.turbo_stream do
        render(turbo_stream: turbo_stream.append(
          "toast-anchor",
          partial: "shared/toast",
          locals: { message: msg, variant: :success },
        ))
      end
      format.html { redirect_to(edit_settings_path, notice: msg) }
    end
  rescue CalendarHub::CredentialEncryption::KeyRotationError => exception
    respond_to do |format|
      error = t("flashes.settings.key_rotation_failed", error: exception.message)
      format.turbo_stream do
        render(turbo_stream: turbo_stream.append(
          "toast-anchor",
          partial: "shared/toast",
          locals: { message: error, variant: :error },
        ))
      end
      format.html { redirect_to(edit_settings_path, alert: error) }
    end
  end

  def test_calendar
    client = if params[:apple_username].present? || params[:apple_app_password].present?
      # Blank fields fall back to the saved values so users can test a new
      # username (or re-test) without re-typing the stored app password.
      AppleCalendar::Client.new(credentials: {
        username: params[:apple_username].presence || @settings.apple_username,
        app_specific_password: params[:apple_app_password].presence || @settings.apple_app_password,
      })
    else
      AppleCalendar::Client.new
    end
    identifier = @settings.default_calendar_identifier.presence
    if identifier.present?
      url = client.send(:discover_calendar_url, identifier)
      message = t("flashes.settings.apple_test_found", path: URI.parse(url).request_uri)
    else
      # Fallback: just follow well-known and fetch home set
      principal_url = client.send(:follow_well_known)
      _home = client.send(:fetch_calendar_home_set, principal_url)
      message = t("flashes.settings.apple_test_ok")
    end

    respond_to do |format|
      format.turbo_stream { render(turbo_stream: turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: message, variant: :success })) }
      format.html { redirect_to(edit_settings_path, notice: message) }
    end
  rescue StandardError => exception
    error = t("flashes.settings.apple_test_failed", error: exception.message)
    respond_to do |format|
      format.turbo_stream { render(turbo_stream: turbo_stream.append("toast-anchor", partial: "shared/toast", locals: { message: error, variant: :error })) }
      format.html { redirect_to(edit_settings_path, alert: error) }
    end
  end

  private

  def set_settings
    @settings = AppSetting.instance
  end

  # Credentials the current key can't decrypt (lost or replaced key store).
  def set_unreadable_credentials
    @apple_credentials_unreadable = @settings.credentials_unreadable?
    @unreadable_credential_sources = CalendarSource.unscoped.where.not(credentials: [nil, ""]).order(:name).select(&:credentials_unreadable?)
  end

  def settings_params
    params.expect(app_setting: [:default_time_zone, :default_calendar_identifier, :notes, :app_host, :app_protocol, :app_port, :apple_username, :apple_app_password, :default_sync_frequency_minutes])
  end
end
