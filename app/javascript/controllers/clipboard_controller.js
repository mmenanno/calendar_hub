import BaseController from "controllers/base_controller"

export default class extends BaseController {
  static values = { text: String }
  static targets = ["button", "label"]

  copy () {
    const text = this.textValue || this.element.dataset.text || this.element.textContent
    navigator.clipboard.writeText(text).then(() => {
      this.flash("Copied")
    }).catch(() => {
      this.flash("Copy failed")
    })
  }

  flash (msg) {
    if (this.hasLabelTarget) {
      const original = this.labelTarget.textContent
      this.labelTarget.textContent = msg
      setTimeout(() => { this.labelTarget.textContent = original }, 1200)
    }
  }
}

