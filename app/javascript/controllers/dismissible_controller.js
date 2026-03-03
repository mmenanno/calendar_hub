import BaseController from "controllers/base_controller"

export default class extends BaseController {
  static targets = ["banner"]

  dismiss(event) {
    const banner = event.target.closest("[data-dismissible-target='banner']")
    if (!banner) return

    const sourceId = banner.dataset.sourceId
    const failureCount = banner.dataset.failureCount

    // Store dismissed state in sessionStorage so it reappears on next session
    // or when the failure count increases
    if (sourceId && failureCount) {
      sessionStorage.setItem(`dismissed_alert_${sourceId}`, failureCount)
    }

    banner.remove()

    // Remove the container if no banners remain
    if (this.bannerTargets.length === 0) {
      this.element.remove()
    }
  }

  connect() {
    // Hide banners that were previously dismissed (unless failure count increased)
    this.bannerTargets.forEach(banner => {
      const sourceId = banner.dataset.sourceId
      const failureCount = banner.dataset.failureCount
      const dismissedCount = sessionStorage.getItem(`dismissed_alert_${sourceId}`)

      if (dismissedCount && dismissedCount === failureCount) {
        banner.remove()
      }
    })

    // Remove the container if all banners were dismissed
    if (this.bannerTargets.length === 0) {
      this.element.remove()
    }
  }
}
