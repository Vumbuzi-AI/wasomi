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
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import Chart from "chart.js/auto";

const Hooks = {};

const R2Uploader = (entries, onViewError) => {
  entries.forEach((entry) => {
    const request = new XMLHttpRequest();
    entry.xhr = request;

    // LiveView calls this cleanup callback if the owning view goes away.
    // Passing an error message here (as the old implementation did) throws
    // inside the uploader and leaves failed uploads displayed at 0% forever.
    onViewError(() => request.abort());

    const fail = (reason) => {
      console.error(`R2 upload failed: ${reason}`);
      entry.error(reason);
    };

    request.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable)
        entry.progress(Math.round((event.loaded / event.total) * 100));
    });
    request.addEventListener("load", () => {
      if (request.status >= 200 && request.status < 300) {
        entry.progress(100);
      } else {
        fail(`HTTP ${request.status}`);
      }
    });
    request.addEventListener("error", () =>
      fail("network error or blocked CORS request"),
    );
    request.addEventListener("timeout", () => fail("request timed out"));
    request.timeout = 120_000;
    request.open("PUT", entry.meta.url);
    request.setRequestHeader(
      "Content-Type",
      entry.meta.content_type || entry.file.type,
    );
    request.send(entry.file);
  });
};

const SIDEBAR_COLLAPSED_KEY_PREFIX = "sidebar-collapsed:";

// Shared by both the admin and learner sidebars — finds its own `.app-sidebar`
// ancestor rather than a hardcoded id, and persists collapsed state per
// sidebar (keyed by that sidebar's own DOM id) so toggling one doesn't
// affect the other.
Hooks.SidebarToggle = {
  mounted() {
    const sidebar = this.el.closest(".app-sidebar");
    if (!sidebar) return;

    const storageKey = SIDEBAR_COLLAPSED_KEY_PREFIX + (sidebar.id || "default");

    const setTitle = (isCollapsed) => {
      this.el.title = isCollapsed ? "Expand sidebar" : "Collapse sidebar";
    };

    const collapsed = localStorage.getItem(storageKey) === "true";
    sidebar.classList.toggle("is-collapsed", collapsed);
    setTitle(collapsed);

    this.el.addEventListener("click", () => {
      const isCollapsed = sidebar.classList.toggle("is-collapsed");
      localStorage.setItem(storageKey, isCollapsed);
      setTitle(isCollapsed);
    });
  },
};

// URL patches preserve scroll position. Reset the Study Hub's scrolling main
// only when a navigation key changes, so a long previous screen cannot leave a
// shorter replacement clipped while ordinary form updates stay put.
Hooks.ScrollContainerOnKeyChange = {
  mounted() {
    this.scrollKey = this.el.dataset.scrollKey;
  },
  updated() {
    const nextKey = this.el.dataset.scrollKey;
    if (nextKey === this.scrollKey) return;

    this.scrollKey = nextKey;
    window.requestAnimationFrame(() => {
      const container = this.el.closest("main");
      if (container) container.scrollTo({ top: 0, left: 0 });
    });
  },
};

Hooks.SortableList = {
  mounted() {
    this.draggedItem = null;
    this.startOrder = this.order();

    this.onPointerDown = (event) => {
      const handle = event.target.closest("[data-sortable-handle]");
      if (!handle) return;

      const item = this.itemFor(handle);
      if (!item) return;

      item.draggable = true;
    };

    this.onPointerUp = () => {
      if (this.draggedItem) return;
      this.items().forEach((item) => (item.draggable = false));
    };

    this.onDragStart = (event) => {
      const item = this.itemFor(event.target);
      if (!item) return;

      this.draggedItem = item;
      this.startOrder = this.order();
      item.dataset.dragging = "true";
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", item.dataset.id);
    };

    this.onDragOver = (event) => {
      if (!this.draggedItem) return;

      const target = this.itemFor(event.target);
      if (!target || target === this.draggedItem) return;

      event.preventDefault();
      event.dataTransfer.dropEffect = "move";

      const targetRect = target.getBoundingClientRect();
      const insertAfter =
        event.clientY > targetRect.top + targetRect.height / 2;
      this.items().forEach((item) => delete item.dataset.dragOver);
      target.dataset.dragOver = "true";

      this.el.insertBefore(
        this.draggedItem,
        insertAfter ? target.nextElementSibling : target,
      );
    };

    this.onDragLeave = (event) => {
      const item = this.itemFor(event.target);
      if (item) delete item.dataset.dragOver;
    };

    this.onDrop = (event) => {
      if (!this.draggedItem) return;
      event.preventDefault();
      this.persistOrder();
    };

    this.onDragEnd = () => {
      this.items().forEach((item) => {
        item.draggable = false;
        delete item.dataset.dragging;
        delete item.dataset.dragOver;
      });

      if (this.draggedItem) this.persistOrder();
      this.draggedItem = null;
    };

    this.el.addEventListener("pointerdown", this.onPointerDown);
    document.addEventListener("pointerup", this.onPointerUp);
    this.el.addEventListener("dragstart", this.onDragStart);
    this.el.addEventListener("dragover", this.onDragOver);
    this.el.addEventListener("dragleave", this.onDragLeave);
    this.el.addEventListener("drop", this.onDrop);
    this.el.addEventListener("dragend", this.onDragEnd);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown);
    document.removeEventListener("pointerup", this.onPointerUp);
    this.el.removeEventListener("dragstart", this.onDragStart);
    this.el.removeEventListener("dragover", this.onDragOver);
    this.el.removeEventListener("dragleave", this.onDragLeave);
    this.el.removeEventListener("drop", this.onDrop);
    this.el.removeEventListener("dragend", this.onDragEnd);
  },

  items() {
    return Array.from(
      this.el.querySelectorAll(":scope > [data-sortable-item]"),
    );
  },

  itemFor(element) {
    const item = element.closest("[data-sortable-item]");
    return item?.parentElement === this.el ? item : null;
  },

  order() {
    return this.items().map((item) => item.dataset.id);
  },

  persistOrder() {
    const order = this.order();
    if (order.join(",") === this.startOrder.join(",")) return;

    const payload = {
      [this.el.dataset.orderKey || "ids"]: order,
    };

    if (this.el.dataset.parentKey) {
      payload[this.el.dataset.parentKey] = this.el.dataset.parentId;
    }

    this.startOrder = order;
    this.pushEvent(this.el.dataset.event, payload);
  },
};

// No browser API can block an OS screenshot or a screen recorder, so course
// content is defended on the only two axes the web actually gives us:
//
//   * Deterrence — remove the *easy* copies (right-click save, Ctrl+C on the
//     transcript, Ctrl+P to PDF, a screenshot of a paused frame while the
//     learner is on another tab).
//   * Traceability — stamp every rendered pixel with the viewer's identity so
//     a leaked capture is attributable to one account.
//
// Anything stronger requires hardware DRM (Widevine L1 / PlayReady SL3000 /
// FairPlay), which blacks out the video surface in OS-level captures. Cloudflare
// Stream — our current provider — does not offer it, so it is out of scope here.

// Blocks the shortcut-level copy paths and reports attempts. Returns a
// teardown function; every listener is registered on `document` because the
// key handling has to win before the browser's own default runs.
const guardCaptureShortcuts = (report) => {
  const isEditable = (node) =>
    node instanceof HTMLElement &&
    (node.isContentEditable ||
      ["INPUT", "TEXTAREA", "SELECT"].includes(node.tagName));

  const blockUnlessEditing = (event) => {
    // Learners type free-text answers into the practice questions, so copy and
    // selection stay available inside form fields — only lesson content is locked.
    if (isEditable(event.target)) return;
    event.preventDefault();
  };

  const onCopy = (event) => {
    if (isEditable(event.target)) return;
    event.preventDefault();
    report("copy");
  };

  const onKeyDown = (event) => {
    if (typeof event.key !== "string") return;
    const meta = event.metaKey || event.ctrlKey;

    // Ctrl/Cmd+P and Ctrl/Cmd+S turn the lesson into a portable file in one
    // keystroke; the print blackout in app.css covers the menu-driven route.
    if (meta && ["p", "s"].includes(event.key.toLowerCase())) {
      event.preventDefault();
      report(`shortcut:${event.key.toLowerCase()}`);
    }
  };

  // PrintScreen fires *after* Windows has already captured, so this cannot
  // prevent the screenshot — overwriting the clipboard only denies the
  // paste-straight-into-chat path, and the report is the real value.
  const onKeyUp = (event) => {
    if (event.key !== "PrintScreen") return;
    navigator.clipboard?.writeText?.("").catch(() => {});
    report("printscreen");
  };

  const listeners = [
    ["contextmenu", blockUnlessEditing],
    ["dragstart", blockUnlessEditing],
    ["selectstart", blockUnlessEditing],
    ["copy", onCopy],
    ["cut", onCopy],
    ["keydown", onKeyDown],
    ["keyup", onKeyUp],
  ];

  listeners.forEach(([event, handler]) =>
    document.addEventListener(event, handler, true),
  );

  return () =>
    listeners.forEach(([event, handler]) =>
      document.removeEventListener(event, handler, true),
    );
};

// Wraps a protected surface: the learner workspace (video, transcript,
// resources and quizzes) and the study hub.
Hooks.CaptureGuard = {
  mounted() {
    this.lastReportAt = 0;
    // The CSS half of the guard (selection blocking, print blackout) keys off
    // this class, so it is applied here rather than server-side: the rules only
    // ever make sense when this hook is live to back them up.
    this.el.classList.add("capture-guarded");
    this.teardownGuards = guardCaptureShortcuts((kind) => this.report(kind));
  },

  destroyed() {
    this.teardownGuards?.();
  },

  // Throttled: a learner leaning on Ctrl+C should produce one audit line, not
  // a flood that drowns the log it is meant to make readable.
  report(kind) {
    const now = Date.now();
    if (now - this.lastReportAt < 5000) return;

    this.lastReportAt = now;
    this.pushEvent("capture-attempt", { kind });
  },
};

// The lesson player draws its own controls instead of handing the learner the
// browser's. Two reasons: native chrome offers a scrub bar that invites
// skipping ahead, which the seek clamp then silently undoes — reading as a
// broken player — and it has nowhere to say *why* the un-watched stretch is out
// of reach. These controls paint that stretch as locked and explain themselves
// when someone reaches for it.
const SEEK_TOLERANCE = 0.5;
const SKIP_LOCKED_MESSAGE =
  "No skipping ahead — keep watching to unlock the rest of this lesson.";
const SPEED_LOCKED_MESSAGE =
  "Playback speed unlocks once you have watched this lesson through.";
const CONTROL_BUTTON_CLASS =
  "grid h-9 w-9 shrink-0 place-items-center rounded-full text-white/90 outline-none transition hover:bg-white/15 hover:text-white focus-visible:ring-2 focus-visible:ring-primary";
const CONTROL_SELECT_CLASS =
  "cursor-pointer rounded-lg border border-white/20 bg-black/60 px-2 py-1 text-[11px] font-semibold text-white outline-none transition hover:border-white/40 focus-visible:ring-2 focus-visible:ring-primary disabled:cursor-not-allowed disabled:opacity-40";

const PLAYER_ICONS = {
  play: {
    filled: true,
    body: `<path d="M8.25 4.94v14.12c0 .81.88 1.31 1.57.89l11.02-6.94a1.05 1.05 0 0 0 0-1.78L9.82 4.05a1.05 1.05 0 0 0-1.57.89Z"/>`,
  },
  pause: {
    filled: true,
    body: `<rect x="7" y="4.5" width="3.4" height="15" rx="1.3"/><rect x="13.6" y="4.5" width="3.4" height="15" rx="1.3"/>`,
  },
  rewind: { body: `<path d="M9 15 3 9m0 0 6-6M3 9h12a6 6 0 0 1 0 12h-3"/>` },
  forward: { body: `<path d="m15 15 6-6m0 0-6-6m6 6H9a6 6 0 0 0 0 12h3"/>` },
  lock: {
    body: `<path d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75M6.75 21.75h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z"/>`,
  },
  volume: {
    body: `<path d="M19.114 5.636a9 9 0 0 1 0 12.728M16.463 8.288a5.25 5.25 0 0 1 0 7.424M6.75 8.25l4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.01 9.01 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z"/>`,
  },
  muted: {
    body: `<path d="M17.25 9.75 19.5 12m0 0 2.25 2.25M19.5 12l2.25-2.25M19.5 12l-2.25 2.25M6.75 8.25l4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.01 9.01 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z"/>`,
  },
  fullscreen: {
    body: `<path d="M3.75 8.25v-4.5h4.5M3.75 3.75 9 9M3.75 15.75v4.5h4.5M3.75 20.25 9 15M20.25 8.25v-4.5h-4.5M20.25 3.75 15 9M20.25 15.75v4.5h-4.5M20.25 20.25 15 15"/>`,
  },
  exitFullscreen: {
    body: `<path d="M9 9V4.5M9 9H4.5M9 9 3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5 5.25 5.25"/>`,
  },
};

function playerIcon(name, sizeClass = "h-5 w-5") {
  const icon = PLAYER_ICONS[name];
  const paint = icon.filled
    ? `fill="currentColor"`
    : `fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"`;

  return `<svg viewBox="0 0 24 24" ${paint} aria-hidden="true" class="${sizeClass}">${icon.body}</svg>`;
}

function formatMediaTime(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";

  const whole = Math.floor(seconds);
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor(whole / 60) % 60;
  const secs = String(whole % 60).padStart(2, "0");

  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${secs}`
    : `${minutes}:${secs}`;
}

Hooks.ProtectedVideo = {
  mounted() {
    this.playerHost = this.el.querySelector("[data-role='player']");
    this.watermark = this.el.querySelector("[data-role='watermark']");
    this.abortController = new AbortController();
    this.veil = this.buildVeil();
    this.buffering = false;
    // Shortcuts are scoped to the player rather than the document: the lesson
    // page also hosts quiz inputs and a transcript, and space/arrow keys belong
    // to whatever the learner is actually focused on.
    this.el.tabIndex = 0;
    this.el.classList.add("outline-none");
    this.onKeydown = (event) => this.handleKeydown(event);
    this.el.addEventListener("keydown", this.onKeydown);
    // Fullscreen is taken on the whole container, not the <video>, so the
    // identity watermark and these controls travel with the frame.
    this.onFullscreenChange = () => this.handleFullscreenChange();
    document.addEventListener("fullscreenchange", this.onFullscreenChange);

    this.el.addEventListener("contextmenu", (event) => event.preventDefault());
    // Resize is applied once real metadata loads (see applyAspectRatio); transition
    // keeps that resize from feeling like a jump once the 16:9 placeholder is replaced.
    this.el.style.transition =
      "aspect-ratio 300ms ease-out, width 300ms ease-out, height 300ms ease-out";
    this.loadPlayer();
    this.moveWatermark();
    this.watermarkTimer = window.setInterval(() => this.moveWatermark(), 8000);
    this.stampTimer = window.setInterval(() => this.stampWatermark(), 1000);

    // A recorder is usually driven from another window, and a screenshot tool
    // takes focus before it fires. Pausing and covering the frame the moment
    // this tab stops being the active one means the capture lands on the veil,
    // not on lesson content. Balanced deliberately: only a *hidden* tab pauses,
    // so a learner alt-tabbing to take notes keeps their audio.
    this.onVisibility = () => {
      if (document.visibilityState === "hidden") this.player?.pause();
      this.setVeiled(document.visibilityState === "hidden");
    };
    document.addEventListener("visibilitychange", this.onVisibility);
  },

  destroyed() {
    this.saveProgress?.();
    this.abortController?.abort();
    this.hls?.destroy();
    window.clearInterval(this.watermarkTimer);
    window.clearInterval(this.stampTimer);
    window.clearTimeout(this.hideChromeTimer);
    window.clearTimeout(this.noticeTimer);
    document.removeEventListener("visibilitychange", this.onVisibility);
    document.removeEventListener("fullscreenchange", this.onFullscreenChange);
    this.el.removeEventListener("keydown", this.onKeydown);
  },

  buildVeil() {
    const veil = document.createElement("div");
    veil.dataset.role = "veil";
    veil.className =
      "pointer-events-none absolute inset-0 z-40 hidden place-items-center bg-dark text-center text-xs font-semibold text-white/70";
    veil.textContent = "Paused — return to this tab to keep watching.";
    this.el.append(veil);
    return veil;
  },

  setVeiled(veiled) {
    this.veil.classList.toggle("hidden", !veiled);
    this.veil.classList.toggle("grid", veiled);
  },

  // Re-stamps the in-frame watermark so a capture cropped to just the video
  // still carries who was watching and when.
  stampWatermark() {
    if (!this.watermark) return;

    const identity = this.el.dataset.watermark;
    if (!identity) return;

    this.watermark.textContent = `${identity} · ${new Date().toISOString().slice(0, 19).replace("T", " ")}`;
  },

  async loadPlayer() {
    try {
      const response = await fetch(this.el.dataset.playbackUrl, {
        credentials: "same-origin",
        headers: { accept: "application/json" },
        signal: this.abortController.signal,
      });

      if (!response.ok)
        throw new Error(`Playback authorization failed (${response.status})`);

      const { url } = await response.json();
      const player = document.createElement("video");
      // Native controls stay off: buildChrome() below replaces them with a bar
      // that can express the no-skipping rule instead of fighting it.
      player.controls = false;
      player.playsInline = true;
      player.preload = "metadata";
      // Refuse picture-in-picture and AirPlay/Cast: each renders the frame
      // outside our watermarked container, where the identity stamp no longer
      // travels with the pixels. controlslist still matters for the iOS native
      // fullscreen player, which we cannot skin.
      player.setAttribute("controlslist", "nodownload noplaybackrate");
      player.disablePictureInPicture = true;
      player.disableRemotePlayback = true;
      const playerFrame = document.createElement("div");
      playerFrame.className = "relative h-full w-full";

      // Only an HLS manifest needs hls.js; a progressive file (e.g. the
      // seeded .mp4 samples) plays natively everywhere and would break
      // hls.js if handed to it.
      const isHls = new URL(url, window.location.origin).pathname.endsWith(
        ".m3u8",
      );

      if (!isHls) {
        player.src = url;
        player.textTracks.addEventListener?.("addtrack", () =>
          this.updateNativeCaptionOptions(),
        );
      } else if (window.Hls?.isSupported()) {
        this.hls = new window.Hls();
        this.hls.on(window.Hls.Events.MANIFEST_PARSED, () =>
          this.updateQualityOptions(),
        );
        this.hls.on(window.Hls.Events.LEVEL_SWITCHED, () =>
          this.syncQualitySelection(),
        );
        this.hls.on(window.Hls.Events.SUBTITLE_TRACKS_UPDATED, () =>
          this.updateCaptionOptions(),
        );
        this.hls.on(window.Hls.Events.SUBTITLE_TRACK_SWITCH, () =>
          this.syncCaptionSelection(),
        );
        this.hls.loadSource(url);
        this.hls.attachMedia(player);
      } else if (player.canPlayType("application/vnd.apple.mpegurl")) {
        player.src = url;
        player.textTracks.addEventListener?.("addtrack", () =>
          this.updateNativeCaptionOptions(),
        );
      } else {
        throw new Error("HLS playback is not supported by this browser");
      }
      player.style.width = "100%";
      player.style.height = "100%";
      // Letterbox non-16:9 sources instead of stretching them to fill the frame.
      player.style.objectFit = "contain";

      this.player = player;
      this.preview = this.el.dataset.preview === "true";
      // An admin previewing a course is reviewing content, not consuming a
      // lesson, so the no-skipping rule does not apply to them. Same for a
      // lecture the learner has already completed: a review pass scrubs freely.
      this.freeSeek = this.preview || this.el.dataset.seekUnlocked === "true";
      this.previewPositionKey = `wasomi-preview-position:${this.el.dataset.viewerId}:${this.el.dataset.lectureId}`;
      const serverPosition = Number(this.el.dataset.startPosition || 0);
      const localPreviewPosition = this.preview
        ? Number(window.localStorage.getItem(this.previewPositionKey) || 0)
        : 0;
      const resumePosition = Math.max(serverPosition, localPreviewPosition);

      this.lastSavedPosition = serverPosition;
      this.lastSaveAt = 0;
      // Furthest position actually played, updated every tick (unthrottled).
      this.furthestWatched = resumePosition;

      const chrome = this.buildChrome();
      this.applyStoredVolume();

      player.addEventListener("loadedmetadata", () => {
        if (resumePosition > 0 && resumePosition < player.duration) {
          player.currentTime = resumePosition;
        }

        this.applyAspectRatio(player.videoWidth, player.videoHeight);
        if (!this.hls) this.updateNativeCaptionOptions();
        this.syncChrome();
      });

      player.addEventListener("timeupdate", () => {
        this.furthestWatched = Math.max(
          this.furthestWatched,
          player.currentTime,
        );

        if (this.preview) {
          window.localStorage.setItem(
            this.previewPositionKey,
            String(Math.max(0, Math.floor(player.currentTime))),
          );
        }

        const now = Date.now();

        if (
          player.currentTime - this.lastSavedPosition >= 10 ||
          now - this.lastSaveAt >= 15000
        ) {
          this.saveProgress();
        }

        this.syncChrome();
      });

      // A pause often means the learner is about to navigate away. Save the
      // exact checkpoint instead of waiting for the next periodic timeupdate.
      player.addEventListener("pause", () => this.saveProgress());

      ["play", "pause", "volumechange", "progress", "durationchange"].forEach(
        (event) => player.addEventListener(event, () => this.syncChrome()),
      );
      player.addEventListener("play", () => this.scheduleHideChrome());
      player.addEventListener("waiting", () => this.setBuffering(true));
      ["playing", "canplay", "seeked", "pause"].forEach((event) =>
        player.addEventListener(event, () => this.setBuffering(false)),
      );

      // Speeding a lecture up is skipping ahead by another name, so the rate is
      // pinned to 1x until the lesson has been watched through. This is the
      // backstop for the console as much as for the speed menu.
      player.addEventListener("ratechange", () => {
        if (this.skipLocked() && player.playbackRate > 1) {
          player.playbackRate = 1;
          this.flashNotice(SPEED_LOCKED_MESSAGE);
        }

        if (this.speedSelect) {
          this.speedSelect.select.value = String(player.playbackRate);
        }
      });

      // Backstop for the clamp the controls already enforce: catches a seek that
      // never went through them at all — the iOS native fullscreen scrubber, a
      // media-key gesture, or a console poke. Tolerance absorbs rounding only.
      player.addEventListener("seeking", () => {
        const limit = this.seekLimit();

        if (player.currentTime > limit + SEEK_TOLERANCE) {
          player.currentTime = limit;
          this.flashNotice();
        }
      });

      player.addEventListener("ended", () => {
        if (this.preview) {
          window.localStorage.removeItem(this.previewPositionKey);
        }

        // The lesson has been watched end to end, so scrubbing opens up for the
        // rewatch that usually follows.
        this.freeSeek = true;
        this.showChrome();
        // Flush final position so mark_complete's watch-threshold check sees it.
        this.saveProgress();
        this.pushEvent("complete-lecture", {
          lecture_id: this.el.dataset.lectureId,
        });
      });

      playerFrame.append(player, chrome);
      this.playerHost.replaceChildren(playerFrame);
      this.syncChrome();
    } catch (error) {
      if (error.name === "AbortError") return;
      this.playerHost.textContent =
        "This protected video is temporarily unavailable.";
      console.error(error);
    }
  },

  // ── Seek gating ──────────────────────────────────────────────────────────
  // Everything that can move the playhead goes through requestSeek, and
  // seekLimit is the single answer to "how far ahead may this learner jump".

  duration() {
    const duration = this.player?.duration;
    return Number.isFinite(duration) && duration > 0 ? duration : 0;
  },

  // Never past the furthest point actually played, so the only way through a
  // lecture is to watch it. Rewinding stays free — re-listening to a passage is
  // the opposite of the problem this guards.
  seekLimit() {
    const duration = this.duration();
    if (!duration) return 0;
    if (this.freeSeek || this.furthestWatched >= duration - 1.5)
      return duration;

    return this.furthestWatched;
  },

  skipLocked() {
    const duration = this.duration();
    return duration > 0 && this.seekLimit() < duration - SEEK_TOLERANCE;
  },

  requestSeek(time) {
    if (!this.player || !this.duration()) return;

    const limit = this.seekLimit();
    const target = Math.max(0, Math.min(time, limit));
    // A clamped forward jump still lands where the learner has earned — the
    // notice explains why it stopped short of where they clicked.
    if (time > limit + SEEK_TOLERANCE) this.flashNotice();

    this.player.currentTime = target;
    this.syncChrome();
  },

  nudge(delta) {
    if (!this.player) return;
    this.requestSeek(this.player.currentTime + delta);
    this.showChrome();
  },

  togglePlay() {
    if (!this.player) return;

    if (this.player.paused || this.player.ended) {
      this.player.play().catch(() => {});
    } else {
      this.player.pause();
    }

    this.showChrome();
  },

  toggleMute() {
    if (!this.player) return;
    // Unmuting a player left at zero volume would stay silent and read as
    // broken, so it comes back at a usable level.
    if (this.player.muted && this.player.volume === 0) this.setVolume(0.6);
    this.player.muted = !this.player.muted;
    this.persistVolume();
    this.showChrome();
  },

  setVolume(value) {
    if (!this.player) return;

    const volume = Math.min(1, Math.max(0, value));
    this.player.volume = volume;
    this.player.muted = volume === 0;
    this.persistVolume();
    this.showChrome();
  },

  persistVolume() {
    window.localStorage.setItem(
      "wasomi-video-volume",
      String(this.player.volume),
    );
    window.localStorage.setItem(
      "wasomi-video-muted",
      String(this.player.muted),
    );
  },

  applyStoredVolume() {
    const stored = Number(
      window.localStorage.getItem("wasomi-video-volume") ?? 1,
    );
    this.player.volume = Number.isFinite(stored)
      ? Math.min(1, Math.max(0, stored))
      : 1;
    this.player.muted =
      window.localStorage.getItem("wasomi-video-muted") === "true";
  },

  toggleFullscreen() {
    if (document.fullscreenElement === this.el) {
      document.exitFullscreen?.();
    } else if (this.el.requestFullscreen) {
      this.el.requestFullscreen().catch(() => {});
    } else if (this.player?.webkitEnterFullscreen) {
      // iOS Safari only fullscreens the media element itself, so the learner
      // gets Apple's controls there. The seeking backstop above still holds.
      this.player.webkitEnterFullscreen();
    }
  },

  handleFullscreenChange() {
    // applyAspectRatio's sizing is for the in-page frame; fullscreen wants the
    // whole viewport, with the video letterboxed inside it.
    if (document.fullscreenElement === this.el) {
      this.el.style.aspectRatio = "auto";
      this.el.style.width = "100%";
      this.el.style.maxWidth = "none";
      this.el.style.height = "100%";
    } else if (this.player) {
      this.applyAspectRatio(this.player.videoWidth, this.player.videoHeight);
    }

    this.showChrome();
  },

  handleKeydown(event) {
    if (!this.player) return;
    // Let the caption/quality/speed menus and the volume slider keep their own
    // arrow-key behaviour.
    if (
      event.target instanceof HTMLSelectElement ||
      event.target instanceof HTMLInputElement
    ) {
      return;
    }

    switch (event.key.toLowerCase()) {
      case " ":
      case "k":
        this.togglePlay();
        break;
      case "arrowleft":
      case "j":
        this.nudge(-10);
        break;
      case "arrowright":
      case "l":
        this.nudge(10);
        break;
      case "arrowup":
        this.setVolume(this.player.volume + 0.1);
        break;
      case "arrowdown":
        this.setVolume(this.player.volume - 0.1);
        break;
      case "m":
        this.toggleMute();
        break;
      case "f":
        this.toggleFullscreen();
        break;
      default:
        return;
    }

    event.preventDefault();
  },

  // ── Controls ─────────────────────────────────────────────────────────────

  buildChrome() {
    const chrome = document.createElement("div");
    chrome.dataset.role = "chrome";
    chrome.className = "absolute inset-0 z-30";
    // Clicking the picture toggles playback and double-click goes fullscreen,
    // matching what every learner already expects from a video. Guarded on
    // target so a click on a button is not also a play/pause.
    chrome.addEventListener("click", (event) => {
      if (event.target === chrome) this.togglePlay();
    });
    chrome.addEventListener("dblclick", (event) => {
      if (event.target === chrome) this.toggleFullscreen();
    });
    chrome.addEventListener("pointermove", () => this.showChrome());
    chrome.addEventListener("pointerleave", () => this.scheduleHideChrome());

    this.centerButton = this.buildIconButton("play", "Play", () =>
      this.togglePlay(),
    );
    this.centerButton.className =
      "absolute left-1/2 top-1/2 grid h-16 w-16 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-black/55 text-white shadow-xl outline-none backdrop-blur-sm transition hover:scale-105 hover:bg-black/70 focus-visible:ring-2 focus-visible:ring-primary";
    this.centerButton.innerHTML = playerIcon("play", "h-7 w-7 translate-x-0.5");

    this.spinner = document.createElement("div");
    this.spinner.className =
      "pointer-events-none absolute left-1/2 top-1/2 hidden h-12 w-12 -translate-x-1/2 -translate-y-1/2 animate-spin rounded-full border-2 border-white/25 border-t-primary";

    this.controlBar = document.createElement("div");
    this.controlBar.className =
      "absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/60 to-transparent px-3 pb-2.5 pt-12 transition-opacity duration-200 sm:px-4";
    this.controlBar.addEventListener("pointerenter", () => {
      this.pointerOnBar = true;
      this.showChrome();
    });
    this.controlBar.addEventListener("pointerleave", () => {
      this.pointerOnBar = false;
      this.scheduleHideChrome();
    });

    this.notice = document.createElement("p");
    this.notice.dataset.role = "notice";
    this.notice.setAttribute("role", "status");
    // Sits in the bar's transparent gradient band, above the scrubber: close to
    // the control that was just refused, and never clipped by the frame edge.
    this.notice.className =
      "pointer-events-none absolute left-1/2 top-1 w-max max-w-[min(22rem,90%)] -translate-x-1/2 rounded-xl bg-dark/95 px-3.5 py-2 text-center text-xs font-semibold text-white opacity-0 shadow-lg transition-opacity duration-200";

    this.controlBar.append(this.notice, this.buildScrubber(), this.buildRow());
    chrome.append(this.centerButton, this.spinner, this.controlBar);
    this.chrome = chrome;

    return chrome;
  },

  buildRow() {
    const row = document.createElement("div");
    row.className = "mt-0.5 flex items-center gap-1 sm:gap-1.5";

    this.playButton = this.buildIconButton("play", "Play", () =>
      this.togglePlay(),
    );
    this.rewindButton = this.buildIconButton("rewind", "Back 10 seconds", () =>
      this.nudge(-10),
    );
    this.forwardButton = this.buildIconButton(
      "forward",
      "Forward 10 seconds",
      () => this.nudge(10),
    );

    const volume = document.createElement("div");
    volume.className = "flex items-center";
    this.muteButton = this.buildIconButton("volume", "Mute", () =>
      this.toggleMute(),
    );
    this.volumeSlider = document.createElement("input");
    this.volumeSlider.type = "range";
    this.volumeSlider.min = "0";
    this.volumeSlider.max = "1";
    this.volumeSlider.step = "0.05";
    this.volumeSlider.setAttribute("aria-label", "Volume");
    // Hidden on phones, where the bar is tight and the OS volume keys are the
    // control people actually reach for.
    this.volumeSlider.className =
      "ml-1 hidden h-1 w-16 cursor-pointer accent-primary sm:block";
    this.volumeSlider.addEventListener("input", (event) =>
      this.setVolume(Number(event.target.value)),
    );
    volume.append(this.muteButton, this.volumeSlider);

    this.timeLabel = document.createElement("span");
    this.timeLabel.className =
      "ml-1.5 text-xs font-semibold tabular-nums text-white/90";
    this.timeLabel.textContent = "0:00 / 0:00";

    this.lockChip = document.createElement("span");
    this.lockChip.className =
      "hidden items-center gap-1 rounded-full bg-white/10 px-2 py-1 text-[11px] font-semibold text-white/75";
    this.lockChip.title = SKIP_LOCKED_MESSAGE;
    this.lockChip.innerHTML = `${playerIcon("lock", "h-3 w-3")}<span class="hidden sm:inline">No skipping</span>`;

    this.captionSelect = this.buildPlaybackSelect(
      "Captions",
      "captions",
      [["CC Off", "off"]],
      (event) => this.setCaptionTrack(event.target.value),
    );
    this.qualitySelect = this.buildPlaybackSelect(
      "Quality",
      "quality",
      [["Auto", "auto"]],
      (event) => this.setQualityLevel(event.target.value),
    );
    this.speedSelect = this.buildPlaybackSelect(
      "Playback speed",
      "speed",
      [1, 1.25, 1.5, 1.75, 2].map((rate) => [`${rate}x`, String(rate)]),
      (event) => {
        this.player.playbackRate = Number(event.target.value);
      },
    );
    this.fullscreenButton = this.buildIconButton(
      "fullscreen",
      "Full screen",
      () => this.toggleFullscreen(),
    );

    const spacer = document.createElement("div");
    spacer.className = "flex-1";

    row.append(
      this.playButton,
      this.rewindButton,
      this.forwardButton,
      volume,
      this.timeLabel,
      spacer,
      this.lockChip,
      this.captionSelect.label,
      this.qualitySelect.label,
      this.speedSelect.label,
      this.fullscreenButton,
    );

    return row;
  },

  // Three stacked fills tell the whole story at a glance: orange is where the
  // learner is, translucent white is how far they have earned the right to jump,
  // and the hatched tail is the part still locked behind watching it.
  buildScrubber() {
    const scrubber = document.createElement("div");
    scrubber.className = "group/scrub relative cursor-pointer py-2.5";
    scrubber.setAttribute("role", "slider");
    scrubber.setAttribute("aria-label", "Lesson progress");
    scrubber.setAttribute("aria-valuemin", "0");

    const track = document.createElement("div");
    track.className =
      "relative h-1.5 w-full overflow-hidden rounded-full bg-white/20 transition-all duration-150 group-hover/scrub:h-2.5";

    const fill = (className) => {
      const bar = document.createElement("div");
      bar.className = className;
      bar.style.width = "0%";
      return bar;
    };

    this.bufferedBar = fill("absolute inset-y-0 left-0 bg-white/20");
    this.watchedBar = fill("absolute inset-y-0 left-0 bg-white/40");
    this.lockedBar = fill(
      "player-locked-region absolute inset-y-0 right-0 bg-white/5",
    );
    this.playedBar = fill("absolute inset-y-0 left-0 bg-primary");
    track.append(
      this.bufferedBar,
      this.watchedBar,
      this.lockedBar,
      this.playedBar,
    );

    this.thumb = document.createElement("div");
    this.thumb.className =
      "pointer-events-none absolute top-1/2 z-10 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary opacity-0 shadow-md transition-opacity group-hover/scrub:opacity-100";
    this.thumb.style.left = "0%";

    this.hoverLabel = document.createElement("div");
    this.hoverLabel.className =
      "pointer-events-none absolute bottom-full z-10 mb-1 flex -translate-x-1/2 items-center gap-1 rounded-md bg-dark/95 px-2 py-1 text-[11px] font-semibold text-white opacity-0 transition-opacity group-hover/scrub:opacity-100";

    scrubber.append(track, this.thumb, this.hoverLabel);

    const timeAt = (event) => {
      const rect = track.getBoundingClientRect();
      const ratio = Math.min(
        1,
        Math.max(0, (event.clientX - rect.left) / rect.width),
      );
      return ratio * this.duration();
    };

    scrubber.addEventListener("pointerdown", (event) => {
      if (!this.duration()) return;

      event.preventDefault();
      this.scrubbing = true;
      scrubber.setPointerCapture(event.pointerId);
      this.requestSeek(timeAt(event));
    });
    scrubber.addEventListener("pointermove", (event) => {
      if (!this.duration()) return;

      const time = timeAt(event);
      const rect = track.getBoundingClientRect();
      const locked = time > this.seekLimit() + SEEK_TOLERANCE;
      this.hoverLabel.style.left = `${Math.min(Math.max(event.clientX - rect.left, 24), rect.width - 24)}px`;
      this.hoverLabel.innerHTML = locked
        ? `${playerIcon("lock", "h-3 w-3")}Locked`
        : formatMediaTime(time);

      if (this.scrubbing) this.requestSeek(time);
    });
    const endScrub = (event) => {
      if (!this.scrubbing) return;

      this.scrubbing = false;
      if (scrubber.hasPointerCapture(event.pointerId)) {
        scrubber.releasePointerCapture(event.pointerId);
      }
      this.scheduleHideChrome();
    };
    scrubber.addEventListener("pointerup", endScrub);
    scrubber.addEventListener("pointercancel", endScrub);

    this.scrubber = scrubber;
    return scrubber;
  },

  buildIconButton(icon, label, onClick) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = CONTROL_BUTTON_CLASS;
    button.innerHTML = playerIcon(icon);
    button.title = label;
    button.setAttribute("aria-label", label);
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      onClick();
    });
    return button;
  },

  setButtonIcon(button, icon, label) {
    if (button.dataset.icon !== icon) {
      button.dataset.icon = icon;
      button.innerHTML = playerIcon(icon);
    }

    button.title = label;
    button.setAttribute("aria-label", label);
  },

  buildPlaybackSelect(labelText, kind, options, onChange) {
    const label = document.createElement("label");
    label.className = "flex items-center";
    label.title = labelText;
    const text = document.createElement("span");
    text.textContent = labelText;
    text.className = "sr-only";
    const select = document.createElement("select");
    select.className = CONTROL_SELECT_CLASS;
    select.setAttribute("aria-label", labelText);
    select.dataset.setting = kind;
    options.forEach(([optionText, value]) =>
      select.add(new Option(optionText, value)),
    );
    select.disabled = true;
    select.addEventListener("change", onChange);
    label.append(text, select);
    return { label, select };
  },

  // Single place the controls are redrawn from, so playback state and the
  // rendered bar can never disagree.
  syncChrome() {
    const player = this.player;
    if (!player || !this.chrome) return;

    const duration = this.duration();
    const percent = (value) =>
      `${duration ? Math.min(100, Math.max(0, (value / duration) * 100)) : 0}%`;
    const limit = this.seekLimit();
    const locked = this.skipLocked();

    this.playedBar.style.width = percent(player.currentTime);
    this.watchedBar.style.width = percent(limit);
    this.bufferedBar.style.width = percent(this.bufferedEnd());
    this.lockedBar.style.width = duration
      ? `${Math.max(0, 100 - (limit / duration) * 100)}%`
      : "0%";
    this.thumb.style.left = percent(player.currentTime);
    this.timeLabel.textContent = `${formatMediaTime(player.currentTime)} / ${formatMediaTime(duration)}`;
    this.scrubber.setAttribute("aria-valuemax", String(Math.round(duration)));
    this.scrubber.setAttribute(
      "aria-valuenow",
      String(Math.round(player.currentTime)),
    );
    this.scrubber.setAttribute(
      "aria-valuetext",
      `${formatMediaTime(player.currentTime)} of ${formatMediaTime(duration)}`,
    );

    const playing = !player.paused && !player.ended;
    this.setButtonIcon(
      this.playButton,
      playing ? "pause" : "play",
      playing ? "Pause" : "Play",
    );
    this.centerButton.classList.toggle(
      "hidden",
      Boolean(playing || this.buffering),
    );

    const muted = player.muted || player.volume === 0;
    this.setButtonIcon(
      this.muteButton,
      muted ? "muted" : "volume",
      muted ? "Unmute" : "Mute",
    );
    if (document.activeElement !== this.volumeSlider) {
      this.volumeSlider.value = String(muted ? 0 : player.volume);
    }

    const fullscreen = document.fullscreenElement === this.el;
    this.setButtonIcon(
      this.fullscreenButton,
      fullscreen ? "exitFullscreen" : "fullscreen",
      fullscreen ? "Exit full screen" : "Full screen",
    );

    this.forwardButton.classList.toggle("text-white/40", locked);
    this.forwardButton.title = locked
      ? SKIP_LOCKED_MESSAGE
      : "Forward 10 seconds";
    this.lockChip.classList.toggle("hidden", !locked);
    this.lockChip.classList.toggle("inline-flex", locked);
    this.speedSelect.select.disabled = locked;
    this.speedSelect.label.title = locked
      ? SPEED_LOCKED_MESSAGE
      : "Playback speed";
  },

  bufferedEnd() {
    const buffered = this.player?.buffered;
    if (!buffered || buffered.length === 0) return 0;

    for (let index = 0; index < buffered.length; index += 1) {
      if (
        buffered.start(index) <= this.player.currentTime &&
        buffered.end(index) >= this.player.currentTime
      ) {
        return buffered.end(index);
      }
    }

    return buffered.end(buffered.length - 1);
  },

  setBuffering(buffering) {
    this.buffering = buffering;
    this.spinner?.classList.toggle("hidden", !buffering);
    this.syncChrome();
  },

  showChrome() {
    if (!this.controlBar) return;

    this.controlBar.classList.remove("opacity-0", "pointer-events-none");
    this.chrome.classList.remove("cursor-none");
    this.scheduleHideChrome();
  },

  scheduleHideChrome() {
    window.clearTimeout(this.hideChromeTimer);
    this.hideChromeTimer = window.setTimeout(() => this.hideChrome(), 2800);
  },

  // A paused player keeps its controls: the learner is looking at them, not at
  // the picture. So does one being scrubbed, hovered, or focused. A faded bar
  // also stops taking clicks, so the bottom of the picture stays clickable.
  hideChrome() {
    if (
      !this.controlBar ||
      !this.player ||
      this.player.paused ||
      this.scrubbing ||
      this.pointerOnBar ||
      this.controlBar.contains(document.activeElement)
    ) {
      return;
    }

    this.controlBar.classList.add("opacity-0", "pointer-events-none");
    this.chrome.classList.add("cursor-none");
  },

  flashNotice(message = SKIP_LOCKED_MESSAGE) {
    if (!this.notice) return;

    this.notice.textContent = message;
    this.notice.classList.remove("opacity-0");
    this.showChrome();
    window.clearTimeout(this.noticeTimer);
    this.noticeTimer = window.setTimeout(
      () => this.notice.classList.add("opacity-0"),
      2600,
    );
  },

  updateQualityOptions() {
    if (!this.hls || !this.qualitySelect) return;

    const heights = [
      ...new Set(this.hls.levels.map((level) => level.height).filter(Boolean)),
    ].sort((a, b) => b - a);
    this.qualitySelect.select.replaceChildren(new Option("Auto", "auto"));
    heights.forEach((height) =>
      this.qualitySelect.select.add(new Option(`${height}p`, String(height))),
    );
    this.qualitySelect.select.disabled = heights.length === 0;

    const saved = window.localStorage.getItem("wasomi-video-quality") || "auto";
    const available = [...this.qualitySelect.select.options].some(
      (option) => option.value === saved,
    );
    this.setQualityLevel(available ? saved : "auto");
  },

  setQualityLevel(value) {
    if (!this.hls) return;
    const height = Number(value);
    const index =
      value === "auto"
        ? -1
        : this.hls.levels.findIndex((level) => level.height === height);
    this.hls.currentLevel = index;
    window.localStorage.setItem("wasomi-video-quality", value);
    this.syncQualitySelection();
  },

  syncQualitySelection() {
    if (!this.hls || !this.qualitySelect) return;
    this.qualitySelect.select.value =
      this.hls.autoLevelEnabled || this.hls.currentLevel < 0
        ? "auto"
        : String(this.hls.levels[this.hls.currentLevel]?.height || "auto");
  },

  updateCaptionOptions() {
    if (!this.hls || !this.captionSelect) return;

    this.captionSelect.select.replaceChildren(new Option("CC Off", "off"));
    this.hls.subtitleTracks.forEach((track, index) => {
      this.captionSelect.select.add(
        new Option(
          track.name || track.lang || `Track ${index + 1}`,
          String(index),
        ),
      );
    });
    this.captionSelect.select.disabled = this.hls.subtitleTracks.length === 0;

    const saved = window.localStorage.getItem("wasomi-video-captions");
    const defaultTrack = this.hls.subtitleTracks.findIndex(
      (track) => track.lang === "en",
    );
    const requested =
      saved ?? (defaultTrack >= 0 ? String(defaultTrack) : "off");
    this.setCaptionTrack(requested);
  },

  updateNativeCaptionOptions() {
    if (!this.player || this.hls || !this.captionSelect) return;

    const tracks = [...this.player.textTracks];
    this.captionSelect.select.replaceChildren(new Option("CC Off", "off"));
    tracks.forEach((track, index) => {
      this.captionSelect.select.add(
        new Option(
          track.label || track.language || `Track ${index + 1}`,
          String(index),
        ),
      );
    });
    this.captionSelect.select.disabled = tracks.length === 0;

    const saved = window.localStorage.getItem("wasomi-video-captions");
    const defaultTrack = tracks.findIndex((track) => track.language === "en");
    this.setCaptionTrack(
      saved ?? (defaultTrack >= 0 ? String(defaultTrack) : "off"),
    );
  },

  setCaptionTrack(value) {
    const index = value === "off" ? -1 : Number(value);

    if (this.hls) {
      this.hls.subtitleDisplay = index >= 0;
      this.hls.subtitleTrack = index;
    } else if (this.player) {
      [...this.player.textTracks].forEach((track, trackIndex) => {
        track.mode = trackIndex === index ? "showing" : "disabled";
      });
    } else {
      return;
    }

    window.localStorage.setItem("wasomi-video-captions", value);
    this.syncCaptionSelection();
  },

  syncCaptionSelection() {
    if (!this.captionSelect) return;

    if (this.hls) {
      this.captionSelect.select.value =
        this.hls.subtitleDisplay && this.hls.subtitleTrack >= 0
          ? String(this.hls.subtitleTrack)
          : "off";
    } else if (this.player) {
      const selected = [...this.player.textTracks].findIndex(
        (track) => track.mode === "showing",
      );
      this.captionSelect.select.value =
        selected >= 0 ? String(selected) : "off";
    }
  },

  // Sizes the container to the video's real aspect ratio instead of the
  // hardcoded 16:9 placeholder. Landscape/square sources keep filling the
  // full width (unchanged look for standard 16:9 lectures); portrait sources
  // are capped by height instead, so a tall video doesn't blow out the page,
  // and their width is derived from that height via the same ratio.
  applyAspectRatio(width, height) {
    if (!width || !height) return;

    this.el.style.aspectRatio = `${width} / ${height}`;

    if (width < height) {
      this.el.style.width = "auto";
      this.el.style.maxWidth = "100%";
      this.el.style.height = "min(75vh, 640px)";
    } else {
      this.el.style.width = "100%";
      this.el.style.maxWidth = "";
      this.el.style.height = "auto";
    }
  },

  saveProgress() {
    if (!this.player || !Number.isFinite(this.player.currentTime)) return;

    const position = Math.max(0, Math.floor(this.player.currentTime));
    if (position <= this.lastSavedPosition) return;

    this.lastSavedPosition = position;
    this.lastSaveAt = Date.now();
    this.pushEvent("video-progress", {
      lecture_id: this.el.dataset.lectureId,
      position_seconds: position,
    });
  },

  moveWatermark() {
    if (!this.watermark) return;

    // Kept clear of the bottom band the control bar occupies, so the identity
    // stamp is never parked behind the controls where a capture would miss it.
    const positions = [
      ["6%", "8%"],
      ["58%", "12%"],
      ["10%", "60%"],
      ["54%", "56%"],
      ["34%", "36%"],
    ];
    const [left, top] = positions[Math.floor(Math.random() * positions.length)];
    this.watermark.style.left = left;
    this.watermark.style.top = top;
  },
};

// Plain admin-side playback of an already-saved lecture video (the edit
// modal's Video step). Deliberately not ProtectedVideo: there is no progress
// to record, no seek clamp, and no watermark — an admin is reviewing their own
// upload, not consuming a lesson.
Hooks.AdminVideoPlayback = {
  mounted() {
    this.playerHost = this.el.querySelector("[data-role='player']");
    this.abortController = new AbortController();
    this.loadPlayer();
  },

  destroyed() {
    this.abortController?.abort();
    this.hls?.destroy();
  },

  async loadPlayer() {
    try {
      const response = await fetch(this.el.dataset.playbackUrl, {
        credentials: "same-origin",
        headers: { accept: "application/json" },
        signal: this.abortController.signal,
      });

      if (!response.ok)
        throw new Error(`Playback authorization failed (${response.status})`);

      const { url } = await response.json();
      const player = document.createElement("video");
      player.controls = true;
      player.playsInline = true;
      player.preload = "metadata";
      player.style.width = "100%";
      player.style.height = "100%";
      player.style.setProperty("--media-object-fit", "contain");

      // Only an HLS manifest needs hls.js; a progressive file plays natively.
      const isHls = new URL(url, window.location.origin).pathname.endsWith(
        ".m3u8",
      );

      if (!isHls) {
        player.src = url;
      } else if (window.Hls?.isSupported()) {
        this.hls = new window.Hls();
        this.hls.loadSource(url);
        this.hls.attachMedia(player);
      } else if (player.canPlayType("application/vnd.apple.mpegurl")) {
        player.src = url;
      } else {
        throw new Error("HLS playback is not supported by this browser");
      }

      this.playerHost.replaceChildren(player);
    } catch (error) {
      if (error.name === "AbortError") return;
      this.playerHost.textContent = "This video is temporarily unavailable.";
      console.error(error);
    }
  },
};

Hooks.VideoPreview = {
  mounted() {
    this.preview = this.el.querySelector("[data-role='preview']");

    this.el.addEventListener("change", (event) => {
      const input = event.target;
      if (input.type !== "file" || !input.files || !input.files[0]) return;

      const file = input.files[0];
      if (this.objectUrl) URL.revokeObjectURL(this.objectUrl);
      this.objectUrl = URL.createObjectURL(file);

      this.preview.src = this.objectUrl;
      this.preview.classList.remove("hidden");
      this.preview.onloadedmetadata = () => this.fillDuration();
    });
  },

  fillDuration() {
    const seconds = Math.round(this.preview.duration);
    if (!Number.isFinite(seconds) || seconds <= 0) return;

    const durationInput = this.el
      .closest("form")
      ?.querySelector("[name='lecture[duration_seconds]']");

    if (durationInput) {
      durationInput.value = seconds;
      durationInput.dispatchEvent(new Event("input", { bubbles: true }));
    }
  },

  destroyed() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl);
  },
};

function titleCaseFromFilename(filename) {
  return filename
    .replace(/\.[^/.]+$/, "")
    .replace(/[-_]+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

Hooks.StreamUpload = {
  mounted() {
    this.fileInput = this.el.querySelector("[data-role='file']");
    // When the widget lives inside a LiveComponent (e.g. the lecture form
    // modal) it sets phx-target so events reach the component, not the view.
    this.uploadTarget = this.el.getAttribute("phx-target");

    this.fileInput.addEventListener("change", () => {
      if (this.fileInput.files[0]) this.selectFile(this.fileInput.files[0]);
    });

    this.el.addEventListener("dragover", (event) => event.preventDefault());
    this.el.addEventListener("drop", (event) => {
      event.preventDefault();
      const file = event.dataTransfer.files && event.dataTransfer.files[0];
      if (file) this.selectFile(file);
    });

    this.handleEvent("stream-upload-ready", ({ url }) => this.upload(url));
    this.handleEvent("stream-check-upload", () => {
      window.clearTimeout(this.statusTimer);
      this.statusTimer = window.setTimeout(
        () => this.pushUp("check-upload", {}),
        3000,
      );
    });
    this.handleEvent("stream-reset", () => {
      this.request?.abort();
      window.clearTimeout(this.statusTimer);
      this.selectedFile = null;
      if (this.fileInput) this.fileInput.value = "";
    });
  },

  destroyed() {
    this.request?.abort();
    window.clearTimeout(this.statusTimer);
  },

  selectFile(file) {
    this.selectedFile = file;
    this.fillTitle(file.name);
    this.captureLocalPreview(file);

    this.pushUp("create-upload", {
      filename: file.name,
      content_type: file.type,
      size: file.size,
    });
  },

  // The provider can't generate a real thumbnail until processing finishes
  // server-side, but the browser already has the file — grab a frame from
  // it locally so the picker feels instant while the real upload/processing
  // continues in the background.
  captureLocalPreview(file) {
    const objectUrl = URL.createObjectURL(file);
    const video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.preload = "metadata";
    video.src = objectUrl;

    const cleanup = () => URL.revokeObjectURL(objectUrl);

    video.addEventListener(
      "loadeddata",
      () => {
        video.currentTime = Math.min(0.1, (video.duration || 1) / 2);
      },
      { once: true },
    );

    video.addEventListener(
      "seeked",
      () => {
        const canvas = document.createElement("canvas");
        canvas.width = 160;
        canvas.height =
          Math.round((video.videoHeight / video.videoWidth) * 160) || 90;

        const context = canvas.getContext("2d");
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
        this.pushUp("local-preview", {
          data_url: canvas.toDataURL("image/jpeg", 0.7),
        });
        cleanup();
      },
      { once: true },
    );

    video.addEventListener("error", cleanup, { once: true });
  },

  fillTitle(filename) {
    const titleInput = this.el
      .closest("form")
      ?.querySelector("[name='lecture[title]']");
    if (!titleInput || titleInput.value.trim() !== "") return;

    const title = titleCaseFromFilename(filename);
    if (!title) return;

    titleInput.value = title;
    titleInput.dispatchEvent(new Event("input", { bubbles: true }));
  },

  pushUp(event, payload) {
    if (this.uploadTarget) {
      this.pushEventTo(this.uploadTarget, event, payload);
    } else {
      this.pushEvent(event, payload);
    }
  },

  upload(url) {
    const file = this.selectedFile;
    if (!file) return;
    // The progress bar only exists once the server has rendered past the
    // idle state, which has already happened by the time this fires.
    const progress = this.el.querySelector("[data-role='progress']");
    const request = new XMLHttpRequest();
    this.request = request;

    request.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable || !progress) return;
      progress.style.width = `${Math.round((event.loaded / event.total) * 100)}%`;
    });

    request.addEventListener("load", () => {
      if (request.status >= 200 && request.status < 300) {
        if (progress) progress.style.width = "100%";
        this.pushUp("upload-complete", {});
      } else {
        console.error(`Cloudflare Stream upload failed (${request.status})`);
        this.pushUp("upload-failed", { status: request.status });
      }
    });

    request.addEventListener("error", () => {
      console.error(
        "Cloudflare Stream upload failed because of a network error",
      );
      this.pushUp("upload-failed", {});
    });

    request.open("POST", url);
    const body = new FormData();
    body.append("file", file, file.name);
    request.send(body);
  },
};

Hooks.PdfDownload = {
  mounted() {
    this.handleEvent("download-pdf", ({ data, filename }) => {
      const bytes = Uint8Array.from(atob(data), (char) => char.charCodeAt(0));
      const blob = new Blob([bytes], { type: "application/pdf" });
      const url = URL.createObjectURL(blob);

      const link = document.createElement("a");
      link.href = url;
      link.download = filename || "certificate.pdf";
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    });
  },
};

// Plays a one-shot entrance the first time the element scrolls into view.
// `data-reveal="fade-up"` (default) just plays the fade-up keyframe.
// `data-reveal="settle-float"` transitions the element's own tilt/offset
// utility classes to rest, then — once that transition finishes — starts
// the slow, subtle `float` loop so it doesn't fight the entrance motion.
// `data-reveal="stagger"` just adds `in-view` to the element itself, so
// children can key off it (e.g. `group-[.in-view]:animate-fade-up` with a
// per-child `animation-delay`) for a cascading, timeline-style reveal.
Hooks.RevealOnScroll = {
  mounted() {
    const variant = this.el.dataset.reveal || "fade-up";

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          this.observer.unobserve(this.el);

          if (variant === "settle-float") {
            this.el.classList.remove(
              "opacity-0",
              "-translate-x-12",
              "-rotate-6",
            );
            this.el.classList.add("opacity-100", "translate-x-0", "rotate-0");
            this.el.addEventListener(
              "transitionend",
              () => this.el.classList.add("animate-float"),
              { once: true },
            );
          } else if (variant === "stagger") {
            this.el.classList.add("in-view");
          } else {
            this.el.classList.add("animate-fade-up");
          }
        });
      },
      { threshold: 0.2 },
    );

    this.observer.observe(this.el);
  },

  destroyed() {
    this.observer?.disconnect();
  },
};

const EYE_OPEN =
  '<path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7Z"/><circle cx="12" cy="12" r="3"/>';
const EYE_CLOSED =
  '<path d="M17.9 17.9A10.6 10.6 0 0 1 12 19c-7 0-11-7-11-7a19.4 19.4 0 0 1 4.2-5.1M9.9 4.2A9.4 9.4 0 0 1 12 4c7 0 11 7 11 7a19.4 19.4 0 0 1-2.6 3.6M14.1 14.1a3 3 0 1 1-4.2-4.2"/><line x1="1" y1="1" x2="23" y2="23"/>';

Hooks.TogglePassword = {
  mounted() {
    this.input = this.el.querySelector("input");
    this.button = this.el.querySelector("[data-role='toggle']");
    this.eye = this.el.querySelector("[data-role='eye']");
    if (!this.input || !this.button || !this.eye) return;

    this.button.addEventListener("click", () => {
      const showing = this.input.type === "text";
      this.input.type = showing ? "password" : "text";
      this.eye.innerHTML = showing ? EYE_OPEN : EYE_CLOSED;
      this.button.setAttribute(
        "aria-label",
        showing ? "Show password" : "Hide password",
      );
    });
  },
};

Hooks.QuizCountdown = {
  // Display-only: the server owns the deadline and auto-submits via its own
  // `Process.send_after` timer, so this never drives submission itself —
  // just a smooth per-second readout between LiveView renders.
  mounted() {
    this.tick();
    this.timer = window.setInterval(() => this.tick(), 1000);
  },
  destroyed() {
    window.clearInterval(this.timer);
  },
  tick() {
    const deadline = new Date(this.el.dataset.deadline).getTime();
    const totalMs = (parseInt(this.el.dataset.totalSeconds, 10) || 0) * 1000;
    const remainingMs = Math.max(0, deadline - Date.now());
    const remainingSeconds = Math.ceil(remainingMs / 1000);
    const minutes = Math.floor(remainingSeconds / 60);
    const seconds = remainingSeconds % 60;
    this.el.textContent = `${minutes}:${String(seconds).padStart(2, "0")}`;

    const ratio = totalMs > 0 ? remainingMs / totalMs : 0;
    this.el.classList.remove("text-primary", "text-amber-500", "text-red-600");
    if (ratio <= 0.1) {
      this.el.classList.add("text-red-600");
    } else if (ratio <= 0.25) {
      this.el.classList.add("text-amber-500");
    } else {
      this.el.classList.add("text-primary");
    }

    if (remainingMs <= 0) {
      window.clearInterval(this.timer);
    }
  },
};

Hooks.FlashAutoDismiss = {
  mounted() {
    this.schedule();
  },
  updated() {
    this.schedule();
  },
  schedule() {
    window.clearTimeout(this.dismissTimer);
    const ms = parseInt(this.el.dataset.autoDismissMs, 10) || 5000;
    this.dismissTimer = window.setTimeout(() => this.el.click(), ms);
  },
  destroyed() {
    window.clearTimeout(this.dismissTimer);
  },
};

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];
const DOW = ["S", "M", "T", "W", "T", "F", "S"];

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
    this.today.setHours(0, 0, 0, 0);
    const maxVal = this.el.dataset.max;
    if (maxVal === "today") {
      this.max = this.today;
    } else if (maxVal && /^\d{4}-\d{2}-\d{2}$/.test(maxVal)) {
      const [y, m, d] = maxVal.split("-").map(Number);
      this.max = new Date(y, m - 1, d);
      this.max.setHours(0, 0, 0, 0);
    } else {
      this.max = null;
    }
  }

  minYear() {
    return this.today.getFullYear() - 120;
  }
  maxYear() {
    return this.max ? this.max.getFullYear() : this.today.getFullYear() + 10;
  }

  parseValue() {
    const v = this.input ? this.input.value : "";
    if (v && /^\d{4}-\d{2}-\d{2}$/.test(v)) {
      const [y, m, d] = v.split("-").map(Number);
      this.selected = new Date(y, m - 1, d);
      this.selected.setHours(0, 0, 0, 0);
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
    return date.toLocaleDateString(undefined, {
      day: "numeric",
      month: "short",
      year: "numeric",
    });
  }

  renderDisplay() {
    if (!this.display) return;
    if (this.selected) {
      this.display.textContent = this.fmt(this.selected);
      this.display.classList.remove("text-muted");
    } else {
      this.display.textContent =
        this.display.dataset.placeholder || "Choose a date";
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
      if (!this.el.contains(e.target) && !this.pop.contains(e.target))
        this.close();
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
      if (this.viewMonth < 0) {
        this.viewMonth = 11;
        this.viewYear--;
      }
      if (this.viewMonth > 11) {
        this.viewMonth = 0;
        this.viewYear++;
      }
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
      if (this.viewMonth > this.maxMonthFor(this.viewYear))
        this.viewMonth = this.maxMonthFor(this.viewYear);
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
      this.selected = new Date(
        this.viewYear,
        this.viewMonth,
        parseInt(day.dataset.dpDay, 10),
      );
      this.selected.setHours(0, 0, 0, 0);
      this.input.value = this.iso(this.selected);
      this.input.dispatchEvent(new Event("input", { bubbles: true }));
      this.input.dispatchEvent(new Event("change", { bubbles: true }));
      this.renderDisplay();
      this.close();
    }
  }

  maxMonthFor(year) {
    return this.max && year === this.max.getFullYear()
      ? this.max.getMonth()
      : 11;
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
    const daysInMonth = new Date(
      this.viewYear,
      this.viewMonth + 1,
      0,
    ).getDate();

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
    DOW.forEach((d) => {
      dow += `<span style="text-align:center;font-size:12px;font-weight:500;" class="text-muted">${d}</span>`;
    });
    dow += `</div>`;

    let grid = `<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;">`;
    for (let i = 0; i < startDow; i++) grid += `<span></span>`;

    for (let d = 1; d <= daysInMonth; d++) {
      const cur = new Date(this.viewYear, this.viewMonth, d);
      cur.setHours(0, 0, 0, 0);
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

      grid += `<button type="button" data-dp-month="${i}" ${disabled ? "disabled" : ""} class="${classes.join(" ")}">${name.slice(0, 3)}</button>`;
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
      container.scrollTop =
        sel.offsetTop - container.clientHeight / 2 + sel.clientHeight / 2;
    }
  }
}

// Renders a Chart.js chart from a JSON config passed via the `data-config`
// attribute. LiveView re-patches that attribute whenever filters change the
// underlying data — the whole chart is destroyed and rebuilt on `updated()`
// rather than patched in place, since Chart.js configs (scales, datasets)
// aren't cheap to diff and admin dashboards redraw infrequently.
Hooks.Chart = {
  mounted() {
    this.renderChart();
  },
  updated() {
    this.renderChart();
  },
  renderChart() {
    const config = JSON.parse(this.el.dataset.config);
    if (this.chart) this.chart.destroy();
    this.chart = new Chart(this.el, config);
  },
  destroyed() {
    if (this.chart) this.chart.destroy();
  },
};

Hooks.DatePicker = {
  mounted() {
    this.picker = new CustomDatePicker(this.el);
  },
  updated() {
    if (this.picker) {
      this.picker.initToday();
      this.picker.parseValue();
    }
  },
  destroyed() {
    if (this.picker) {
      this.picker.destroy();
    }
  },
};

// v3 (invisible) runs first; v2 (checkbox) is the fallback when the
// server flags a low score or v3 never runs at all (blocked, timed out).
Hooks.Recaptcha = {
  mounted() {
    this.v2Rendered = false;

    this.handleFormSubmit = (e) => {
      const siteKey = this.el.dataset.siteKey;
      const v2SiteKey = this.el.dataset.v2SiteKey;
      if (!siteKey && !v2SiteKey) return;

      if (this.el.dataset.captchaVerified) {
        this.el.dataset.captchaVerified = "";
        return;
      }

      e.preventDefault();
      e.stopImmediatePropagation();

      if (this.el.dataset.showV2 === "true") {
        // Server already asked for v2 — just ensure it's rendered.
        this.ensureV2Rendered();
        return;
      }

      if (!siteKey) {
        this.ensureV2Rendered();
        return;
      }

      this.waitForGrecaptcha()
        .then(() => this.executeAndSubmit(siteKey))
        .catch(() => this.fallbackToV2OrReport());
    };

    this.el.addEventListener("submit", this.handleFormSubmit);
    this.maybeRenderV2();
  },

  updated() {
    this.maybeRenderV2();
  },

  maybeRenderV2() {
    if (this.el.dataset.showV2 === "true") this.ensureV2Rendered();
  },

  waitForGrecaptcha(timeoutMs = 6000, intervalMs = 200) {
    return new Promise((resolve, reject) => {
      const deadline = Date.now() + timeoutMs;

      const check = () => {
        if (window.grecaptcha) return resolve();
        if (Date.now() >= deadline) return reject();
        setTimeout(check, intervalMs);
      };

      check();
    });
  },

  executeAndSubmit(siteKey) {
    const action = this.el.dataset.action || "submit";

    window.grecaptcha.ready(() => {
      const widgetId = this.ensureV3Widget(siteKey);
      if (widgetId === undefined) {
        this.fallbackToV2OrReport();
        return;
      }

      window.grecaptcha
        .execute(widgetId, { action })
        .then((token) => this.submitWithToken(token, "v3"))
        .catch((err) => {
          console.error("reCAPTCHA v3 execution error:", err);
          this.fallbackToV2OrReport();
        });
    });
  },

  // render=explicit means execute() needs a widget id, not the raw site
  // key — render it once into the permanent recaptcha-v3-widget container.
  ensureV3Widget(siteKey) {
    if (this.v3WidgetId !== undefined) return this.v3WidgetId;

    const container = this.el.querySelector("[data-role='recaptcha-v3-widget']");
    if (!container) return undefined;

    this.v3WidgetId = window.grecaptcha.render(container, {
      sitekey: siteKey,
      size: "invisible",
      badge: "bottomright",
    });

    return this.v3WidgetId;
  },

  fallbackToV2OrReport() {
    if (this.el.dataset.v2SiteKey) {
      this.ensureV2Rendered();
    } else {
      this.reportBlocked();
    }
  },

  // Renders the real checkbox into the phx-update="ignore" leaf div so a
  // later LiveView patch can't wipe out Google's injected iframe. Only
  // ever renders once per mount — the widget itself persists after that.
  ensureV2Rendered() {
    const v2SiteKey = this.el.dataset.v2SiteKey;
    const container = this.el.querySelector("[data-role='recaptcha-v2-widget']");
    if (!v2SiteKey || !container || this.v2Rendered) return;

    this.waitForGrecaptcha()
      .then(() => {
        window.grecaptcha.render(container, {
          sitekey: v2SiteKey,
          callback: (token) => this.submitWithToken(token, "v2"),
        });
        this.v2Rendered = true;
      })
      .catch(() => this.reportBlocked());
  },

  submitWithToken(token, version) {
    this.setHiddenField("captcha_token", token);
    this.setHiddenField("captcha_version", version);
    this.el.dataset.captchaVerified = "true";
    this.el.requestSubmit();
  },

  setHiddenField(name, value) {
    let input = this.el.querySelector(`input[name='${name}']`);
    if (!input) {
      input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      this.el.appendChild(input);
    }
    input.value = value;
  },

  // Reuses the same inline error the LiveView shows for a server-side
  // captcha failure.
  reportBlocked() {
    this.pushEventTo(this.el, "recaptcha_blocked", {});
  },

  destroyed() {
    if (this.handleFormSubmit) {
      this.el.removeEventListener("submit", this.handleFormSubmit);
    }
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
  uploaders: { R2: R2Uploader },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// Paired with JS.dispatch on the lesson tabs: a panel that opens below the fold
// — the lesson quiz under a tall player — has to bring itself into view, or the
// click reads as having done nothing at all.
window.addEventListener("wasomi:scroll-into-view", (event) => {
  event.target.scrollIntoView({ behavior: "smooth", block: "start" });
});

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
