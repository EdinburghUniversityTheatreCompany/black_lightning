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

  bold() { this.#cmd(this.#cmds.toggleStrongCommand) }
  italic() { this.#cmd(this.#cmds.toggleEmphasisCommand) }
  strike() { this.#cmd(this.#cmds.toggleStrikethroughCommand) }
  h1() { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 1 }) }
  h2() { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 2 }) }
  h3() { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 3 }) }
  bulletList() { this.#cmd(this.#cmds.wrapInBulletListCommand) }
  orderedList() { this.#cmd(this.#cmds.wrapInOrderedListCommand) }
  taskList() { this.#toggleTaskList() }
  blockquote() { this.#cmd(this.#cmds.wrapInBlockquoteCommand) }
  inlineCode() { this.#cmd(this.#cmds.toggleInlineCodeCommand) }
  codeBlock() { this.#cmd(this.#cmds.createCodeBlockCommand) }
  insertLink() { this.#insertLink() }
  insertImage() { this.#fileInput?.click() }
  insertTable() { this.#cmd(this.#cmds.insertTableCommand) }
  undo() { this.#cmd(this.#cmds.undoCommand) }
  redo() { this.#cmd(this.#cmds.redoCommand) }

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
  #fileInput = null
  #cmds = {}

  #buildShell() {
    const toolbar = document.createElement("div")
    toolbar.className = "milkdown-toolbar"
    toolbar.innerHTML = `
      <div class="milkdown-tabs" role="tablist">
        <button type="button" class="milkdown-tab active" data-mode="edit"    data-action="click->markdown-editor#setMode" role="tab">Edit</button>
        <button type="button" class="milkdown-tab"        data-mode="source"  data-action="click->markdown-editor#setMode" role="tab">Source</button>
        <button type="button" class="milkdown-tab"        data-mode="preview" data-action="click->markdown-editor#setMode" role="tab">Preview</button>
      </div>
      <div class="milkdown-sep milkdown-sep--strong"></div>
      <div class="milkdown-toolbar__group">
        <button type="button" class="milkdown-btn" title="Bold (Ctrl+B)"   data-action="click->markdown-editor#bold"><i class="fa-solid fa-bold"></i></button>
        <button type="button" class="milkdown-btn" title="Italic (Ctrl+I)" data-action="click->markdown-editor#italic"><i class="fa-solid fa-italic"></i></button>
        <button type="button" class="milkdown-btn" title="Strikethrough"   data-action="click->markdown-editor#strike"><i class="fa-solid fa-strikethrough"></i></button>
      </div>
      <div class="milkdown-sep"></div>
      <div class="milkdown-toolbar__group">
        <button type="button" class="milkdown-btn milkdown-btn--text" title="Heading 1" data-action="click->markdown-editor#h1">H1</button>
        <button type="button" class="milkdown-btn milkdown-btn--text" title="Heading 2" data-action="click->markdown-editor#h2">H2</button>
        <button type="button" class="milkdown-btn milkdown-btn--text" title="Heading 3" data-action="click->markdown-editor#h3">H3</button>
      </div>
      <div class="milkdown-sep"></div>
      <div class="milkdown-toolbar__group">
        <button type="button" class="milkdown-btn" title="Bullet list"  data-action="click->markdown-editor#bulletList"><i class="fa-solid fa-list-ul"></i></button>
        <button type="button" class="milkdown-btn" title="Ordered list" data-action="click->markdown-editor#orderedList"><i class="fa-solid fa-list-ol"></i></button>
        <button type="button" class="milkdown-btn" title="Task list"    data-action="click->markdown-editor#taskList"><i class="fa-solid fa-list-check"></i></button>
        <button type="button" class="milkdown-btn" title="Blockquote"   data-action="click->markdown-editor#blockquote"><i class="fa-solid fa-quote-left"></i></button>
      </div>
      <div class="milkdown-sep"></div>
      <div class="milkdown-toolbar__group">
        <button type="button" class="milkdown-btn" title="Inline code" data-action="click->markdown-editor#inlineCode"><i class="fa-solid fa-code"></i></button>
        <button type="button" class="milkdown-btn" title="Code block"  data-action="click->markdown-editor#codeBlock"><i class="fa-solid fa-file-code"></i></button>
      </div>
      <div class="milkdown-sep"></div>
      <div class="milkdown-toolbar__group">
        <button type="button" class="milkdown-btn" title="Insert link"  data-action="click->markdown-editor#insertLink"><i class="fa-solid fa-link"></i></button>
        <button type="button" class="milkdown-btn" title="Upload image" data-action="click->markdown-editor#insertImage"><i class="fa-solid fa-image"></i></button>
        <button type="button" class="milkdown-btn" title="Insert table" data-action="click->markdown-editor#insertTable"><i class="fa-solid fa-table"></i></button>
      </div>
      <div class="milkdown-sep milkdown-sep--strong"></div>
      <div class="milkdown-toolbar__group">
        <button type="button" class="milkdown-btn" title="Undo (Ctrl+Z)" data-action="click->markdown-editor#undo"><i class="fa-solid fa-rotate-left"></i></button>
        <button type="button" class="milkdown-btn" title="Redo (Ctrl+Y)" data-action="click->markdown-editor#redo"><i class="fa-solid fa-rotate-right"></i></button>
      </div>
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

    this.#fileInput = document.createElement("input")
    this.#fileInput.type = "file"
    this.#fileInput.accept = "image/*"
    this.#fileInput.style.display = "none"
    this.#fileInput.addEventListener("change", () => this.#handleFileInputChange())
    this.element.appendChild(this.#fileInput)
  }

  async #mountEditor(value = null) {
    const markdown = value ?? this.#textarea.value

    const [
      { Editor, defaultValueCtx, rootCtx, editorViewCtx, commandsCtx },
      { commonmark, toggleStrongCommand, toggleEmphasisCommand, wrapInHeadingCommand,
        wrapInBulletListCommand, wrapInOrderedListCommand, wrapInBlockquoteCommand,
        createCodeBlockCommand, toggleInlineCodeCommand, updateLinkCommand },
      { gfm, toggleStrikethroughCommand, insertTableCommand },
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

    import("../styles/milkdown_editor.css")

    this.#cmds = {
      toggleStrongCommand, toggleEmphasisCommand, wrapInHeadingCommand,
      wrapInBulletListCommand, wrapInOrderedListCommand, wrapInBlockquoteCommand,
      createCodeBlockCommand, toggleInlineCodeCommand, toggleStrikethroughCommand,
      insertTableCommand, updateLinkCommand,
      undoCommand, redoCommand,
      callCommand, editorViewCtx, commandsCtx
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
        await this.#destroyEditor()
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

  #toggleTaskList() {
    if (!this.#editor || this.#mode !== "edit") return
    const { editorViewCtx, commandsCtx, wrapInBulletListCommand } = this.#cmds

    this.#editor.action(ctx => {
      const view = ctx.get(editorViewCtx)
      const { state, dispatch } = view
      const { $from } = state.selection

      let listItemDepth = null
      for (let d = $from.depth; d >= 0; d--) {
        if ($from.node(d).type.name === "list_item") { listItemDepth = d; break }
      }

      if (listItemDepth !== null) {
        const node = $from.node(listItemDepth)
        const pos = $from.before(listItemDepth)
        dispatch(state.tr.setNodeMarkup(pos, null, {
          ...node.attrs,
          checked: node.attrs.checked == null ? false : null
        }))
      } else {
        // Wrap in bullet list, then set the new list item as a task
        ctx.get(commandsCtx).call(wrapInBulletListCommand)
        const { $from: f } = view.state.selection
        for (let d = f.depth; d >= 0; d--) {
          if (f.node(d).type.name === "list_item") {
            view.dispatch(view.state.tr.setNodeMarkup(f.before(d), null, { ...f.node(d).attrs, checked: false }))
            break
          }
        }
      }
    })
  }

  #insertLink() {
    if (!this.#editor || this.#mode !== "edit") return
    const href = window.prompt("Link URL:")
    if (href) this.#cmd(this.#cmds.updateLinkCommand, { href, title: "" })
  }

  async #handleFileInputChange() {
    const files = this.#fileInput.files
    if (!files?.length || !this.#editor) return

    const { editorViewCtx } = this.#cmds
    const schema = this.#editor.action(ctx => ctx.get(editorViewCtx).state.schema)
    const nodes = await this.#uploadFiles(files, schema)

    if (nodes.length) {
      this.#editor.action(ctx => {
        const view = ctx.get(editorViewCtx)
        let tr = view.state.tr
        nodes.forEach(node => { tr = tr.replaceSelectionWith(node) })
        view.dispatch(tr)
      })
    }
    this.#fileInput.value = ""
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
