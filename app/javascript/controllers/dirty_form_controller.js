import BaseController from "controllers/base_controller"

export default class extends BaseController {
  static targets = ["save"]
  // Start dirty (e.g. a form re-rendered with validation errors must stay submittable)
  static values = { dirty: Boolean }

  connect() {
    this.initial = this.dirtyValue ? null : this.snapshot()
    this.element.addEventListener("input", () => this.update())
    this.element.addEventListener("change", () => this.update())
    this.update()
  }

  update() {
    const dirty = !this.equals(this.initial, this.snapshot())
    this.saveTarget.classList.toggle("hidden", !dirty)
  }

  snapshot() {
    const data = new FormData(this.element)
    // Serialize to a simple object for comparison
    const obj = {}
    for (const [k, v] of data.entries()) obj[k] = v
    return JSON.stringify(obj)
  }

  equals(a, b) { return a === b }

  reset(event) {
    // Only reset if the submission was successful (2xx/3xx)
    if (event?.detail?.success) {
      this.initial = this.snapshot()
      this.update()
    }
  }
}
