import BaseController from "controllers/base_controller"

const FOCUSABLE = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled]):not([type='hidden'])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(",")

// Manages the shared Turbo Frame modal (<turbo-frame id="modal">):
// - exposes it as an accessible dialog while it has content
// - moves focus into it, traps Tab inside it and restores focus on close
// - closes on Escape or backdrop click
export default class extends BaseController {
  connect () {
    this.isOpen = false
    this.onKeyDown = this.handleKeyDown.bind(this)
    this.onDocumentClick = this.rememberOpener.bind(this)
    window.addEventListener("keydown", this.onKeyDown)
    document.addEventListener("click", this.onDocumentClick, { capture: true })
    this.element.addEventListener("click", this.onBackdropClick)

    // Content arrives via frame navigation or turbo streams (e.g. re-rendered
    // forms with errors) and is removed via `turbo_stream.update("modal", "")`.
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.element, { childList: true })
    this.sync()
  }

  disconnect () {
    window.removeEventListener("keydown", this.onKeyDown)
    document.removeEventListener("click", this.onDocumentClick, { capture: true })
    this.element.removeEventListener("click", this.onBackdropClick)
    this.observer?.disconnect()
  }

  rememberOpener (event) {
    const trigger = event.target.closest?.("[data-turbo-frame='modal']")
    if (trigger) this.opener = trigger
  }

  sync () {
    const hasContent = this.element.children.length > 0
    if (hasContent && !this.isOpen) {
      this.opened()
    } else if (hasContent) {
      // Content replaced while open (e.g. validation errors): keep focus inside
      if (!this.element.contains(document.activeElement)) this.focusFirst()
    } else if (!hasContent && this.isOpen) {
      this.closed()
    }
  }

  opened () {
    this.isOpen = true
    if (!this.opener && document.activeElement && !this.element.contains(document.activeElement)) {
      this.opener = document.activeElement
    }
    this.element.setAttribute("role", "dialog")
    this.element.setAttribute("aria-modal", "true")
    const heading = this.element.querySelector("h1, h2")
    if (heading) {
      if (!heading.id) heading.id = "modal-title"
      this.element.setAttribute("aria-labelledby", heading.id)
    }
    this.focusFirst()
  }

  closed () {
    this.isOpen = false
    this.element.removeAttribute("role")
    this.element.removeAttribute("aria-modal")
    this.element.removeAttribute("aria-labelledby")
    const opener = this.opener
    this.opener = null
    if (opener && opener.isConnected) opener.focus()
  }

  focusFirst () {
    const fields = this.focusables()
    const preferred = fields.find((el) => el.matches("input, select, textarea")) || fields[0]
    if (preferred) {
      preferred.focus()
    } else {
      this.element.setAttribute("tabindex", "-1")
      this.element.focus()
    }
  }

  focusables () {
    return Array.from(this.element.querySelectorAll(FOCUSABLE))
      .filter((el) => el.offsetParent !== null || el === document.activeElement)
  }

  handleKeyDown (event) {
    if (!this.isOpen) return

    if (event.key === "Escape") {
      // Let native <dialog>s (e.g. confirm prompts) handle their own Escape
      if (document.querySelector("dialog[open]")) return
      event.preventDefault()
      this.close()
    } else if (event.key === "Tab") {
      this.trapFocus(event)
    }
  }

  trapFocus (event) {
    const fields = this.focusables()
    if (fields.length === 0) {
      event.preventDefault()
      return
    }
    const first = fields[0]
    const last = fields[fields.length - 1]
    const active = document.activeElement

    if (!this.element.contains(active)) {
      event.preventDefault()
      first.focus()
    } else if (event.shiftKey && active === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first.focus()
    }
  }

  onBackdropClick = (event) => {
    // Only close when clicking the semi‑transparent overlay, not inner card
    if (event.target === this.element) this.close()
  }

  close () {
    // Empty the Turbo Frame to hide the modal (the observer restores focus)
    this.element.innerHTML = ""
  }
}
