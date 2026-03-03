import BaseController from "controllers/base_controller"

export default class extends BaseController {
  static targets = ["menu", "openButton", "closeButton"]

  connect () {
    this.closeOnEscape = this.closeOnEscape.bind(this)
  }

  open () {
    this.menuTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    document.addEventListener("keydown", this.closeOnEscape)
    // Focus the close button for accessibility
    requestAnimationFrame(() => {
      if (this.hasCloseButtonTarget) this.closeButtonTarget.focus()
    })
  }

  close () {
    this.menuTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.closeOnEscape)
    // Return focus to the open button
    if (this.hasOpenButtonTarget) this.openButtonTarget.focus()
  }

  closeOnEscape (event) {
    if (event.key === "Escape") this.close()
  }

  disconnect () {
    document.removeEventListener("keydown", this.closeOnEscape)
    document.body.classList.remove("overflow-hidden")
  }
}
