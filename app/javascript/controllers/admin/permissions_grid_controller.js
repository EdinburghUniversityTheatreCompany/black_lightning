import { Controller } from "@hotwired/stimulus"

// Parses checkbox name format: [RoleName][SubjectClass]action
const NAME_RE = /^\[([^\]]+)\]\[([^\]]+)\](.+)$/

export default class extends Controller {
  static targets = ["modal", "dialog", "changeList", "changeCount", "changeCountText"]

  #initialState = new Map()
  #confirmed = false

  connect() {
    this.element.querySelectorAll('input[type="checkbox"]:not([disabled])').forEach(checkbox => {
      this.#initialState.set(this.#key(checkbox), checkbox.checked)
    })
  }

  markChanged() {
    this.#updateHighlights()
    this.#updateChangeCount()
  }

  confirmSubmit(event) {
    if (this.#confirmed) return

    const changes = this.#gatherChanges()
    if (changes.length === 0) return

    event.preventDefault()
    this.#showModal(changes)
  }

  cancelSubmit() {
    this.#hideModal()
  }

  backdropClick(event) {
    if (!this.dialogTarget.contains(event.target)) {
      this.#hideModal()
    }
  }

  approveSubmit() {
    this.#confirmed = true
    this.#hideModal()
    this.element.requestSubmit()
  }

  #key(checkbox) {
    return `${checkbox.name}::${checkbox.value}`
  }

  #parse(checkbox) {
    const match = checkbox.name.match(NAME_RE)
    if (!match) return { role: checkbox.name, subject: "", action: "" }
    return { role: match[1], subject: match[2], action: match[3] }
  }

  #updateHighlights() {
    this.element.querySelectorAll('input[type="checkbox"]:not([disabled])').forEach(checkbox => {
      const changed = checkbox.checked !== (this.#initialState.get(this.#key(checkbox)) ?? false)
      checkbox.closest("td")?.classList.toggle("permission-changed", changed)
    })
  }

  #updateChangeCount() {
    const changes = this.#gatherChanges()
    if (changes.length === 0) {
      this.changeCountTarget.classList.add("hidden")
      return
    }

    const roles = [...new Set(changes.map(c => c.role))].sort()
    this.changeCountTextTarget.textContent =
      `${changes.length} pending change${changes.length === 1 ? "" : "s"} in: ${roles.join(", ")}`
    this.changeCountTarget.classList.remove("hidden")
  }

  #gatherChanges() {
    const rows = []
    this.element.querySelectorAll('input[type="checkbox"]:not([disabled])').forEach(checkbox => {
      const initial = this.#initialState.get(this.#key(checkbox)) ?? false
      if (checkbox.checked === initial) return
      const { role, subject, action } = this.#parse(checkbox)
      rows.push({ role, subject, action, type: checkbox.checked ? "added" : "removed" })
    })
    rows.sort((a, b) => a.role.localeCompare(b.role) || a.subject.localeCompare(b.subject) || a.action.localeCompare(b.action))
    return rows
  }

  #showModal(changes) {
    const list = this.changeListTarget
    list.innerHTML = ""
    list.appendChild(this.#buildTable(changes))

    this.modalTarget.classList.remove("hidden")
    this.modalTarget.classList.add("flex")
  }

  #hideModal() {
    this.modalTarget.classList.add("hidden")
    this.modalTarget.classList.remove("flex")
  }

  #buildTable(changes) {
    const table = document.createElement("table")
    table.className = "w-full text-sm border-collapse"

    const thead = document.createElement("thead")
    thead.innerHTML = `
      <tr class="border-b border-gray-200">
        <th class="text-left py-2 pr-4 font-semibold text-gray-700">Role</th>
        <th class="text-left py-2 pr-4 font-semibold text-gray-700">Subject</th>
        <th class="text-left py-2 pr-4 font-semibold text-gray-700">Action</th>
        <th class="text-left py-2 font-semibold text-gray-700">Change</th>
      </tr>`
    table.appendChild(thead)

    const tbody = document.createElement("tbody")
    changes.forEach(({ role, subject, action, type }) => {
      const tr = document.createElement("tr")
      tr.className = "border-b border-gray-100 last:border-0"
      const badge = type === "added"
        ? `<span class="inline-flex items-center gap-1 text-green-700 font-medium">+ Added</span>`
        : `<span class="inline-flex items-center gap-1 text-red-700 font-medium">− Removed</span>`
      tr.innerHTML = `
        <td class="py-1.5 pr-4 text-gray-800">${this.#esc(role)}</td>
        <td class="py-1.5 pr-4 text-gray-600 font-mono text-xs">${this.#esc(subject)}</td>
        <td class="py-1.5 pr-4 text-gray-600">${this.#esc(action)}</td>
        <td class="py-1.5">${badge}</td>`
      tbody.appendChild(tr)
    })
    table.appendChild(tbody)

    return table
  }

  #esc(str) {
    return str.replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }
}
