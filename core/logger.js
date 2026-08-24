class Logger {
  constructor(max = 600) {
    this.max = max
    this.items = []
  }

  add(message, type = 'info') {
    const entry = {
      time: new Date().toLocaleTimeString(),
      timestamp: Date.now(),
      message: String(message),
      type
    }

    this.items.push(entry)
    while (this.items.length > this.max) this.items.shift()
    console.log(`[${entry.time}] ${entry.message}`)
    return entry
  }

  clear() {
    this.items.length = 0
    this.add('GUI logs notīrīti.')
  }

  all() {
    return this.items
  }
}

module.exports = Logger
