# frozen_string_literal: true

module Reorderable
  extend ActiveSupport::Concern

  private

  def reorder_records(model_class)
    ids = Array(params[:order]).map(&:to_i)
    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, idx|
        if (record = model_class.find_by(id: id))
          record.update!(position: idx)
        end
      end
    end
    head(:ok)
  end
end
