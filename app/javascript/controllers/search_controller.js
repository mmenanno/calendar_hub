import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "form"]
  static values = { delay: { type: Number, default: 300 } }

  connect() {
    this.timeout = null
  }

  disconnect() {
    this.clearTimeout()
  }

  search() {
    this.clearTimeout()
    this.timeout = setTimeout(() => {
      this.submitForm()
    }, this.delayValue)
  }

  submitForm() {
    if (this.hasFormTarget) {
      if (this.formTarget.requestSubmit) {
        this.formTarget.requestSubmit()
      } else {
        this.formTarget.submit()
      }
    }
  }

  clearTimeout() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
  }
}
