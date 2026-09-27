import BaseController from "controllers/base_controller"

// Reorderable list (drag & drop plus keyboard-accessible move buttons).
//
// Markup:
//   <div data-controller="sortable" data-sortable-url-value="/things/reorder">
//     <tbody data-sortable-target="container">            (optional, defaults to the controller element)
//       <tr data-id="1" draggable="true" data-sortable-target="item"
//           data-action="dragstart->sortable#dragStart dragover->sortable#dragOver drop->sortable#drop dragend->sortable#dragEnd">
//         <button data-action="sortable#moveUp">…</button>
//         <button data-action="sortable#moveDown">…</button>
//
// Listeners are declared via data-action, so rows added later (turbo streams,
// duplicates) are sortable without re-binding. If saving fails the previous
// order is restored and an error toast is shown.
export default class extends BaseController {
  static targets = ["container", "item"]
  static values = {
    url: String,
    errorMessage: { type: String, default: "Could not save the new order. Please try again." },
  }

  get container () {
    return this.hasContainerTarget ? this.containerTarget : this.element
  }

  get items () {
    return this.itemTargets.filter((el) => el.parentElement === this.container)
  }

  currentOrder () {
    return this.items.map((el) => el.dataset.id)
  }

  // Drag & drop -------------------------------------------------------------

  dragStart (event) {
    this.dragging = event.currentTarget
    this.orderBeforeDrag = this.currentOrder()
    event.dataTransfer.effectAllowed = "move"
    try { event.dataTransfer.setData("text/plain", this.dragging.dataset.id) } catch { /* noop */ }
    this.dragging.classList.add("opacity-60")
  }

  dragOver (event) {
    if (!this.dragging) return
    event.preventDefault()
    const target = event.currentTarget
    if (target === this.dragging) return

    const rect = target.getBoundingClientRect()
    const halfway = rect.top + rect.height / 2
    if (event.clientY < halfway) {
      target.parentNode.insertBefore(this.dragging, target)
    } else {
      target.parentNode.insertBefore(this.dragging, target.nextSibling)
    }
  }

  drop (event) {
    event.preventDefault()
  }

  dragEnd () {
    if (!this.dragging) return

    this.dragging.classList.remove("opacity-60")
    this.dragging = null
    const before = this.orderBeforeDrag
    this.orderBeforeDrag = null
    if (before && before.join(",") !== this.currentOrder().join(",")) this.persist(before)
  }

  // Keyboard / button alternative --------------------------------------------

  moveUp (event) {
    this.move(event, -1)
  }

  moveDown (event) {
    this.move(event, 1)
  }

  move (event, direction) {
    event.preventDefault()
    const button = event.currentTarget
    const item = this.items.find((el) => el.contains(button))
    if (!item) return

    const items = this.items
    const index = items.indexOf(item)
    const neighbour = items[index + direction]
    if (!neighbour) return

    const before = this.currentOrder()
    if (direction < 0) {
      this.container.insertBefore(item, neighbour)
    } else {
      this.container.insertBefore(item, neighbour.nextSibling)
    }
    // Moving the node can drop focus; keep it on the pressed button
    button.focus()
    this.persist(before)
  }

  // Persistence ---------------------------------------------------------------

  async persist (previousOrder) {
    const order = this.currentOrder()

    try {
      const response = await this.fetchWithCsrf(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify({ order })
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
    } catch (error) {
      console.error("Failed to persist sort order:", error)
      this.restore(previousOrder)
      this.showToast(this.errorMessageValue, "error")
    }
  }

  restore (order) {
    if (!order) return
    const byId = new Map(this.items.map((el) => [el.dataset.id, el]))
    order.forEach((id) => {
      const el = byId.get(id)
      if (el) this.container.appendChild(el)
    })
  }
}
