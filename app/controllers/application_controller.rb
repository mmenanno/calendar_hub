# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include TurboStreamable

  # Application-wide error handling for database timeout and lock errors
  rescue_from ActiveRecord::StatementTimeout, SQLite3::BusyException do |exception|
    Rails.logger.error("[ApplicationController] Database timeout/lock error: #{exception.message}")

    respond_to do |format|
      format.turbo_stream do
        render(
          turbo_stream: toast_stream(
            t("flashes.database_busy", default: "Database is busy. Please try again in a moment."),
            variant: :error,
          ),
          status: :service_unavailable,
        )
      end
      format.html do
        redirect_to(
          request.referer || root_path,
          alert: t("flashes.database_busy", default: "Database is busy. Please try again in a moment."),
        )
      end
      format.json do
        render(
          json: { error: t("flashes.database_busy", default: "Database is busy. Please try again in a moment.") },
          status: :service_unavailable,
        )
      end
    end
  end
end
