import { Controller } from "@hotwired/stimulus"

// Loads a saved template into a questions/jobs form by clicking the form's own
// nested-form "Add" buttons and filling the row each click inserts. The views
// set the templates-base-url and templates-items-type meta tags.
const ROWS = {
  questions: (template) => [
    ...(template.questions ?? []).map((item) =>
      ({ button: ".question_add_button", row: ".nested-fields.question", fields: ["question_text", "response_type"], item })),
    ...(template.notify_emails ?? []).map((item) =>
      ({ button: ".notify_email_add_button", row: ".nested-fields.email", fields: ["email"], item })),
  ],
  jobs: (template) => (template.staffing_jobs ?? []).map((item) =>
    ({ button: ".staffing_job_add_button", row: ".nested-fields", fields: ["name"], item })),
}

const element = (tag, className, textContent = "") =>
  Object.assign(document.createElement(tag), { className, textContent })

export default class extends Controller {
  static targets = ["dialog", "list", "summary", "loadButton"]

  #itemsType = null
  #templates = []
  #selected = null

  connect() {
    this.#itemsType = document.querySelector('meta[name="templates-items-type"]').content
    const url = document.querySelector('meta[name="templates-base-url"]').content
    this.listTarget.addEventListener("change", () => this.#select())
    this.loadButtonTarget.addEventListener("click", () => this.#load())

    fetch(`${url}.json`, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.json()
      })
      .then((templates) => {
        this.#templates = templates
        for (const template of templates) this.listTarget.add(new Option(template.name, template.id))
      })
      .catch((error) => console.error("Failed to load template list:", error))
  }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  #select() {
    this.#selected = this.#templates.find((t) => String(t.id) === this.listTarget.value) ?? null
    this.loadButtonTarget.disabled = !this.#selected
    this.summaryTarget.replaceChildren(...(this.#selected ? this.#summary() : []))
  }

  #summary() {
    const list = element("ul", "space-y-1")
    list.id = "template_items_list"

    if (this.#itemsType === "questions") {
      for (const { question_text, response_type } of this.#selected.questions ?? []) {
        const li = element("li", "flex items-start gap-2 text-sm py-1 border-b border-gray-100 last:border-0")
        li.append(element("span", "flex-1 text-gray-800", question_text ?? ""))
        if (response_type) {
          li.append(element("span", "text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-500 shrink-0 font-mono",
            response_type.replace(/_/g, " ")))
        }
        list.append(li)
      }
    } else {
      for (const { name } of this.#selected.staffing_jobs ?? []) {
        list.append(element("li", "text-sm text-gray-800 py-1 border-b border-gray-100 last:border-0", name ?? ""))
      }
    }

    return [element("p", "text-xs font-semibold text-gray-500 uppercase tracking-wide mt-3 mb-1", "Preview"), list]
  }

  async #load() {
    if (!this.#selected) return
    this.dialogTarget.close()

    for (const { button, row, fields, item } of ROWS[this.#itemsType](this.#selected)) {
      const add = document.querySelector(button)
      if (!add) continue

      add.click()
      const inserted = [...document.querySelectorAll(row)].at(-1)
      for (const field of fields) {
        const input = inserted.querySelector(`[name$="[${field}]"]`)
        if (input) input.value = item[field] ?? ""
      }
      await new Promise((resolve) => setTimeout(resolve, 0))
    }
  }
}
