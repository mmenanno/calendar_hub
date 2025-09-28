import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["container", "item"]
  static values = { url: String }

  connect () {
    this.dragging = null
    this.itemTargets.forEach((el) => {
      el.addEventListener('dragstart', this.onDragStart)
      el.addEventListener('dragover', this.onDragOver)
      el.addEventListener('drop', this.onDrop)
      el.addEventListener('dragend', this.onDragEnd)
    })
  }

  disconnect () {
    this.itemTargets.forEach((el) => {
      el.removeEventListener('dragstart', this.onDragStart)
      el.removeEventListener('dragover', this.onDragOver)
      el.removeEventListener('drop', this.onDrop)
      el.removeEventListener('dragend', this.onDragEnd)
    })
  }

  onDragStart = (e) => {
    this.dragging = e.currentTarget
    e.dataTransfer.effectAllowed = 'move'
    e.currentTarget.classList.add('opacity-60')
  }

  onDragOver = (e) => {
    e.preventDefault()
    const target = e.currentTarget
    if (!this.dragging || target === this.dragging) return
    const rect = target.getBoundingClientRect()
    const halfway = rect.top + rect.height / 2
    if (e.clientY < halfway) {
      target.parentNode.insertBefore(this.dragging, target)
    } else {
      target.parentNode.insertBefore(this.dragging, target.nextSibling)
    }
  }

  onDrop = (e) => {
    e.preventDefault()
  }

  onDragEnd = () => {
    if (!this.dragging) return
    this.dragging.classList.remove('opacity-60')
    this.dragging = null
    this.persistOrder()
  }

  async persistOrder() {
    const order = Array.from(this.containerTarget.querySelectorAll('[data-id]')).map(el => el.dataset.id)

    try {
      await this.fetchWithCsrf(this.urlValue, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ order })
      })
    } catch (error) {
      console.error('Failed to persist sort order:', error)
    }
  }
}

