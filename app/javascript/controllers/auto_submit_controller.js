// Auto-submit a form when a field changes
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    const form = event.target?.form || this.element
    if (form && typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else if (form) {
      form.submit()
    }
  }
}

