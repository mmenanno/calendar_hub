import { Controller } from "@hotwired/stimulus"

// Provides instant visual feedback when navigating between event views
// (upcoming/past toggle, show excluded toggle). Dims the events list and
// shows a spinner while Turbo Drive fetches the new page.
export default class extends Controller {
  static targets = ["list"]

  loading() {
    if (!this.hasListTarget) return

    this.listTarget.classList.add("opacity-40", "pointer-events-none", "transition-opacity")

    const spinner = document.createElement("div")
    spinner.className = "flex items-center justify-center py-8"
    spinner.innerHTML = `<svg class="animate-spin h-6 w-6 text-indigo-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>`
    this.listTarget.parentNode.insertBefore(spinner, this.listTarget)
  }
}
