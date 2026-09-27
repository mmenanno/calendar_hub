import BaseController from "controllers/base_controller"

export default class extends BaseController {
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
      this.submit()
    }, this.delayValue)
  }

  submit() {
    this.submitForm(this.form)
  }

  // Also usable directly as a Stimulus action (e.g. `change->search#submitForm`),
  // in which case Stimulus passes the DOM event rather than a form element.
  submitForm(formOrEvent) {
    const form = formOrEvent instanceof HTMLFormElement ? formOrEvent : this.form
    this.clearTimeout()
    super.submitForm(form)
  }

  get form() {
    if (this.hasFormTarget) return this.formTarget
    return this.element instanceof HTMLFormElement ? this.element : this.element.closest("form")
  }

  clearTimeout() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
  }
}
