// Tailwind CSS configuration for terminal/hacker aesthetic
const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/polymarket_bot_web.ex",
    "../lib/polymarket_bot/web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        terminal: {
          green: "#00ff00",
          "green-dim": "rgba(0, 255, 0, 0.7)",
          "green-dark": "rgba(0, 255, 0, 0.3)",
          amber: "#ffd93d",
          red: "#ff6b6b",
          bg: "#000000"
        }
      },
      fontFamily: {
        mono: [
          "JetBrains Mono",
          "Fira Code",
          "SF Mono",
          "Monaco",
          "Inconsolata",
          "Roboto Mono",
          "Source Code Pro",
          "monospace"
        ]
      },
      animation: {
        "pulse-slow": "pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite",
        "blink": "blink 1s step-end infinite",
        "flicker": "flicker 0.15s infinite"
      },
      keyframes: {
        blink: {
          "0%, 50%": { opacity: 1 },
          "51%, 100%": { opacity: 0 }
        },
        flicker: {
          "0%": { opacity: 0.97 },
          "50%": { opacity: 0.95 },
          "100%": { opacity: 0.98 }
        }
      },
      boxShadow: {
        "terminal": "0 0 10px rgba(0, 255, 0, 0.3), 0 0 20px rgba(0, 255, 0, 0.1)",
        "terminal-inset": "inset 0 0 10px rgba(0, 255, 0, 0.1), inset 0 0 20px rgba(0, 255, 0, 0.05)"
      }
    }
  },
  plugins: [
    // Custom plugin for terminal utilities
    plugin(function({ addUtilities }) {
      addUtilities({
        ".text-glow": {
          "text-shadow": "0 0 5px #00ff00, 0 0 10px #00ff00, 0 0 15px #00ff00"
        },
        ".text-glow-amber": {
          "text-shadow": "0 0 5px #ffd93d, 0 0 10px #ffd93d"
        },
        ".scanlines": {
          "background": "repeating-linear-gradient(0deg, rgba(0,0,0,0.15), rgba(0,0,0,0.15) 1px, transparent 1px, transparent 2px)"
        }
      })
    })
  ]
}
