import BaseController from "controllers/base_controller"

export default class extends BaseController {
  async run(event) {
    const btn = event?.currentTarget
    this.setButtonLoading(btn, true, 'Testing…')

    try {
      const username = document.getElementById("app_setting_apple_username")?.value || ""
      const password = document.getElementById("app_setting_apple_app_password")?.value || ""

      const response = await this.fetchWithCsrf("/settings/test_calendar", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ apple_username: username, apple_app_password: password })
      })

      const html = await response.text()
      this.renderTurboStream(html)
    } catch (error) {
      console.error('Calendar test failed:', error)
    } finally {
      this.setButtonLoading(btn, false)
    }
  }
}
