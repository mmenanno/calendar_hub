import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  run(event) {
    const btn = event?.currentTarget
    const originalHTML = btn ? btn.innerHTML : null
    if (btn) { btn.disabled = true; btn.innerHTML = this.loadingHTML() }

    const username = document.getElementById("app_setting_apple_username")?.value || ""
    const password = document.getElementById("app_setting_apple_app_password")?.value || ""
    const token = document.querySelector('meta[name="csrf-token"]')?.content

    fetch("/settings/test_calendar", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: JSON.stringify({ apple_username: username, apple_app_password: password })
    })
      .then(resp => resp.text())
      .then(html => { if (window.Turbo) Turbo.renderStreamMessage(html) })
      .catch(() => {})
      .finally(() => { if (btn) { btn.disabled = false; btn.innerHTML = originalHTML } })
  }

  loadingHTML() {
    return `<span class="inline-flex items-center gap-2"><svg class="h-4 w-4 animate-spin text-slate-300" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"></path></svg>Testing…</span>`
  }
}
