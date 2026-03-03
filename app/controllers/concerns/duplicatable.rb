# frozen_string_literal: true

module Duplicatable
  extend ActiveSupport::Concern

  private

  def duplicate_record(original, row_partial:, success_message_key:, locals: {})
    copy = original.dup
    copy.position = original.class.maximum(:position).to_i + 1
    copy.save!

    # Swap any reference to the original with the copy in caller-provided locals
    render_locals = locals.transform_values { |v| v.equal?(original) ? copy : v }

    streams = [
      turbo_stream.after(
        view_context.dom_id(original, :row),
        render_to_string(
          partial: row_partial,
          locals: { original.model_name.param_key.to_sym => copy }.merge(render_locals),
        ),
      ),
    ]

    message = t("#{success_message_key}.duplicated")
    turbo_success_response(streams, message: message, fallback_location: polymorphic_path(original.class))
  end
end
