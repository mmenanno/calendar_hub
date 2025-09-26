import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "input"]
  static values = { url: String }

  connect () {
    this.timeout = null
  }

  queue () {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submit(), 250)
  }

  submit () {
    const form = this.element
    if (!form) return

    if (!this.anyFilled()) {
      const result = document.getElementById('filter_test_result')
      if (result) {
        result.innerHTML = ''
      }
      return
    }

    const body = new FormData(form)
    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content')

    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": csrfToken, Accept: "text/vnd.turbo-stream.html" },
      body,
      credentials: "same-origin",
    })
      .then((response) => response.ok ? response.text() : Promise.reject(response))
      .then((html) => {
        if (!html || !html.trim()) return
        if (window.Turbo && typeof window.Turbo.renderStreamMessage === "function") {
          window.Turbo.renderStreamMessage(html)
        }
      })
      .catch((error) => console.error("Filter test failed", error))
  }

  anyFilled () {
    return this.inputTargets.some((input) => input.value.trim().length > 0)
  }
}
