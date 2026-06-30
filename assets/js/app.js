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

      player.addEventListener("loadedmetadata", () => {
        const startPosition = Number(this.el.dataset.startPosition || 0)

        if (startPosition > 0 && startPosition < player.duration) {
          player.currentTime = startPosition
        }
      })

      player.addEventListener("timeupdate", () => {
        const now = Date.now()

        if (
          player.currentTime - this.lastSavedPosition >= 10 ||
          now - this.lastSaveAt >= 15000
        ) {
          this.saveProgress()
        }
      })

      player.addEventListener("ended", () => {
        this.pushEvent("complete-lecture", {lecture_id: this.el.dataset.lectureId})
      })

      this.playerHost.replaceChildren(player)
    } catch (error) {
      if (error.name === "AbortError") return
      this.playerHost.textContent = "This protected video is temporarily unavailable."
      console.error(error)
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

Hooks.MuxUpload = {
  mounted() {
    this.fileInput = this.el.querySelector("[data-role='file']")
    this.startButton = this.el.querySelector("[data-role='start']")
    this.progress = this.el.querySelector("[data-role='progress']")
    // When the widget lives inside a LiveComponent (e.g. the lecture form
    // modal) it sets data-target so events reach the component, not the view.
    this.uploadTarget = this.el.getAttribute("data-target")

    this.startButton.addEventListener("click", () => {
      if (!this.fileInput.files[0]) {
        this.fileInput.setCustomValidity("Choose a video file first.")
        this.fileInput.reportValidity()
        return
      }

      this.fileInput.setCustomValidity("")
      this.startButton.disabled = true
      this.pushUp("create-upload", {
        filename: this.fileInput.files[0].name,
        content_type: this.fileInput.files[0].type,
        size: this.fileInput.files[0].size
      })
    })

    this.handleEvent("mux-upload-ready", ({url}) => this.upload(url))
    this.handleEvent("mux-check-upload", () => {
      window.clearTimeout(this.statusTimer)
      this.statusTimer = window.setTimeout(() => this.pushUp("check-upload", {}), 3000)
    })
  },

  destroyed() {
    this.request?.abort()
    window.clearTimeout(this.statusTimer)
  },

  pushUp(event, payload) {
    if (this.uploadTarget) {
      this.pushEventTo(this.uploadTarget, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  },

  upload(url) {
    const file = this.fileInput.files[0]
    const request = new XMLHttpRequest()
    this.request = request

    request.upload.addEventListener("progress", event => {
      if (!event.lengthComputable) return
      this.progress.style.width = `${Math.round((event.loaded / event.total) * 100)}%`
    })

    request.addEventListener("load", () => {
      if (request.status >= 200 && request.status < 300) {
        this.progress.style.width = "100%"
        this.pushUp("upload-complete", {})
      } else {
        this.startButton.disabled = false
        console.error(`Mux upload failed (${request.status})`)
      }
    })

    request.addEventListener("error", () => {
      this.startButton.disabled = false
      console.error("Mux upload failed because of a network error")
    })

    request.open("PUT", url)
    request.setRequestHeader("Content-Type", file.type || "application/octet-stream")
    request.send(file)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
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
