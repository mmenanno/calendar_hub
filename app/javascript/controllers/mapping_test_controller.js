import BaseController from "./base_controller"

export default class extends BaseController {
  static values = {
    url: String,
    delay: { type: Number, default: 300 }
  }
  static targets = ["source", "input"]

  connect() {
    this.timer = null
  }

  disconnect() {
    this.clearTimeout()
  }

  queue() {
    this.clearTimeout()
    this.timer = setTimeout(() => this.run(), this.delayValue)
  }

  async run() {
    try {
      const body = JSON.stringify({
        calendar_source_id: this.sourceTarget.value,
        sample_title: this.inputTarget.value
      })

      const response = await this.fetchWithCsrf(this.urlValue, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body
      })

      const html = await response.text()
      this.renderTurboStream(html)
    } catch (error) {
      console.error('Mapping test failed:', error)
    }
  }

  clearTimeout() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }
}

