import BaseController from "controllers/base_controller"

// Trims leading/trailing spaces on blur (and on connect for prefilled values)
export default class extends BaseController {
  static targets = ["field"]

  connect() {
    this.fieldTargets.forEach(el => this.applyTo(el))
  }

  apply(event) {
    const el = event?.target || null
    if (el) this.applyTo(el)
  }

  applyTo(el) {
    if (typeof el.value === "string") {
      const trimmed = el.value.replace(/\s+$/g, "").replace(/^\s+/g, "")
      if (trimmed !== el.value) el.value = trimmed
    }
  }
}

