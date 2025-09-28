# frozen_string_literal: true

module Toggleable
  extend ActiveSupport::Concern

  private

  def toggle_field(record, field, success_message_key, row_partial:, locals: {})
    record.update!(field => !record.public_send(field))

    streams = [
      turbo_stream.replace(
        view_context.dom_id(record, :row),
        partial: row_partial,
        locals: { record.model_name.param_key.to_sym => record }.merge(locals),
      ),
    ]

    message = t(record.public_send(field) ? "#{success_message_key}.enabled" : "#{success_message_key}.disabled")
    turbo_success_response(streams, message: message, fallback_location: polymorphic_path(record.class))
  end
end
