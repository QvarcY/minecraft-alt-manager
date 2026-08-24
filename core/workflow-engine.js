class WorkflowEngine {
  constructor({ profile, bot, logger, getPassword, onAfk, onStage, onError, onStateChange }) {
    this.profile = profile
    this.bot = bot
    this.logger = logger
    this.getPassword = getPassword
    this.onAfk = onAfk
    this.onStage = onStage
    this.onError = onError
    this.onStateChange = onStateChange

    this.steps = (profile.workflow?.steps || []).filter(step => step.enabled !== false)
    this.state = new Map()
    this.spawnCount = 0
    this.completedConfigCycles = 0
    this.configOpen = false
    this.destroyed = false
    this.passwordLoaded = false
    this.cachedPassword = null

    for (const step of this.steps) {
      this.state.set(step.id, {
        pending: false,
        executed: false,
        executedAt: null,
        configCyclesAtExecution: 0,
        timer: null
      })
    }
  }

  destroy() {
    this.destroyed = true
    for (const state of this.state.values()) {
      if (state.timer) clearTimeout(state.timer)
      state.timer = null
      state.pending = false
    }
  }

  onConfigurationStart() {
    this.configOpen = true
  }

  onConfigurationFinish() {
    if (this.configOpen) {
      this.completedConfigCycles++
      this.configOpen = false
    }
  }

  onSpawn() {
    this.spawnCount++

    for (const step of this.steps) {
      const trigger = step.trigger || {}

      if (trigger.type === 'spawn') {
        if (this.spawnCount === Number(trigger.occurrence || 1)) {
          this.schedule(step, `spawn #${this.spawnCount}`)
        }
        continue
      }

      if (trigger.type === 'spawnAfterStep') {
        const ref = this.state.get(trigger.afterStepId)
        if (!ref || !ref.executed) continue

        if (
          trigger.requireConfigurationCycle !== false &&
          this.completedConfigCycles <= ref.configCyclesAtExecution
        ) {
          continue
        }

        this.schedule(step, `spawn pēc ${trigger.afterStepId}`)
      }
    }
  }

  onMessage(message) {
    const text = String(message || '')

    for (const step of this.steps) {
      const trigger = step.trigger || {}
      if (trigger.type !== 'message') continue

      if (trigger.afterStepId) {
        const ref = this.state.get(trigger.afterStepId)
        if (!ref?.executed) continue
      }

      if (this.matchesMessage(trigger, text)) {
        this.schedule(step, `ziņojums: ${text}`)
      }
    }
  }

  matchesMessage(trigger, message) {
    const values = Array.isArray(trigger.any) ? trigger.any : []
    const insensitive = trigger.caseInsensitive !== false
    const source = insensitive ? message.toLowerCase() : message

    return values.some(value => {
      const needle = insensitive ? String(value).toLowerCase() : String(value)
      return trigger.match === 'equals' ? source === needle : source.includes(needle)
    })
  }

  scheduleAfterStep(stepId) {
    for (const step of this.steps) {
      const trigger = step.trigger || {}
      if (trigger.type === 'afterStep' && trigger.afterStepId === stepId) {
        this.schedule(step, `pēc ${stepId}`)
      }
    }
  }

  schedule(step, reason) {
    const state = this.state.get(step.id)
    if (!state || state.pending || state.executed || this.destroyed) return

    state.pending = true
    const delay = Math.max(0, Number(step.delayMs) || 0)

    this.logger.add(`Workflow: "${step.name}" aktivizēts (${reason}).`)
    if (this.onStage) this.onStage(step)

    state.timer = setTimeout(() => {
      state.timer = null
      state.pending = false
      if (this.destroyed) return

      try {
        this.execute(step, state)
      } catch (err) {
        this.logger.add(`Workflow kļūda (${step.name}): ${err.message}`, 'error')
        if (this.onError) this.onError(err, step)
      }
    }, delay)
  }

  execute(step, state) {
    if (this.destroyed || state.executed) return

    const action = step.action || {}

    if (action.type === 'chat') {
      const command = this.expand(String(action.text || ''))
      if (!command) throw new Error('Komanda ir tukša.')

      this.logger.add(`→ ${this.maskPassword(command)}`)
      this.bot.chat(command)
    } else if (action.type === 'markAfk') {
      this.logger.add('✓ Workflow sasniedza AFK gala stāvokli.')
      if (this.onAfk) this.onAfk(step)
    } else {
      throw new Error(`Neatbalstīts action tips: ${action.type}`)
    }

    state.executed = true
    state.executedAt = Date.now()
    state.configCyclesAtExecution = this.completedConfigCycles
    if (this.onStateChange) this.onStateChange()

    // Universāliem profiliem bieži vajag vienkāršu lineāru ķēdi:
    // komanda -> pagaidi -> nākamā komanda/AFK. Šis trigger neprasa
    // servera ziņojumu vai jaunu spawn un tāpēc strādā arī parastiem /home teleportiem.
    this.scheduleAfterStep(step.id)
  }

  password() {
    if (!this.passwordLoaded) {
      this.cachedPassword = this.getPassword()
      this.passwordLoaded = true
    }
    return this.cachedPassword
  }

  expand(text) {
    let out = text
    const c = this.profile.connection || {}

    out = out.replaceAll('{username}', c.username || '')
    out = out.replaceAll('{host}', c.host || '')
    out = out.replaceAll('{port}', String(c.port || ''))

    if (out.includes('{password}')) {
      out = out.replaceAll('{password}', this.password())
    }

    return out
  }

  maskPassword(text) {
    if (!text) return text

    // Svarīgi: neizsaucam DPAPI/PowerShell tikai loga maskēšanas dēļ.
    // Parole tiek nolasīta tikai tad, kad komanda tiešām izmanto {password}.
    if (this.passwordLoaded && this.cachedPassword) {
      return text.split(this.cachedPassword).join('••••••••')
    }

    return text
      .replace(/\/login\s+\S+/i, '/login ••••••••')
      .replace(/\/register\s+\S+\s+\S+/i, '/register •••••••• ••••••••')
  }

  summary() {
    return this.steps.map(step => {
      const state = this.state.get(step.id)
      return {
        id: step.id,
        name: step.name,
        pending: !!state?.pending,
        executed: !!state?.executed
      }
    })
  }
}

module.exports = WorkflowEngine
