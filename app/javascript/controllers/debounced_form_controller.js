import BaseController from "controllers/base_controller"

/**
 * Base controller for forms that need debounced submission
 */
export default class DebouncedFormController extends BaseController {
  static values = {
    url: String,
    delay: { type: Number, default: 300 }
  }

  connect() {
    this.timeout = null
  }

  disconnect() {
    this.clearTimeout()
  }

  /**
   * Queue a debounced submission
   */
  queue() {
    this.clearTimeout()
    this.timeout = setTimeout(() => this.submit(), this.delayValue)
  }

  /**
   * Submit the form - override in subclasses for custom logic
   */
  async submit() {
    const form = this.element
    if (!form) return

    try {
      const formData = new FormData(form)
      const response = await this.fetchWithCsrf(this.urlValue, {
        method: 'POST',
        body: formData
      })

      if (response.ok) {
        const html = await response.text()
        this.renderTurboStream(html)
      }
    } catch (error) {
      console.error('Form submission failed:', error)
    }
  }

  /**
   * Clear the timeout
   */
  clearTimeout() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
  }
}
