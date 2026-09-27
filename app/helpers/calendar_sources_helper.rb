# frozen_string_literal: true

module CalendarSourcesHelper
  # Calendar icon used in the Sources page headers
  def sources_icon
    content_tag(
      :svg,
      content_tag(:path, "", "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "1.5", d: "M8 7V3m8 4V3m-9 8h10m-11 8h12a2 2 0 002-2v-8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"),
      xmlns: "http://www.w3.org/2000/svg",
      class: "h-6 w-6",
      fill: "none",
      viewBox: "0 0 24 24",
      stroke: "currentColor",
      "aria-hidden": "true",
    )
  end
end
