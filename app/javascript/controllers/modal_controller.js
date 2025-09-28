import BaseController from "./base_controller"

// Closes the shared Turbo Frame modal on Escape or backdrop click
export default class extends BaseController {
  connect () {
    this.onKeyDown = this.handleKeyDown.bind(this)
    window.addEventListener('keydown', this.onKeyDown)
    this.element.addEventListener('click', this.onBackdropClick)
  }

  disconnect () {
    window.removeEventListener('keydown', this.onKeyDown)
    this.element.removeEventListener('click', this.onBackdropClick)
  }

  handleKeyDown (event) {
    if (event.key === 'Escape') this.close()
  }

  onBackdropClick = (event) => {
    // Only close when clicking the semi‑transparent overlay, not inner card
    if (event.target === this.element) this.close()
  }

  close () {
    // Empty the Turbo Frame to hide the modal
    this.element.innerHTML = ''
  }
}

