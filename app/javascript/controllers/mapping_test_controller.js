import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["source", "input"]

  connect () {
    this.timer = null
  }

  queue () {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.run(), 300)
  }

  run () {
    const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content')
    const body = JSON.stringify({ calendar_source_id: this.sourceTarget.value, sample_title: this.inputTarget.value })
    fetch(this.urlValue, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, 'Accept': 'text/vnd.turbo-stream.html' },
      body
    }).then(r => r.text()).then(html => {
      if (window.Turbo && html.trim().length) {
        Turbo.renderStreamMessage(html)
      }
    }).catch(() => {})
  }
}

