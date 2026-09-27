import { Controller } from "@hotwired/stimulus"

// Provides instant visual feedback when navigating between event views
// (upcoming/past toggle, show excluded toggle). Dims the events list and
// shows a spinner while Turbo Drive fetches the new page.
//
// The loading state is cleared before Turbo caches the page so that
// navigating back restores an interactive list instead of a frozen one.
export default class extends Controller {
  static targets = ["list"]

  connect() {
    this.reset = this.reset.bind(this)
    document.addEventListener("turbo:before-cache", this.reset)
    // A snapshot cached before this fix may still carry the loading state
    this.reset()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.reset)
  }

  loading() {
    if (!this.hasListTarget) return

    this.reset()
    this.listTarget.classList.add("opacity-40", "pointer-events-none", "transition-opacity")
    this.listTarget.setAttribute("aria-busy", "true")

    const spinner = document.createElement("div")
    spinner.className = "flex items-center justify-center py-8"
    spinner.dataset.eventsToggleSpinner = ""
    spinner.setAttribute("role", "status")
    spinner.innerHTML = `<svg class="animate-spin h-6 w-6 text-indigo-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" aria-hidden="true"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg><span class="sr-only">Loading…</span>`
    this.listTarget.parentNode.insertBefore(spinner, this.listTarget)
  }

  reset() {
    this.element.querySelectorAll("[data-events-toggle-spinner]").forEach((el) => el.remove())
    if (!this.hasListTarget) return

    this.listTarget.classList.remove("opacity-40", "pointer-events-none")
    this.listTarget.removeAttribute("aria-busy")
  }
}
