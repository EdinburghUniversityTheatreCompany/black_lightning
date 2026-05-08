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
    this.#linkDialog?.remove()
    this.#destroyEditor()
  }

  // Actions

  setMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode !== this.#mode) this.#switchTo(mode)
  }

  bold() { this.#insertInlineMark("strong", this.#cmds.toggleStrongCommand, "bold") }
  italic() { this.#insertInlineMark("emphasis", this.#cmds.toggleEmphasisCommand, "italic") }
  strike() { this.#insertInlineMark("strike_through", this.#cmds.toggleStrikethroughCommand, "strikethrough") }
  h1() { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 1 }) }
  h2() { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 2 }) }
  h3() { this.#cmd(this.#cmds.wrapInHeadingCommand, { level: 3 }) }
  bulletList() { this.#cmd(this.#cmds.wrapInBulletListCommand) }
  orderedList() { this.#cmd(this.#cmds.wrapInOrderedListCommand) }
  taskList() { this.#toggleTaskList() }
  blockquote() { this.#cmd(this.#cmds.wrapInBlockquoteCommand) }
  inlineCode() { this.#insertInlineMark("inlineCode", this.#cmds.toggleInlineCodeCommand, "code") }
  codeBlock() { this.#cmd(this.#cmds.createCodeBlockCommand) }
  insertLink(event) { this.#showLinkDialog(event) }
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
  #linkDialog = null
  #linkDialogResolve = null
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

    // Prevent toolbar button clicks from stealing focus away from the editor,
    // then immediately re-focus the editor so ProseMirror commands have a valid selection.
    toolbar.addEventListener("mousedown", e => {
      if (e.target.closest(".milkdown-btn, .milkdown-tab")) {
        e.preventDefault()
        if (this.#editor && this.#cmds.editorViewCtx) {
          this.#editor.action(ctx => ctx.get(this.#cmds.editorViewCtx).focus())
        }
      }
    })

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

    this.#linkDialog = this.#buildLinkDialog()
    document.body.appendChild(this.#linkDialog)
  }

  #buildLinkDialog() {
    const dialog = document.createElement("dialog")
    dialog.className = "milkdown-link-dialog"
    dialog.innerHTML = `
      <form class="milkdown-link-dialog__form">
        <p class="milkdown-link-dialog__title">Insert link</p>
        <label class="milkdown-link-dialog__label">Text
          <input type="text" name="text" class="form-control form-control-sm mt-1" placeholder="Link text (optional)">
        </label>
        <label class="milkdown-link-dialog__label">URL
          <input type="url" name="href" class="form-control form-control-sm mt-1" placeholder="https://" required>
        </label>
        <div class="milkdown-link-dialog__actions">
          <button type="button" class="btn btn-sm btn-secondary" data-cancel>Cancel</button>
          <button type="submit" class="btn btn-sm btn-primary">Insert</button>
        </div>
      </form>
    `

    const form = dialog.querySelector("form")
    form.addEventListener("submit", e => {
      e.preventDefault()
      const data = new FormData(form)
      const result = { href: data.get("href"), text: data.get("text") }
      dialog.close()
      this.#linkDialogResolve?.(result)
      this.#linkDialogResolve = null
    })

    dialog.querySelector("[data-cancel]").addEventListener("click", () => {
      dialog.close()
    })

    // Resolve with null on any close (Escape key, cancel button, or backdrop)
    dialog.addEventListener("close", () => {
      this.#linkDialogResolve?.(null)
      this.#linkDialogResolve = null
    })

    return dialog
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
      { callCommand },
      { TextSelection }
    ] = await Promise.all([
      import("@milkdown/core"),
      import("@milkdown/preset-commonmark"),
      import("@milkdown/preset-gfm"),
      import("@milkdown/plugin-history"),
      import("@milkdown/plugin-clipboard"),
      import("@milkdown/plugin-listener"),
      import("@milkdown/plugin-upload"),
      import("@milkdown/utils"),
      import("@milkdown/prose/state")
    ])

    import("../styles/milkdown_editor.css")

    this.#cmds = {
      toggleStrongCommand, toggleEmphasisCommand, wrapInHeadingCommand,
      wrapInBulletListCommand, wrapInOrderedListCommand, wrapInBlockquoteCommand,
      createCodeBlockCommand, toggleInlineCodeCommand, toggleStrikethroughCommand,
      insertTableCommand, updateLinkCommand,
      undoCommand, redoCommand,
      callCommand, editorViewCtx, commandsCtx, TextSelection
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
    this.#editor.action(ctx => {
      ctx.get(this.#cmds.editorViewCtx).focus()
      ctx.get(this.#cmds.commandsCtx).call(cmdDef.key, payload)
    })
  }

  // For inline marks: inserts placeholder text with the mark applied when nothing
  // is selected, so the user can immediately type to replace it. Toggles the mark
  // on existing selections as usual.
  #insertInlineMark(markName, cmdDef, placeholder) {
    if (!this.#editor || this.#mode !== "edit") return
    const { editorViewCtx, commandsCtx, TextSelection } = this.#cmds

    this.#editor.action(ctx => {
      const view = ctx.get(editorViewCtx)
      view.focus()
      const { state } = view
      const { selection } = state

      if (!selection.empty) {
        ctx.get(commandsCtx).call(cmdDef.key)
        return
      }

      const markType = state.schema.marks[markName]
      if (!markType) return

      const from = selection.from
      const node = state.schema.text(placeholder, [markType.create()])
      // Pass false so ProseMirror doesn't strip the mark by inheriting from the cursor position
      const tr = state.tr.replaceSelectionWith(node, false)
      tr.setSelection(TextSelection.create(tr.doc, from, from + placeholder.length))
      view.dispatch(tr)
    })
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

  async #showLinkDialog(event) {
    if (!this.#editor || this.#mode !== "edit") return

    // Position dialog below the clicked button
    if (event?.currentTarget) {
      const rect = event.currentTarget.getBoundingClientRect()
      this.#linkDialog.style.margin = "0"
      this.#linkDialog.style.position = "fixed"
      this.#linkDialog.style.left = `${Math.min(rect.left, window.innerWidth - 340)}px`
      this.#linkDialog.style.top = `${rect.bottom + 6}px`
    }

    // Pre-fill text field if editor has a selection
    const { editorViewCtx } = this.#cmds
    let selectedText = ""
    this.#editor.action(ctx => {
      const view = ctx.get(editorViewCtx)
      const { state } = view
      if (!state.selection.empty) {
        selectedText = state.doc.textBetween(state.selection.from, state.selection.to)
      }
    })

    const form = this.#linkDialog.querySelector("form")
    form.reset()
    form.querySelector("[name='text']").value = selectedText

    this.#linkDialog.showModal()
    this.#linkDialog.querySelector("[name='href']").focus()

    const result = await new Promise(resolve => { this.#linkDialogResolve = resolve })
    if (!result?.href) return

    const { href, text } = result

    this.#editor.action(ctx => {
      const view = ctx.get(editorViewCtx)
      const { state, dispatch } = view
      const { selection, schema } = state
      const linkMark = schema.marks.link?.create({ href, title: "" })
      if (!linkMark) return

      if (!selection.empty) {
        // Apply link mark to selected text
        dispatch(state.tr.addMark(selection.from, selection.to, linkMark))
      } else {
        // Insert linked text, using insertText + addMark to avoid mark inheritance stripping
        const linkText = text?.trim() || href
        const from = selection.from
        const tr = state.tr.insertText(linkText, from)
        tr.addMark(from, from + linkText.length, linkMark)
        dispatch(tr)
      }
      view.focus()
    })
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
