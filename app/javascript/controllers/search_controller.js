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
    if (this.hasFormTarget) {
      this.submitForm(this.formTarget)
    }
  }

  clearTimeout() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
  }
}
