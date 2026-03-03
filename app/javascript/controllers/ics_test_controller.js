import BaseController from "controllers/base_controller"

export default class extends BaseController {
  static targets = ["result", "urlField"]

  connect() {
    if (this.hasUrlFieldTarget) {
      this.urlFieldTarget.addEventListener("input", () => this.clearResult())
    }
  }

  async test(event) {
    const btn = event?.currentTarget
    const url = this.hasUrlFieldTarget ? this.urlFieldTarget.value.trim() : ""

    if (!url) {
      this.showError("Please enter an ICS feed URL first.")
      return
    }

    this.setButtonLoading(btn, true, "Testing...")

    try {
      const response = await this.fetchWithCsrf("/calendar_sources/test_ics_feed", {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify({ url: url })
      })

      const data = await response.json()

      if (data.success) {
        this.showSuccess(data.event_count, data.sample_titles)
      } else {
        this.showError(data.error || "Unknown error")
      }
    } catch (error) {
      this.showError("Request failed: " + error.message)
    } finally {
      this.setButtonLoading(btn, false)
    }
  }

  showSuccess(count, titles) {
    if (!this.hasResultTarget) return

    let html = `<div class="rounded-lg border border-emerald-700 bg-emerald-500/10 p-3 text-sm text-emerald-200">`
    html += `<p class="font-medium">Found ${this.escapeHtml(String(count))} event${count === 1 ? "" : "s"}</p>`
    if (titles && titles.length > 0) {
      html += `<ul class="mt-2 list-disc pl-5 text-xs text-emerald-300">`
      titles.forEach(title => {
        html += `<li>${this.escapeHtml(title)}</li>`
      })
      html += `</ul>`
    }
    html += `</div>`
    this.resultTarget.innerHTML = html
  }

  showError(message) {
    if (!this.hasResultTarget) return

    this.resultTarget.innerHTML = `<div class="rounded-lg border border-rose-700/40 bg-rose-950/40 p-3 text-sm text-rose-200">${this.escapeHtml(message)}</div>`
  }

  clearResult() {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = ""
    }
  }
}
