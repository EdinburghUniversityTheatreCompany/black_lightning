import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    uploadUrl: String,
    height: { type: String, default: "300px" },
    itemType: String,
    itemId: String
  }

  async connect() {
    this.#textarea = this.element.querySelector("textarea")
    if (!this.#textarea) return

    this.#form = this.#textarea.closest("form")
    this.#textarea.style.display = "none"

    this.#buildShell()
    await this.#mountEditor()

    // Textarea is kept current via listenerCtx, but sync on submit as safety net
    this.#boundSync = () => this.#syncFromEditor()
    this.#form?.addEventListener("submit", this.#boundSync, { capture: true })
  }

  disconnect() {
    this.#form?.removeEventListener("submit", this.#boundSync, { capture: true })
    this.#destroyEditor()
  }

  // Actions

  setMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode !== this.#mode) this.#switchTo(mode)
  }

  bold()        { this.#cmd(this.#cmds.toggleStrongCommand) }
  italic()      { this.#cmd(this.#cmds.toggleEmphasisCommand) }
  strike()      { this.#cmd(this.#cmds.toggleStrikethroughCommand) }
  h1()          { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 1 }) }
  h2()          { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 2 }) }
  h3()          { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 3 }) }
  bulletList()  { this.#cmd(this.#cmds.wrapInBulletListCommand) }
  orderedList() { this.#cmd(this.#cmds.wrapInOrderedListCommand) }
  blockquote()  { this.#cmd(this.#cmds.wrapInBlockquoteCommand) }
  codeBlock()   { this.#cmd(this.#cmds.createCodeBlockCommand) }
  inlineCode()  { this.#cmd(this.#cmds.toggleInlineCodeCommand) }
  undo()        { this.#cmd(this.#cmds.undoCommand) }
  redo()        { this.#cmd(this.#cmds.redoCommand) }

  // Private

  #textarea = null
  #editor = null
  #form = null
  #boundSync = null
  #mode = "edit"
  #editorEl = null
  #sourceEl = null
  #sourceTextarea = null
  #previewEl = null
  #cmds = {}

  #buildShell() {
    const toolbar = document.createElement("div")
    toolbar.className = "milkdown-toolbar d-flex align-items-center gap-1 flex-wrap border rounded-top bg-light p-1"
    toolbar.innerHTML = `
      <div class="btn-group btn-group-sm" role="group" aria-label="Editor mode">
        <button type="button" class="btn btn-outline-secondary active" data-mode="edit"    data-action="click->markdown-editor#setMode">Edit</button>
        <button type="button" class="btn btn-outline-secondary"        data-mode="source"  data-action="click->markdown-editor#setMode">Source</button>
        <button type="button" class="btn btn-outline-secondary"        data-mode="preview" data-action="click->markdown-editor#setMode">Preview</button>
      </div>
      <div class="vr mx-1"></div>
      <button type="button" class="btn btn-sm btn-outline-secondary fw-bold"  title="Bold"         data-action="click->markdown-editor#bold">B</button>
      <button type="button" class="btn btn-sm btn-outline-secondary fst-italic" title="Italic"     data-action="click->markdown-editor#italic">I</button>
      <button type="button" class="btn btn-sm btn-outline-secondary text-decoration-line-through" title="Strikethrough" data-action="click->markdown-editor#strike">S</button>
      <div class="vr mx-1"></div>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Heading 1"     data-action="click->markdown-editor#h1">H1</button>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Heading 2"     data-action="click->markdown-editor#h2">H2</button>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Heading 3"     data-action="click->markdown-editor#h3">H3</button>
      <div class="vr mx-1"></div>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Bullet list"   data-action="click->markdown-editor#bulletList">&#8226; List</button>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Ordered list"  data-action="click->markdown-editor#orderedList">1. List</button>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Blockquote"    data-action="click->markdown-editor#blockquote">&#10078;</button>
      <div class="vr mx-1"></div>
      <button type="button" class="btn btn-sm btn-outline-secondary font-monospace" title="Inline code" data-action="click->markdown-editor#inlineCode">\`code\`</button>
      <button type="button" class="btn btn-sm btn-outline-secondary font-monospace" title="Code block"  data-action="click->markdown-editor#codeBlock">{ }</button>
      <div class="vr mx-1"></div>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Undo (Ctrl+Z)" data-action="click->markdown-editor#undo">&#8617;</button>
      <button type="button" class="btn btn-sm btn-outline-secondary" title="Redo (Ctrl+Y)" data-action="click->markdown-editor#redo">&#8618;</button>
    `
    this.element.appendChild(toolbar)

    this.#editorEl = document.createElement("div")
    this.#editorEl.className = "milkdown-editor-wrap border border-top-0 rounded-bottom"
    this.#editorEl.style.minHeight = this.heightValue
    this.element.appendChild(this.#editorEl)

    this.#sourceEl = document.createElement("div")
    this.#sourceEl.style.display = "none"
    this.#sourceTextarea = document.createElement("textarea")
    this.#sourceTextarea.className = "form-control font-monospace border-top-0 rounded-top-0"
    this.#sourceTextarea.style.height = this.heightValue
    this.#sourceTextarea.style.resize = "vertical"
    this.#sourceEl.appendChild(this.#sourceTextarea)
    this.element.appendChild(this.#sourceEl)

    this.#previewEl = document.createElement("div")
    this.#previewEl.className = "markdown-body prose max-w-none p-3 border rounded-bottom"
    this.#previewEl.style.display = "none"
    this.element.appendChild(this.#previewEl)
  }

  async #mountEditor(value = null) {
    const markdown = value ?? this.#textarea.value

    const [
      { Editor, defaultValueCtx, rootCtx },
      { commonmark, toggleStrongCommand, toggleEmphasisCommand, wrapInHeadingCommand,
        wrapInBulletListCommand, wrapInOrderedListCommand, wrapInBlockquoteCommand,
        createCodeBlockCommand, toggleInlineCodeCommand },
      { gfm, toggleStrikethroughCommand },
      { history, undoCommand, redoCommand },
      { clipboard },
      { listener, listenerCtx },
      { upload, uploadConfig },
      { callCommand }
    ] = await Promise.all([
      import("@milkdown/core"),
      import("@milkdown/preset-commonmark"),
      import("@milkdown/preset-gfm"),
      import("@milkdown/plugin-history"),
      import("@milkdown/plugin-clipboard"),
      import("@milkdown/plugin-listener"),
      import("@milkdown/plugin-upload"),
      import("@milkdown/utils")
    ])

    // Inject editor CSS once — Vite handles deduplication
    import("../styles/milkdown_editor.css")

    this.#cmds = {
      toggleStrongCommand, toggleEmphasisCommand, wrapInHeadingCommand,
      wrapInBulletListCommand, wrapInOrderedListCommand, wrapInBlockquoteCommand,
      createCodeBlockCommand, toggleInlineCodeCommand, toggleStrikethroughCommand,
      undoCommand, redoCommand, callCommand
    }

    this.#editor = await Editor.make()
      .config(ctx => {
        ctx.set(rootCtx, this.#editorEl)
        ctx.set(defaultValueCtx, markdown)
        ctx.get(listenerCtx).markdownUpdated((_ctx, md) => {
          this.#textarea.value = md
        })
        ctx.update(uploadConfig.key, prev => ({
          ...prev,
          uploader: (files, schema) => this.#uploadFiles(files, schema)
        }))
      })
      .use(commonmark)
      .use(gfm)
      .use(history)
      .use(clipboard)
      .use(listener)
      .use(upload)
      .create()

    const prose = this.#editorEl.querySelector(".ProseMirror")
    if (prose) prose.classList.add("markdown-body", "prose", "max-w-none", "p-3")
  }

  async #destroyEditor() {
    await this.#editor?.destroy()
    this.#editor = null
    this.#cmds = {}
  }

  async #switchTo(mode) {
    if (this.#mode === "source") {
      this.#textarea.value = this.#sourceTextarea.value
    }

    const prev = this.#mode
    this.#mode = mode

    this.element.querySelectorAll("[data-mode]").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.mode === mode)
    })

    this.#editorEl.style.display = "none"
    this.#sourceEl.style.display = "none"
    this.#previewEl.style.display = "none"

    if (mode === "edit") {
      if (prev === "source") {
        this.#destroyEditor()
        this.#editorEl.innerHTML = ""
        await this.#mountEditor(this.#textarea.value)
      }
      this.#editorEl.style.display = ""
    } else if (mode === "source") {
      this.#sourceTextarea.value = this.#textarea.value
      this.#sourceEl.style.display = ""
    } else if (mode === "preview") {
      await this.#loadPreview()
      this.#previewEl.style.display = ""
    }
  }

  async #loadPreview() {
    this.#previewEl.innerHTML = '<p class="text-muted">Loading preview…</p>'
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch("/markdown/preview", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify({ input_html: encodeURIComponent(this.#textarea.value) })
    })
    if (response.ok) {
      const { rendered_md } = await response.json()
      this.#previewEl.innerHTML = rendered_md
    } else {
      this.#previewEl.innerHTML = '<p class="text-danger">Preview failed.</p>'
    }
  }

  #syncFromEditor() {
    // Textarea is already current via listenerCtx; this is a safety net for submit
    if (this.#mode === "source") this.#textarea.value = this.#sourceTextarea.value
  }

  #cmd(cmdDef, payload = undefined) {
    if (!this.#editor || this.#mode !== "edit" || !cmdDef) return
    this.#editor.action(this.#cmds.callCommand(cmdDef.key, payload))
  }

  async #uploadFiles(files, schema) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const nodes = []
    for (const file of files) {
      if (!file.type.startsWith("image/")) continue
      const formData = new FormData()
      formData.append("image", file, file.name || "upload.png")
      if (this.itemTypeValue) formData.append("item_type", this.itemTypeValue)
      if (this.itemIdValue) formData.append("item_id", this.itemIdValue)
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken },
        body: formData
      })
      if (response.ok) {
        const { url, alt } = await response.json()
        const node = schema.nodes.image?.createAndFill({ src: url, alt })
        if (node) nodes.push(node)
      }
    }
    return nodes
  }
}
