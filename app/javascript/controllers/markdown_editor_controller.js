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
    this.#boundKeydown = (e) => this.#handleKeydown(e)
    this.element.addEventListener("keydown", this.#boundKeydown)
    try {
      await this.#mountEditor()
    } catch {
      this.#textarea.style.display = ""
      return
    }

    // Textarea is kept current via listenerCtx, but sync on submit as safety net
    this.#boundSync = () => this.#syncFromEditor()
    this.#form?.addEventListener("submit", this.#boundSync, { capture: true })
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.#boundKeydown)
    this.#form?.removeEventListener("submit", this.#boundSync, { capture: true })
    this.#linkDialog?.remove()
    this.#tableDialog?.remove()
    this.#destroyEditor()
  }

  // Actions

  setMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode !== this.#mode) this.#switchTo(mode)
  }

  bold() {
    this.#mode === "source"
      ? this.#sourceInline("**", "**", "bold")
      : this.#insertInlineMark("strong", this.#cmds.toggleStrongCommand, "bold")
  }

  italic() {
    this.#mode === "source"
      ? this.#sourceInline("*", "*", "italic")
      : this.#insertInlineMark("emphasis", this.#cmds.toggleEmphasisCommand, "italic")
  }

  strike() {
    this.#mode === "source"
      ? this.#sourceInline("~~", "~~", "strikethrough")
      : this.#insertInlineMark("strike_through", this.#cmds.toggleStrikethroughCommand, "strikethrough")
  }

  h1() {
    this.#mode === "source" ? this.#sourceLinePrefix("# ") : this.#cmd(this.#cmds.wrapInHeadingCommand, 1)
  }

  h2() {
    this.#mode === "source" ? this.#sourceLinePrefix("## ") : this.#cmd(this.#cmds.wrapInHeadingCommand, 2)
  }

  h3() {
    this.#mode === "source" ? this.#sourceLinePrefix("### ") : this.#cmd(this.#cmds.wrapInHeadingCommand, 3)
  }

  bulletList() {
    this.#mode === "source" ? this.#sourceLinePrefix("- ") : this.#cmd(this.#cmds.wrapInBulletListCommand)
  }

  orderedList() {
    this.#mode === "source" ? this.#sourceLinePrefix("1. ") : this.#cmd(this.#cmds.wrapInOrderedListCommand)
  }

  taskList() {
    this.#mode === "source" ? this.#sourceLinePrefix("- [ ] ") : this.#toggleTaskList()
  }

  blockquote() {
    this.#mode === "source" ? this.#sourceLinePrefix("> ") : this.#cmd(this.#cmds.wrapInBlockquoteCommand)
  }

  inlineCode() {
    this.#mode === "source"
      ? this.#sourceInline("`", "`", "code")
      : this.#insertInlineMark("inlineCode", this.#cmds.toggleInlineCodeCommand, "code")
  }

  codeBlock() {
    this.#mode === "source"
      ? this.#sourceBlock("```\n", "\n```", "code")
      : this.#cmd(this.#cmds.createCodeBlockCommand)
  }

  insertLink(event) { this.#showLinkDialog(event) }
  insertImage() { this.#fileInput?.click() }
  insertTable(event) { this.#showTableDialog(event) }

  undo() { if (this.#mode === "edit") this.#cmd(this.#cmds.undoCommand) }
  redo() { if (this.#mode === "edit") this.#cmd(this.#cmds.redoCommand) }

  // Private

  #textarea = null
  #editor = null
  #form = null
  #boundSync = null
  #boundKeydown = null
  #mode = "edit"
  #editorEl = null
  #sourceEl = null
  #sourceTextarea = null
  #previewEl = null
  #fileInput = null
  #linkDialog = null
  #linkDialogResolve = null
  #tableDialog = null
  #tableDialogResolve = null

  // Command definitions (objects with .key, used with commandsCtx.call())
  #cmds = {}
  // Milkdown context keys (used with ctx.get())
  #ctx = {}
  // Milkdown utility functions stored after dynamic import
  #TextSelection = null
  #replaceAll = null
  #insert = null

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
        <button type="button" class="milkdown-btn" title="Insert link (Ctrl+K)"  data-action="click->markdown-editor#insertLink"><i class="fa-solid fa-link"></i></button>
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
        if (this.#editor && this.#ctx.editorViewCtx) {
          this.#editor.action(ctx => ctx.get(this.#ctx.editorViewCtx).focus())
        }
      }
    })

    this.element.appendChild(toolbar)

    this.#editorEl = document.createElement("div")
    this.#editorEl.className = "milkdown-editor-wrap milkdown-panel rounded-bottom"
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
    this.#previewEl.className = "markdown-body prose max-w-none p-3 milkdown-panel rounded-bottom"
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

    this.#tableDialog = this.#buildTableDialog()
    document.body.appendChild(this.#tableDialog)
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
        createCodeBlockCommand, toggleInlineCodeCommand },
      { gfm, toggleStrikethroughCommand, insertTableCommand },
      { history, undoCommand, redoCommand },
      { clipboard },
      { listener, listenerCtx },
      { upload, uploadConfig },
      { replaceAll, insert },
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

    this.#ctx = { editorViewCtx, commandsCtx }
    this.#TextSelection = TextSelection
    this.#replaceAll = replaceAll
    this.#insert = insert

    this.#cmds = {
      toggleStrongCommand, toggleEmphasisCommand, wrapInHeadingCommand,
      wrapInBulletListCommand, wrapInOrderedListCommand, wrapInBlockquoteCommand,
      createCodeBlockCommand, toggleInlineCodeCommand, toggleStrikethroughCommand,
      insertTableCommand, undoCommand, redoCommand
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
    const editor = this.#editor
    // Null eagerly so a reconnect racing this async destruction sees a clean slate
    this.#editor = null
    this.#cmds = {}
    this.#ctx = {}
    this.#TextSelection = null
    this.#replaceAll = null
    this.#insert = null
    await editor?.destroy()
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
        // Replace content in the live editor — preserves the editor instance and plugins
        // flush=true re-creates ProseMirror state (clearing undo history) to match source edits
        this.#editor.action(this.#replaceAll(this.#textarea.value, true))
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
      body: JSON.stringify({ input_html: this.#textarea.value })
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
    // Focus and dispatch the command in a single action so ProseMirror reads the selection
    // from the already-focused view, avoiding ordering assumptions across two action calls.
    this.#editor.action(ctx => {
      ctx.get(this.#ctx.editorViewCtx).focus()
      ctx.get(this.#ctx.commandsCtx).call(cmdDef.key, payload)
    })
  }

  // ── Source-mode helpers ──────────────────────────────────────────────────────

  // Wraps selected text (or inserts placeholder) with before/after syntax.
  #sourceInline(before, after, placeholder) {
    const ta = this.#sourceTextarea
    const start = ta.selectionStart
    const end = ta.selectionEnd
    const selected = ta.value.substring(start, end)
    const text = selected || placeholder
    ta.value = ta.value.substring(0, start) + before + text + after + ta.value.substring(end)
    ta.setSelectionRange(start + before.length, start + before.length + text.length)
    this.#textarea.value = ta.value
    ta.focus()
  }

  // Inserts a markdown prefix at the start of the current line.
  #sourceLinePrefix(prefix) {
    const ta = this.#sourceTextarea
    const pos = ta.selectionStart
    const lineStart = ta.value.lastIndexOf("\n", pos - 1) + 1
    ta.value = ta.value.substring(0, lineStart) + prefix + ta.value.substring(lineStart)
    ta.setSelectionRange(pos + prefix.length, pos + prefix.length)
    this.#textarea.value = ta.value
    ta.focus()
  }

  // Wraps selected text (or placeholder) in a block-level syntax (e.g. fenced code).
  #sourceBlock(before, after, placeholder) {
    const ta = this.#sourceTextarea
    const start = ta.selectionStart
    const end = ta.selectionEnd
    const selected = ta.value.substring(start, end)
    const text = selected || placeholder
    const insertion = before + text + after
    ta.value = ta.value.substring(0, start) + insertion + ta.value.substring(end)
    ta.setSelectionRange(start + before.length, start + before.length + text.length)
    this.#textarea.value = ta.value
    ta.focus()
  }

  // For inline marks: inserts placeholder text with the mark applied when nothing
  // is selected, so the user can immediately type to replace it. Toggles the mark
  // on existing selections as usual.
  #insertInlineMark(markName, cmdDef, placeholder) {
    if (!this.#editor || this.#mode !== "edit") return

    this.#editor.action(ctx => {
      const view = ctx.get(this.#ctx.editorViewCtx)
      view.focus()
      const { state } = view
      const { selection } = state

      if (!selection.empty) {
        ctx.get(this.#ctx.commandsCtx).call(cmdDef.key)
        return
      }

      const markType = state.schema.marks[markName]
      if (!markType) return

      const from = selection.from
      const node = state.schema.text(placeholder, [markType.create()])
      // Pass false so ProseMirror doesn't strip the mark by inheriting from the cursor position
      const tr = state.tr.replaceSelectionWith(node, false)
      tr.setSelection(this.#TextSelection.create(tr.doc, from, from + placeholder.length))
      view.dispatch(tr)
    })
  }

  #toggleTaskList() {
    if (!this.#editor || this.#mode !== "edit") return

    this.#editor.action(ctx => {
      const view = ctx.get(this.#ctx.editorViewCtx)
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
        ctx.get(this.#ctx.commandsCtx).call(this.#cmds.wrapInBulletListCommand.key)
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
    if (this.#mode === "preview") return

    this.#positionDialog(this.#linkDialog, event ?? this.#getCursorCoords(), 340)

    // Pre-fill text field from current selection
    let selectedText = ""
    if (this.#mode === "source") {
      const ta = this.#sourceTextarea
      selectedText = ta.value.substring(ta.selectionStart, ta.selectionEnd)
    } else if (this.#editor) {
      this.#editor.action(ctx => {
        const view = ctx.get(this.#ctx.editorViewCtx)
        const { state } = view
        if (!state.selection.empty) {
          selectedText = state.doc.textBetween(state.selection.from, state.selection.to)
        }
      })
    }

    const form = this.#linkDialog.querySelector("form")
    form.reset()
    form.querySelector("[name='text']").value = selectedText

    this.#linkDialog.showModal()
    this.#linkDialog.querySelector("[name='href']").focus()

    const result = await new Promise(resolve => { this.#linkDialogResolve = resolve })
    if (!result?.href) return

    const { href, text } = result
    const linkText = text?.trim() || href

    if (this.#mode === "source") {
      const ta = this.#sourceTextarea
      const start = ta.selectionStart
      const end = ta.selectionEnd
      const insertion = `[${linkText}](${href})`
      ta.value = ta.value.substring(0, start) + insertion + ta.value.substring(end)
      ta.setSelectionRange(start + insertion.length, start + insertion.length)
      this.#textarea.value = ta.value
      ta.focus()
      return
    }

    this.#editor.action(ctx => {
      const view = ctx.get(this.#ctx.editorViewCtx)
      const { state, dispatch } = view
      const { selection, schema } = state
      const linkMark = schema.marks.link?.create({ href, title: "" })
      if (!linkMark) return

      if (!selection.empty) {
        // Apply link mark to selected text
        dispatch(state.tr.addMark(selection.from, selection.to, linkMark))
      } else {
        // Insert linked text, using insertText + addMark to avoid mark inheritance stripping
        const from = selection.from
        const tr = state.tr.insertText(linkText, from)
        tr.addMark(from, from + linkText.length, linkMark)
        dispatch(tr)
      }
      view.focus()
    })
  }

  #buildTableDialog() {
    const dialog = document.createElement("dialog")
    dialog.className = "milkdown-table-dialog"
    dialog.innerHTML = `
      <form class="milkdown-link-dialog__form">
        <p class="milkdown-link-dialog__title">Insert table</p>
        <div style="display:flex;gap:0.75rem">
          <label class="milkdown-link-dialog__label" style="flex:1">Rows
            <input type="number" name="rows" class="form-control form-control-sm mt-1" value="3" min="1" max="20">
          </label>
          <label class="milkdown-link-dialog__label" style="flex:1">Columns
            <input type="number" name="cols" class="form-control form-control-sm mt-1" value="3" min="1" max="10">
          </label>
        </div>
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
      const result = { rows: parseInt(data.get("rows"), 10) || 3, cols: parseInt(data.get("cols"), 10) || 3 }
      dialog.close()
      this.#tableDialogResolve?.(result)
      this.#tableDialogResolve = null
    })

    dialog.querySelector("[data-cancel]").addEventListener("click", () => dialog.close())
    dialog.addEventListener("close", () => {
      this.#tableDialogResolve?.(null)
      this.#tableDialogResolve = null
    })

    return dialog
  }

  async #showTableDialog(event) {
    if (this.#mode === "preview") return

    this.#positionDialog(this.#tableDialog, event, 260)
    this.#tableDialog.showModal()
    this.#tableDialog.querySelector("[name='rows']").focus()

    const result = await new Promise(resolve => { this.#tableDialogResolve = resolve })
    if (!result) return

    const { rows, cols } = result

    if (this.#mode === "source") {
      const header = "| " + Array(cols).fill("Header").join(" | ") + " |"
      const sep = "| " + Array(cols).fill("---").join(" | ") + " |"
      const row = "| " + Array(cols).fill("Cell").join(" | ") + " |"
      const table = [header, sep, ...Array(rows - 1).fill(row)].join("\n")
      this.#sourceBlock("", "\n", table)
      return
    }

    // WYSIWYG: build table nodes from schema
    this.#editor.action(ctx => {
      const view = ctx.get(this.#ctx.editorViewCtx)
      view.focus()
      const { state, dispatch } = view
      const { schema } = state
      const { table, table_row, table_cell, table_header } = schema.nodes

      if (!table || !table_row || !table_cell) {
        ctx.get(this.#ctx.commandsCtx).call(this.#cmds.insertTableCommand.key)
        return
      }

      const makeCell = (isHeader) => {
        const type = (isHeader && table_header) ? table_header : table_cell
        return type.createAndFill()
      }

      const headerRow = table_row.create(null, Array.from({ length: cols }, () => makeCell(true)))
      const bodyRows = Array.from({ length: Math.max(rows - 1, 0) }, () =>
        table_row.create(null, Array.from({ length: cols }, () => makeCell(false)))
      )
      const tableNode = table.create(null, [headerRow, ...bodyRows])
      dispatch(state.tr.replaceSelectionWith(tableNode))
    })
  }

  #handleKeydown(event) {
    const ctrl = event.ctrlKey || event.metaKey
    if (!ctrl) return

    switch (event.key) {
      case "b":
        if (this.#mode === "source") { event.preventDefault(); this.bold() }
        break
      case "i":
        if (this.#mode === "source") { event.preventDefault(); this.italic() }
        break
      case "k":
        if (this.#mode !== "preview") { event.preventDefault(); this.#showLinkDialog(null) }
        break
    }
  }

  // Returns {left, bottom} for the current cursor position, used to anchor dialogs
  // opened via keyboard shortcut. Edit mode uses ProseMirror's coordsAtPos; source
  // mode falls back to the top of the textarea.
  #getCursorCoords() {
    if (this.#mode === "edit" && this.#editor) {
      let coords = null
      this.#editor.action(ctx => {
        const view = ctx.get(this.#ctx.editorViewCtx)
        const c = view.coordsAtPos(view.state.selection.from)
        coords = { left: c.left, bottom: c.bottom }
      })
      if (coords) return coords
    }
    if (this.#sourceTextarea) {
      const rect = this.#sourceTextarea.getBoundingClientRect()
      return { left: rect.left, bottom: rect.top + 28 }
    }
    return null
  }

  // Positions a dialog anchored below a button event or a {left, bottom} coord pair.
  #positionDialog(dialog, anchor, maxWidth = 340) {
    let left, bottom
    if (anchor?.currentTarget) {
      const rect = anchor.currentTarget.getBoundingClientRect()
      left = rect.left
      bottom = rect.bottom
    } else if (anchor != null) {
      left = anchor.left
      bottom = anchor.bottom
    } else {
      return
    }
    dialog.style.margin = "0"
    dialog.style.position = "fixed"
    dialog.style.left = `${Math.min(left, window.innerWidth - maxWidth - 16)}px`
    dialog.style.top = `${bottom + 6}px`
  }

  async #handleFileInputChange() {
    const files = this.#fileInput.files
    if (!files?.length || !this.#editor) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const results = await Promise.all(
      Array.from(files)
        .filter(f => f.type.startsWith("image/"))
        .map(f => this.#uploadOneFile(f, csrfToken))
    )

    for (const { url, alt } of results.filter(Boolean)) {
      this.#editor.action(this.#insert(`![${alt || "image"}](${url})`))
    }
    this.#fileInput.value = ""
  }

  // Used by plugin-upload (drag/drop/paste) — returns ProseMirror nodes
  async #uploadFiles(files, schema) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const results = await Promise.all(
      Array.from(files)
        .filter(f => f.type.startsWith("image/"))
        .map(f => this.#uploadOneFile(f, csrfToken))
    )
    return results
      .filter(Boolean)
      .map(({ url, alt }) => schema.nodes.image?.createAndFill({ src: url, alt }))
      .filter(Boolean)
  }

  async #uploadOneFile(file, csrfToken) {
    const formData = new FormData()
    formData.append("image", file, file.name || "upload.png")
    if (this.itemTypeValue) formData.append("item_type", this.itemTypeValue)
    if (this.itemIdValue) formData.append("item_id", this.itemIdValue)
    const response = await fetch(this.uploadUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": csrfToken },
      body: formData
    })
    if (!response.ok) return null
    return response.json()
  }
}
