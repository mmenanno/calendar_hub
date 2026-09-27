# frozen_string_literal: true

module TurboStreamable
  extend ActiveSupport::Concern

  private

  def toast_stream(message, variant: :info)
    turbo_stream.append(
      "toast-anchor",
      partial: "shared/toast",
      locals: { message: message, variant: variant },
    )
  end

  def turbo_success_response(streams = [], message:, fallback_location: nil, notice: nil)
    respond_to do |format|
      format.turbo_stream do
        all_streams = Array(streams) + [toast_stream(message, variant: :success)]
        render(turbo_stream: all_streams)
      end
      format.html do
        redirect_to(fallback_location || request.referer || root_path, notice: notice || message)
      end
    end
  end

  def turbo_error_response(message:, status: :unprocessable_entity, fallback_location: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        render(turbo_stream: toast_stream(message, variant: :error), status: status)
      end
      format.html do
        redirect_to(fallback_location || request.referer || root_path, alert: alert || message)
      end
    end
  end
end
