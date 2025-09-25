# frozen_string_literal: true

class CalendarEventAudit < ApplicationRecord
  belongs_to :calendar_event
  enum :action, { created: "created", updated: "updated", deleted: "deleted" }
end
