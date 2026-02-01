// Phoenix LiveView JavaScript
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

// Terminal-style hooks
let Hooks = {}

// Auto-scroll terminal log
Hooks.TerminalLog = {
  mounted() {
    this.scrollToBottom()
  },
  updated() {
    this.scrollToBottom()
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

// Typewriter effect for text
Hooks.Typewriter = {
  mounted() {
    const text = this.el.dataset.text || this.el.innerText
    this.el.innerText = ''
    let i = 0
    const type = () => {
      if (i < text.length) {
        this.el.innerText += text.charAt(i)
        i++
        setTimeout(type, 30)
      }
    }
    type()
  }
}

// Chart resize observer
Hooks.ChartResize = {
  mounted() {
    this.resizeObserver = new ResizeObserver(() => {
      this.pushEvent("chart_resize", { width: this.el.clientWidth })
    })
    this.resizeObserver.observe(this.el)
  },
  destroyed() {
    this.resizeObserver.disconnect()
  }
}

// Copy to clipboard
Hooks.CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copy
      navigator.clipboard.writeText(text).then(() => {
        const original = this.el.innerText
        this.el.innerText = "[COPIED]"
        setTimeout(() => {
          this.el.innerText = original
        }, 1000)
      })
    })
  }
}

// LiveView Socket Setup
let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
  dom: {
    onBeforeElUpdated(from, to) {
      // Preserve focused inputs during updates
      if (from._x_dataStack) {
        window.Alpine.clone(from, to)
      }
    }
  }
})

// Connect if there are any LiveViews on the page
liveSocket.connect()

// Expose liveSocket on window for debugging
window.liveSocket = liveSocket

// Terminal boot sequence effect (run once on page load)
document.addEventListener("DOMContentLoaded", () => {
  console.log("%c[POLYMARKET TERMINAL v0.1.0]", "color: #00ff00; font-family: monospace;")
  console.log("%c> System initialized", "color: #00ff00; font-family: monospace;")
  console.log("%c> WebSocket connected", "color: #00ff00; font-family: monospace;")
  console.log("%c> Ready for commands", "color: #ffd93d; font-family: monospace;")
})
