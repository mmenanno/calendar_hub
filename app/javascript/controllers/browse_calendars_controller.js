import BaseController from "controllers/base_controller"

export default class extends BaseController {
  static targets = ["calendarField", "results", "loading", "error"]
  static values = { url: String }

  async browse(event) {
    event.preventDefault()

    this.showLoading()
    this.hideError()
    this.hideResults()

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content || "",
        },
      })

      const data = await response.json()

      if (data.success && data.calendars?.length > 0) {
        this.showResults(data.calendars)
      } else if (data.success && data.calendars?.length === 0) {
        this.showError("No calendars found.")
      } else {
        this.showError(data.error || "Discovery failed.")
      }
    } catch (e) {
      this.showError("Network error: " + e.message)
    } finally {
      this.hideLoading()
    }
  }

  select(event) {
    const identifier = event.target.value
    if (identifier && this.hasCalendarFieldTarget) {
      this.calendarFieldTarget.value = identifier
    }
  }

  showLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.classList.remove("hidden")
  }

  hideLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }

  hideError() {
    if (this.hasErrorTarget) this.errorTarget.classList.add("hidden")
  }

  showResults(calendars) {
    if (this.hasResultsTarget) {
      const wrapper = document.createElement("div")
      wrapper.className = "select-chevron"

      const select = document.createElement("select")
      select.className = this.calendarFieldTarget.className + " appearance-none pr-8"
      select.setAttribute("data-action", "change->browse-calendars#select")

      const placeholder = document.createElement("option")
      placeholder.value = ""
      placeholder.textContent = "Select a calendar..."
      select.appendChild(placeholder)

      calendars.forEach(cal => {
        const option = document.createElement("option")
        option.value = cal.identifier
        option.textContent = cal.displayname
        select.appendChild(option)
      })

      wrapper.appendChild(select)
      this.resultsTarget.innerHTML = ""
      this.resultsTarget.appendChild(wrapper)
      this.resultsTarget.classList.remove("hidden")
    }
  }

  hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.innerHTML = ""
      this.resultsTarget.classList.add("hidden")
    }
  }
}
