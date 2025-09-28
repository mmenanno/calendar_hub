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

  def turbo_update_response(record, partial:, locals: {}, message:, fallback_location: nil)
    if record.persisted? && record.errors.empty?
      streams = [
        turbo_stream.replace(view_context.dom_id(record, :row), partial: partial, locals: locals),
        turbo_stream.update("modal", ""),
      ]
      turbo_success_response(streams, message: message, fallback_location: fallback_location)
    else
      error_message = record.errors.full_messages.to_sentence.presence || message
      turbo_error_response(message: error_message, fallback_location: fallback_location)
    end
  end
end
