// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const Hooks = {}

const R2Uploader = (entries, onViewError) => {
  entries.forEach(entry => {
    const request = new XMLHttpRequest()
    entry.xhr = request

    request.upload.addEventListener("progress", event => {
      if (event.lengthComputable) entry.progress(Math.round((event.loaded / event.total) * 100))
    })
    request.addEventListener("load", () => {
      if (request.status >= 200 && request.status < 300) {
        entry.progress(100)
      } else {
        onViewError(`R2 upload failed (${request.status})`)
      }
    })
    request.addEventListener("error", () => onViewError("R2 upload failed because of a network error"))
    request.open("PUT", entry.meta.url)
    request.setRequestHeader("Content-Type", entry.meta.content_type || entry.file.type)
    request.send(entry.file)
  })
}

const SIDEBAR_COLLAPSED_KEY = "admin-sidebar-collapsed"

Hooks.SidebarToggle = {
  mounted() {
    const sidebar = document.getElementById("admin-sidebar")
    if (!sidebar) return

    const setTitle = isCollapsed => {
      this.el.title = isCollapsed ? "Expand sidebar" : "Collapse sidebar"
    }

    const collapsed = localStorage.getItem(SIDEBAR_COLLAPSED_KEY) === "true"
    sidebar.classList.toggle("is-collapsed", collapsed)
    setTitle(collapsed)

    this.el.addEventListener("click", () => {
      const isCollapsed = sidebar.classList.toggle("is-collapsed")
      localStorage.setItem(SIDEBAR_COLLAPSED_KEY, isCollapsed)
      setTitle(isCollapsed)
    })
  }
}

Hooks.SortableList = {
  mounted() {
    this.draggedItem = null
    this.startOrder = this.order()

    this.onPointerDown = event => {
      const handle = event.target.closest("[data-sortable-handle]")
      if (!handle) return

      const item = this.itemFor(handle)
      if (!item) return

      item.draggable = true
    }

    this.onPointerUp = () => {
      if (this.draggedItem) return
      this.items().forEach(item => item.draggable = false)
    }

    this.onDragStart = event => {
      const item = this.itemFor(event.target)
      if (!item) return

      this.draggedItem = item
      this.startOrder = this.order()
      item.dataset.dragging = "true"
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", item.dataset.id)
    }

    this.onDragOver = event => {
      if (!this.draggedItem) return

      const target = this.itemFor(event.target)
      if (!target || target === this.draggedItem) return

      event.preventDefault()
      event.dataTransfer.dropEffect = "move"

      const targetRect = target.getBoundingClientRect()
      const insertAfter = event.clientY > targetRect.top + targetRect.height / 2
      this.items().forEach(item => delete item.dataset.dragOver)
      target.dataset.dragOver = "true"

      this.el.insertBefore(
        this.draggedItem,
        insertAfter ? target.nextElementSibling : target
      )
    }

    this.onDragLeave = event => {
      const item = this.itemFor(event.target)
      if (item) delete item.dataset.dragOver
    }

    this.onDrop = event => {
      if (!this.draggedItem) return
      event.preventDefault()
      this.persistOrder()
    }

    this.onDragEnd = () => {
      this.items().forEach(item => {
        item.draggable = false
        delete item.dataset.dragging
        delete item.dataset.dragOver
      })

      if (this.draggedItem) this.persistOrder()
      this.draggedItem = null
    }

    this.el.addEventListener("pointerdown", this.onPointerDown)
    document.addEventListener("pointerup", this.onPointerUp)
    this.el.addEventListener("dragstart", this.onDragStart)
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("dragleave", this.onDragLeave)
    this.el.addEventListener("drop", this.onDrop)
    this.el.addEventListener("dragend", this.onDragEnd)
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    document.removeEventListener("pointerup", this.onPointerUp)
    this.el.removeEventListener("dragstart", this.onDragStart)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("dragleave", this.onDragLeave)
    this.el.removeEventListener("drop", this.onDrop)
    this.el.removeEventListener("dragend", this.onDragEnd)
  },

  items() {
    return Array.from(this.el.querySelectorAll(":scope > [data-sortable-item]"))
  },

  itemFor(element) {
    const item = element.closest("[data-sortable-item]")
    return item?.parentElement === this.el ? item : null
  },

  order() {
    return this.items().map(item => item.dataset.id)
  },

  persistOrder() {
    const order = this.order()
    if (order.join(",") === this.startOrder.join(",")) return

    const payload = {
      [this.el.dataset.orderKey || "ids"]: order
    }

    if (this.el.dataset.parentKey) {
      payload[this.el.dataset.parentKey] = this.el.dataset.parentId
    }

    this.startOrder = order
    this.pushEvent(this.el.dataset.event, payload)
  }
}

Hooks.ProtectedVideo = {
  mounted() {
    this.playerHost = this.el.querySelector("[data-role='player']")
    this.watermark = this.el.querySelector("[data-role='watermark']")
    this.abortController = new AbortController()

    this.el.addEventListener("contextmenu", event => event.preventDefault())
    // Resize is applied once real metadata loads (see applyAspectRatio); transition
    // keeps that resize from feeling like a jump once the 16:9 placeholder is replaced.
    this.el.style.transition = "aspect-ratio 300ms ease-out, width 300ms ease-out, height 300ms ease-out"
    this.loadPlayer()
    this.moveWatermark()
    this.watermarkTimer = window.setInterval(() => this.moveWatermark(), 8000)
  },

  destroyed() {
    this.saveProgress?.()
    this.abortController?.abort()
    window.clearInterval(this.watermarkTimer)
  },

  async loadPlayer() {
    try {
      const response = await fetch(this.el.dataset.playbackUrl, {
        credentials: "same-origin",
        headers: {"accept": "application/json"},
        signal: this.abortController.signal
      })

      if (!response.ok) throw new Error(`Playback authorization failed (${response.status})`)

      const {url} = await response.json()
      await customElements.whenDefined("mux-player")

      const player = document.createElement("mux-player")
      player.setAttribute("src", url)
      player.setAttribute("stream-type", "on-demand")
      player.setAttribute("accent-color", "#009d77")
      player.setAttribute("metadata-video-title", this.el.dataset.videoTitle)
      player.setAttribute("metadata-viewer-user-id", this.el.dataset.viewerId)
      player.setAttribute("playsinline", "")
      player.style.width = "100%"
      player.style.height = "100%"
      // Letterbox non-16:9 sources instead of stretching them to fill the frame.
      player.style.setProperty("--media-object-fit", "contain")

      this.player = player
      this.lastSavedPosition = Number(this.el.dataset.startPosition || 0)
      this.lastSaveAt = 0
      // Furthest position actually played, updated every tick (unthrottled).
      this.furthestWatched = Number(this.el.dataset.startPosition || 0)

      player.addEventListener("loadedmetadata", () => {
        const startPosition = Number(this.el.dataset.startPosition || 0)

        if (startPosition > 0 && startPosition < player.duration) {
          player.currentTime = startPosition
        }

        this.applyAspectRatio(player.videoWidth, player.videoHeight)
      })

      player.addEventListener("timeupdate", () => {
        this.furthestWatched = Math.max(this.furthestWatched, player.currentTime)

        const now = Date.now()

        if (
          player.currentTime - this.lastSavedPosition >= 10 ||
          now - this.lastSaveAt >= 15000
        ) {
          this.saveProgress()
        }
      })

      // Snap back seeks past furthestWatched; tolerance absorbs rounding only.
      player.addEventListener("seeking", () => {
        if (player.currentTime > this.furthestWatched + 0.5) {
          player.currentTime = this.furthestWatched
        }
      })

      player.addEventListener("ended", () => {
        // Flush final position so mark_complete's watch-threshold check sees it.
        this.saveProgress()
        this.pushEvent("complete-lecture", {lecture_id: this.el.dataset.lectureId})
      })

      this.playerHost.replaceChildren(player)
    } catch (error) {
      if (error.name === "AbortError") return
      this.playerHost.textContent = "This protected video is temporarily unavailable."
      console.error(error)
    }
  },

  // Sizes the container to the video's real aspect ratio instead of the
  // hardcoded 16:9 placeholder. Landscape/square sources keep filling the
  // full width (unchanged look for standard 16:9 lectures); portrait sources
  // are capped by height instead, so a tall video doesn't blow out the page,
  // and their width is derived from that height via the same ratio.
  applyAspectRatio(width, height) {
    if (!width || !height) return

    this.el.style.aspectRatio = `${width} / ${height}`

    if (width < height) {
      this.el.style.width = "auto"
      this.el.style.maxWidth = "100%"
      this.el.style.height = "min(75vh, 640px)"
    } else {
      this.el.style.width = "100%"
      this.el.style.maxWidth = ""
      this.el.style.height = "auto"
    }
  },

  saveProgress() {
    if (!this.player || !Number.isFinite(this.player.currentTime)) return

    const position = Math.max(0, Math.floor(this.player.currentTime))
    if (position <= this.lastSavedPosition) return

    this.lastSavedPosition = position
    this.lastSaveAt = Date.now()
    this.pushEvent("video-progress", {
      lecture_id: this.el.dataset.lectureId,
      position_seconds: position
    })
  },

  moveWatermark() {
    if (!this.watermark) return

    const positions = [
      ["6%", "8%"],
      ["58%", "12%"],
      ["10%", "78%"],
      ["54%", "74%"],
      ["34%", "42%"]
    ]
    const [left, top] = positions[Math.floor(Math.random() * positions.length)]
    this.watermark.style.left = left
    this.watermark.style.top = top
  }
}

Hooks.VideoPreview = {
  mounted() {
    this.preview = this.el.querySelector("[data-role='preview']")

    this.el.addEventListener("change", event => {
      const input = event.target
      if (input.type !== "file" || !input.files || !input.files[0]) return

      const file = input.files[0]
      if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = URL.createObjectURL(file)

      this.preview.src = this.objectUrl
      this.preview.classList.remove("hidden")
      this.preview.onloadedmetadata = () => this.fillDuration()
    })
  },

  fillDuration() {
    const seconds = Math.round(this.preview.duration)
    if (!Number.isFinite(seconds) || seconds <= 0) return

    const durationInput = this.el
      .closest("form")
      ?.querySelector("[name='lecture[duration_seconds]']")

    if (durationInput) {
      durationInput.value = seconds
      durationInput.dispatchEvent(new Event("input", {bubbles: true}))
    }
  },

  destroyed() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  }
}

// Drives the "Upload files" / "Add link" mode toggle and the "Save link"
// button on the lecture resources panel. File uploads themselves go through
// LiveView's own native upload JS (see WasomiWeb.AdminLive.Components.ResourceUploader) —
// this hook only ever needs to know which panel is visible and forward the
// link form to the LectureLive.FormComponent that owns "add-link".
Hooks.R2ResourceUpload = {
  mounted() {
    this.linkInput = this.el.querySelector("[data-role='link']")
    this.addLinkButton = this.el.querySelector("[data-role='add-link']")
    this.modeButtons = Array.from(this.el.querySelectorAll("[data-role='resource-mode']"))
    this.modePanels = Array.from(this.el.querySelectorAll("[data-role='resource-panel']"))
    this.uploadTarget = this.el.getAttribute("phx-target")

    this.modeButtons.forEach(button => {
      button.addEventListener("click", () => this.setMode(button.dataset.mode))
    })
    this.setMode("upload")

    this.addLinkButton.addEventListener("click", () => {
      const url = this.linkInput.value.trim()
      if (!url) return
      this.pushUp("add-link", {url})
      this.linkInput.value = ""
    })
  },

  setMode(mode) {
    this.modeButtons.forEach(button => {
      const active = button.dataset.mode === mode
      button.setAttribute("aria-pressed", active ? "true" : "false")
      button.classList.toggle("bg-dark", active)
      button.classList.toggle("text-white", active)
      button.classList.toggle("text-muted", !active)
    })
    this.modePanels.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.mode !== mode)
    })
  },

  pushUp(event, payload) {
    if (this.uploadTarget) {
      this.pushEventTo(this.uploadTarget, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  }
}
function titleCaseFromFilename(filename) {
  return filename
    .replace(/\.[^/.]+$/, "")
    .replace(/[-_]+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean)
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ")
}

Hooks.MuxUpload = {
  mounted() {
    this.fileInput = this.el.querySelector("[data-role='file']")
    // When the widget lives inside a LiveComponent (e.g. the lecture form
    // modal) it sets phx-target so events reach the component, not the view.
    this.uploadTarget = this.el.getAttribute("phx-target")

    this.fileInput.addEventListener("change", () => {
      if (this.fileInput.files[0]) this.selectFile(this.fileInput.files[0])
    })

    this.el.addEventListener("dragover", event => event.preventDefault())
    this.el.addEventListener("drop", event => {
      event.preventDefault()
      const file = event.dataTransfer.files && event.dataTransfer.files[0]
      if (file) this.selectFile(file)
    })

    this.handleEvent("mux-upload-ready", ({url}) => this.upload(url))
    this.handleEvent("mux-check-upload", () => {
      window.clearTimeout(this.statusTimer)
      this.statusTimer = window.setTimeout(() => this.pushUp("check-upload", {}), 3000)
    })
    this.handleEvent("mux-reset", () => {
      this.request?.abort()
      window.clearTimeout(this.statusTimer)
      this.selectedFile = null
      if (this.fileInput) this.fileInput.value = ""
    })
  },

  destroyed() {
    this.request?.abort()
    window.clearTimeout(this.statusTimer)
  },

  selectFile(file) {
    this.selectedFile = file
    this.fillTitle(file.name)
    this.captureLocalPreview(file)

    this.pushUp("create-upload", {
      filename: file.name,
      content_type: file.type,
      size: file.size
    })
  },

  // Mux can't generate a real thumbnail until the asset finishes processing
  // server-side, but the browser already has the file — grab a frame from
  // it locally so the picker feels instant while the real upload/processing
  // continues in the background.
  captureLocalPreview(file) {
    const objectUrl = URL.createObjectURL(file)
    const video = document.createElement("video")
    video.muted = true
    video.playsInline = true
    video.preload = "metadata"
    video.src = objectUrl

    const cleanup = () => URL.revokeObjectURL(objectUrl)

    video.addEventListener(
      "loadeddata",
      () => {
        video.currentTime = Math.min(0.1, (video.duration || 1) / 2)
      },
      {once: true}
    )

    video.addEventListener(
      "seeked",
      () => {
        const canvas = document.createElement("canvas")
        canvas.width = 160
        canvas.height = Math.round((video.videoHeight / video.videoWidth) * 160) || 90

        const context = canvas.getContext("2d")
        context.drawImage(video, 0, 0, canvas.width, canvas.height)
        this.pushUp("local-preview", {data_url: canvas.toDataURL("image/jpeg", 0.7)})
        cleanup()
      },
      {once: true}
    )

    video.addEventListener("error", cleanup, {once: true})
  },

  fillTitle(filename) {
    const titleInput = this.el.closest("form")?.querySelector("[name='lecture[title]']")
    if (!titleInput || titleInput.value.trim() !== "") return

    const title = titleCaseFromFilename(filename)
    if (!title) return

    titleInput.value = title
    titleInput.dispatchEvent(new Event("input", {bubbles: true}))
  },

  pushUp(event, payload) {
    if (this.uploadTarget) {
      this.pushEventTo(this.uploadTarget, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  },

  upload(url) {
    const file = this.selectedFile
    if (!file) return
    // The progress bar only exists once the server has rendered past the
    // idle state, which has already happened by the time this fires.
    const progress = this.el.querySelector("[data-role='progress']")
    const request = new XMLHttpRequest()
    this.request = request

    request.upload.addEventListener("progress", event => {
      if (!event.lengthComputable || !progress) return
      progress.style.width = `${Math.round((event.loaded / event.total) * 100)}%`
    })

    request.addEventListener("load", () => {
      if (request.status >= 200 && request.status < 300) {
        if (progress) progress.style.width = "100%"
        this.pushUp("upload-complete", {})
      } else {
        console.error(`Mux upload failed (${request.status})`)
        this.pushUp("upload-failed", {status: request.status})
      }
    })

    request.addEventListener("error", () => {
      console.error("Mux upload failed because of a network error")
      this.pushUp("upload-failed", {})
    })

    request.open("PUT", url)
    request.setRequestHeader("Content-Type", file.type || "application/octet-stream")
    request.send(file)
  }
}

Hooks.PdfDownload = {
  mounted() {
    this.handleEvent("download-pdf", ({data, filename}) => {
      const bytes = Uint8Array.from(atob(data), char => char.charCodeAt(0))
      const blob = new Blob([bytes], {type: "application/pdf"})
      const url = URL.createObjectURL(blob)

      const link = document.createElement("a")
      link.href = url
      link.download = filename || "certificate.pdf"
      document.body.appendChild(link)
      link.click()
      link.remove()
      URL.revokeObjectURL(url)
    })
  }
}

Hooks.FlashAutoDismiss = {
  mounted() {
    this.schedule()
  },
  updated() {
    this.schedule()
  },
  schedule() {
    window.clearTimeout(this.dismissTimer)
    const ms = parseInt(this.el.dataset.autoDismissMs, 10) || 5000
    this.dismissTimer = window.setTimeout(() => this.el.click(), ms)
  },
  destroyed() {
    window.clearTimeout(this.dismissTimer)
  }
}

const MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"];
const DOW = ["S","M","T","W","T","F","S"];

export class CustomDatePicker {
  constructor(element) {
    this.el = element;
    this.input = this.el.querySelector("[data-dp-input]");
    this.trigger = this.el.querySelector("[data-dp-trigger]");
    this.display = this.el.querySelector("[data-dp-display]");
    this.pop = this.el.querySelector("[data-dp-pop]");
    this.body = this.el.querySelector("[data-dp-body]");
    
    this.initToday();
    this.parseValue();
    this.bindEvents();
  }

  initToday() {
    this.today = new Date();
    this.today.setHours(0,0,0,0);
    const maxVal = this.el.dataset.max;
    if (maxVal === "today") {
      this.max = this.today;
    } else if (maxVal && /^\d{4}-\d{2}-\d{2}$/.test(maxVal)) {
      const [y, m, d] = maxVal.split("-").map(Number);
      this.max = new Date(y, m - 1, d);
      this.max.setHours(0,0,0,0);
    } else {
      this.max = null;
    }
  }

  minYear() { return this.today.getFullYear() - 120; }
  maxYear() { return this.max ? this.max.getFullYear() : this.today.getFullYear() + 10; }

  parseValue() {
    const v = this.input ? this.input.value : "";
    if (v && /^\d{4}-\d{2}-\d{2}$/.test(v)) {
      const [y, m, d] = v.split("-").map(Number);
      this.selected = new Date(y, m - 1, d);
      this.selected.setHours(0,0,0,0);
    } else {
      this.selected = null;
    }
    this.renderDisplay();
  }

  iso(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, "0");
    const d = String(date.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  fmt(date) {
    return date.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
  }

  renderDisplay() {
    if (!this.display) return;
    if (this.selected) {
      this.display.textContent = this.fmt(this.selected);
      this.display.classList.remove("text-muted");
    } else {
      this.display.textContent = this.display.dataset.placeholder || "Choose a date";
      this.display.classList.add("text-muted");
    }
  }

  open() {
    const base = this.selected || this.today;
    this.viewYear = base.getFullYear();
    this.viewMonth = base.getMonth();
    this.mode = "days";
    this.renderCalendar();
    this.pop.removeAttribute("hidden");
  }

  close() {
    this.pop.setAttribute("hidden", "");
  }

  toggle() {
    this.pop.hasAttribute("hidden") ? this.open() : this.close();
  }

  bindEvents() {
    this.onTriggerClick = (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.toggle();
    };
    this.trigger.addEventListener("click", this.onTriggerClick);

    this.onPopClick = (e) => this.handlePopClick(e);
    this.pop.addEventListener("click", this.onPopClick);

    this.onDocClick = (e) => {
      if (!this.el.contains(e.target) && !this.pop.contains(e.target)) this.close();
    };
    document.addEventListener("click", this.onDocClick);

    this.onDocKeydown = (e) => {
      if (e.key === "Escape") this.close();
    };
    document.addEventListener("keydown", this.onDocKeydown);
  }

  destroy() {
    this.trigger.removeEventListener("click", this.onTriggerClick);
    this.pop.removeEventListener("click", this.onPopClick);
    document.removeEventListener("click", this.onDocClick);
    document.removeEventListener("keydown", this.onDocKeydown);
  }

  handlePopClick(e) {
    e.stopPropagation();
    
    // Month navigation (< or >)
    const nav = e.target.closest("[data-dp-nav]");
    if (nav) {
      e.preventDefault();
      this.viewMonth += parseInt(nav.dataset.dpNav, 10);
      if (this.viewMonth < 0) { this.viewMonth = 11; this.viewYear--; }
      if (this.viewMonth > 11) { this.viewMonth = 0; this.viewYear++; }
      this.renderCalendar();
      return;
    }

    // View switcher (open months or years list)
    const open = e.target.closest("[data-dp-open]");
    if (open) {
      e.preventDefault();
      this.mode = open.dataset.dpOpen;
      this.renderCalendar();
      return;
    }

    // Year selection
    const yr = e.target.closest("[data-dp-year]");
    if (yr && !yr.disabled) {
      e.preventDefault();
      this.viewYear = parseInt(yr.dataset.dpYear, 10);
      if (this.viewMonth > this.maxMonthFor(this.viewYear)) this.viewMonth = this.maxMonthFor(this.viewYear);
      this.mode = "days";
      this.renderCalendar();
      return;
    }

    // Month selection
    const mo = e.target.closest("[data-dp-month]");
    if (mo && !mo.disabled) {
      e.preventDefault();
      this.viewMonth = parseInt(mo.dataset.dpMonth, 10);
      this.mode = "days";
      this.renderCalendar();
      return;
    }

    // Day selection
    const day = e.target.closest("[data-dp-day]");
    if (day && !day.disabled) {
      e.preventDefault();
      this.selected = new Date(this.viewYear, this.viewMonth, parseInt(day.dataset.dpDay, 10));
      this.selected.setHours(0,0,0,0);
      this.input.value = this.iso(this.selected);
      this.input.dispatchEvent(new Event("input", { bubbles: true }));
      this.input.dispatchEvent(new Event("change", { bubbles: true }));
      this.renderDisplay();
      this.close();
    }
  }

  maxMonthFor(year) {
    return (this.max && year === this.max.getFullYear()) ? this.max.getMonth() : 11;
  }

  renderCalendar() {
    if (this.mode === "years") return this.renderYears();
    if (this.mode === "months") return this.renderMonths();
    this.renderDays();
  }

  listHeader(label) {
    return `<div style="display:flex;align-items:center;gap:4px;margin-bottom:12px;">
      <button type="button" data-dp-open="days" aria-label="Back to days" class="cal-nav-btn">&#8249;</button>
      <span style="flex:1;text-align:center;font-size:14px;font-weight:600;">${label}</span>
      <span style="width:32px;"></span>
    </div>`;
  }

  renderDays() {
    const first = new Date(this.viewYear, this.viewMonth, 1);
    const startDow = first.getDay();
    const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate();

    let head = `
      <div style="display:flex;align-items:center;gap:6px;margin-bottom:12px;">
        <button type="button" data-dp-nav="-1" aria-label="Previous month" class="cal-nav-btn">&#8249;</button>
        <button type="button" data-dp-open="months" class="cal-select-trigger" style="flex:1;">
          <span>${MONTHS[this.viewMonth]}</span><span class="opacity-50">&#9662;</span>
        </button>
        <button type="button" data-dp-open="years" class="cal-select-trigger">
          <span>${this.viewYear}</span><span class="opacity-50">&#9662;</span>
        </button>
        <button type="button" data-dp-nav="1" aria-label="Next month" class="cal-nav-btn">&#8250;</button>
      </div>`;

    let dow = `<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;margin-bottom:6px;">`;
    DOW.forEach(d => { dow += `<span style="text-align:center;font-size:12px;font-weight:500;" class="text-muted">${d}</span>`; });
    dow += `</div>`;

    let grid = `<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;">`;
    for (let i = 0; i < startDow; i++) grid += `<span></span>`;
    
    for (let d = 1; d <= daysInMonth; d++) {
      const cur = new Date(this.viewYear, this.viewMonth, d);
      cur.setHours(0,0,0,0);
      const isSel = this.selected && cur.getTime() === this.selected.getTime();
      const isToday = cur.getTime() === this.today.getTime();
      const disabled = this.max && cur.getTime() > this.max.getTime();

      let classes = ["cal-day-cell"];
      if (isSel) classes.push("is-selected");
      if (isToday) classes.push("is-today");

      grid += `<button type="button" data-dp-day="${d}" ${disabled ? "disabled" : ""} class="${classes.join(" ")}">${d}</button>`;
    }
    grid += `</div>`;

    this.body.innerHTML = head + dow + grid;
  }

  renderMonths() {
    let head = this.listHeader("Select month");
    let grid = `<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px;">`;
    const maxMonth = this.maxMonthFor(this.viewYear);
    
    MONTHS.forEach((name, i) => {
      const isSel = i === this.viewMonth;
      const disabled = i > maxMonth;
      let classes = ["cal-month-cell"];
      if (isSel) classes.push("is-selected");
      
      grid += `<button type="button" data-dp-month="${i}" ${disabled ? "disabled" : ""} class="${classes.join(" ")}">${name.slice(0,3)}</button>`;
    });
    grid += `</div>`;
    this.body.innerHTML = head + grid;
  }

  renderYears() {
    let head = this.listHeader("Select year");
    let grid = `<div data-dp-years class="cal-years-grid">`;
    
    for (let y = this.maxYear(); y >= this.minYear(); y--) {
      const isSel = y === this.viewYear;
      let classes = ["cal-year-cell"];
      if (isSel) classes.push("is-selected");
      grid += `<button type="button" data-dp-year="${y}" class="${classes.join(" ")}">${y}</button>`;
    }
    grid += `</div>`;
    this.body.innerHTML = head + grid;

    const container = this.pop.querySelector("[data-dp-years]");
    const sel = this.pop.querySelector(`[data-dp-year="${this.viewYear}"]`);
    if (container && sel) {
      container.scrollTop = sel.offsetTop - container.clientHeight / 2 + sel.clientHeight / 2;
    }
  }
}

Hooks.DatePicker = {
  mounted() {
    this.picker = new CustomDatePicker(this.el)
  },
  updated() {
    if (this.picker) {
      this.picker.initToday()
      this.picker.parseValue()
    }
  },
  destroyed() {
    if (this.picker) {
      this.picker.destroy()
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
  uploaders: {R2: R2Uploader}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
