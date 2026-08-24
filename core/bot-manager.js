const path = require('path')
const mineflayer = require('mineflayer')
const WorkflowEngine = require('./workflow-engine')

class BotManager {
  constructor({ rootDir, profileStore, secretStore, logger, authDataDir = null }) {
    this.rootDir = rootDir
    this.profileStore = profileStore
    this.secretStore = secretStore
    this.logger = logger
    this.authDataDir = authDataDir || path.join(this.profileStore.dataDir, 'microsoft-auth')

    this.bot = null
    this.workflow = null
    this.reconnectTimer = null
    this.restartTimer = null
    this.forceStopTimer = null
    this.stableConnectionTimer = null
    this.intentionalBots = new WeakSet()
    this.sessionNumber = 0
    this.manualStop = false
    this.shuttingDown = false
    this.restarting = false
    this.reconnectAttempts = 0
    this.consecutiveFailures = 0
    this.circuitBreakerOpen = false

    this.runtime = {
      running: false,
      connected: false,
      stage: 'STOPPED',
      currentStepId: null,
      currentStepName: null,
      session: 0,
      profileId: this.profileStore.getActiveId(),
      profileName: null,
      username: null,
      version: null,
      hp: null,
      food: null,
      x: null,
      y: null,
      z: null,
      protocolState: null,
      suppressedTickEnds: 0,
      reconnecting: false,
      reconnectAt: null,
      reconnectAttempt: 0,
      reconnectMaxAttempts: null,
      reconnectBaseDelayMs: null,
      reconnectMaxDelayMs: null,
      reconnectBackoffEnabled: true,
      reconnectResetAfterMs: null,
      consecutiveFailures: 0,
      circuitBreakerOpen: false,
      circuitBreakerReason: null,
      lastDisconnectReason: null,
      lastError: null,
      sessionStartedAt: null,
      afkSince: null,
      lastEventAt: Date.now(),
      workflow: []
    }

    this.refreshProfileRuntime()
  }

  activeProfile() {
    const profile = this.profileStore.get(this.profileStore.getActiveId())
    if (!profile) throw new Error('Aktīvais profils nav atrasts.')
    return profile
  }

  refreshProfileRuntime() {
    const p = this.activeProfile()
    this.runtime.profileId = p.id
    this.runtime.profileName = p.name
    this.runtime.username = p.connection.username
    this.runtime.version = p.connection.version
  }

  setStage(stage, step = null) {
    this.runtime.stage = stage
    this.runtime.currentStepId = step?.id || null
    this.runtime.currentStepName = step?.name || null
    this.runtime.lastEventAt = Date.now()
    this.logger.add(step ? `Statuss → ${stage} (${step.name})` : `Statuss → ${stage}`)
  }

  clearPosition() {
    this.runtime.x = null
    this.runtime.y = null
    this.runtime.z = null
  }

  reconnectConfig(profile = this.activeProfile()) {
    const r = profile.reconnect || {}
    const baseDelayMs = Math.max(1000, Number(r.delayMs) || 15000)
    const maxDelayMs = Math.max(
      baseDelayMs,
      Math.min(900000, Number(r.maxDelayMs) || 300000)
    )

    return {
      enabled: r.enabled !== false,
      baseDelayMs,
      backoffEnabled: r.backoffEnabled !== false,
      maxDelayMs,
      maxAttempts: Math.max(1, Math.min(20, Number(r.maxAttempts) || 5)),
      resetAfterMs: Math.max(30000, Math.min(3600000, Number(r.resetAfterMs) || 120000))
    }
  }

  syncReconnectRuntime(profile = this.activeProfile()) {
    const cfg = this.reconnectConfig(profile)
    this.runtime.reconnectAttempt = this.reconnectAttempts
    this.runtime.reconnectMaxAttempts = cfg.maxAttempts
    this.runtime.reconnectBaseDelayMs = cfg.baseDelayMs
    this.runtime.reconnectMaxDelayMs = cfg.maxDelayMs
    this.runtime.reconnectBackoffEnabled = cfg.backoffEnabled
    this.runtime.reconnectResetAfterMs = cfg.resetAfterMs
    this.runtime.consecutiveFailures = this.consecutiveFailures
    this.runtime.circuitBreakerOpen = this.circuitBreakerOpen
  }

  resetReconnectSafety(reason = null, log = false) {
    this.clearTimer('stableConnection')
    const hadFailures =
      this.reconnectAttempts > 0 ||
      this.consecutiveFailures > 0 ||
      this.circuitBreakerOpen

    this.reconnectAttempts = 0
    this.consecutiveFailures = 0
    this.circuitBreakerOpen = false
    this.runtime.reconnectAttempt = 0
    this.runtime.consecutiveFailures = 0
    this.runtime.circuitBreakerOpen = false
    this.runtime.circuitBreakerReason = null

    this.syncReconnectRuntime()

    if (log && hadFailures && reason) {
      this.logger.add(`Reconnect aizsardzības skaitītājs atiestatīts: ${reason}.`)
    }
  }

  reconnectDelayForAttempt(attempt, cfg) {
    if (!cfg.backoffEnabled) return cfg.baseDelayMs

    const multipliers = [1, 2, 4, 8, 20]
    let multiplier
    if (attempt <= multipliers.length) {
      multiplier = multipliers[attempt - 1]
    } else {
      multiplier = multipliers[multipliers.length - 1] * Math.pow(2, attempt - multipliers.length)
    }

    return Math.min(cfg.maxDelayMs, cfg.baseDelayMs * multiplier)
  }

  armStableConnectionReset(bot) {
    this.clearTimer('stableConnection')
    const cfg = this.reconnectConfig()
    this.syncReconnectRuntime()

    this.stableConnectionTimer = setTimeout(() => {
      this.stableConnectionTimer = null
      if (
        this.bot !== bot ||
        this.manualStop ||
        this.shuttingDown ||
        !this.runtime.connected ||
        bot._client?.state !== 'play'
      ) return

      this.resetReconnectSafety(
        `${Math.round(cfg.resetAfterMs / 1000)} s stabils PLAY savienojums`,
        true
      )
    }, cfg.resetAfterMs)
  }

  updatePositionFrom(bot) {
    if (!bot?.entity) return
    const p = bot.entity.position
    this.runtime.x = Number(p.x.toFixed(1))
    this.runtime.y = Number(p.y.toFixed(1))
    this.runtime.z = Number(p.z.toFixed(1))
  }

  clearTimer(name) {
    const key = `${name}Timer`
    if (this[key]) {
      clearTimeout(this[key])
      this[key] = null
    }
  }

  clearAllTimers() {
    this.clearTimer('reconnect')
    this.clearTimer('restart')
    this.clearTimer('forceStop')
    this.clearTimer('stableConnection')
  }

  start() {
    if (this.shuttingDown || this.bot) return false

    this.clearAllTimers()
    this.manualStop = false
    this.restarting = false
    this.refreshProfileRuntime()
    this.resetReconnectSafety()

    this.runtime.running = true
    this.runtime.connected = false
    this.runtime.reconnecting = false
    this.runtime.reconnectAt = null
    this.runtime.lastDisconnectReason = null
    this.runtime.lastError = null
    this.runtime.afkSince = null
    this.runtime.hp = null
    this.runtime.food = null
    this.runtime.workflow = []
    this.clearPosition()

    this.connect()
    return true
  }

  connect() {
    if (this.shuttingDown || this.manualStop || this.bot) return

    const profile = this.activeProfile()
    const c = profile.connection
    this.sessionNumber++
    this.runtime.session = this.sessionNumber
    this.runtime.sessionStartedAt = Date.now()
    this.runtime.reconnecting = false
    this.runtime.reconnectAt = null
    this.runtime.suppressedTickEnds = 0
    this.syncReconnectRuntime(profile)

    this.logger.add(`ALT SESSION #${this.sessionNumber}`)
    this.logger.add(`Profils: ${profile.name}`)
    this.logger.add(`Savienojos ar ${c.host}:${c.port}`)
    this.setStage('CONNECTING')

    const options = {
      host: c.host,
      port: c.port,
      username: c.username,
      auth: c.auth || 'offline',
      version: c.version,
      keepAlive: true,
      hideErrors: true
    }

    if (c.auth === 'microsoft') {
      options.profilesFolder = path.join(this.authDataDir, profile.id)
    }

    const bot = mineflayer.createBot(options)
    this.bot = bot
    const thisBot = bot
    let disconnected = false
    let suppressedTickEnds = 0

    const originalWrite = thisBot._client.write.bind(thisBot._client)
    thisBot._client.write = (name, data) => {
      if (
        profile.compatibility?.tickEndGuard !== false &&
        name === 'tick_end' &&
        thisBot._client.state !== 'play'
      ) {
        suppressedTickEnds++
        this.runtime.suppressedTickEnds = suppressedTickEnds
        if (suppressedTickEnds === 1 || suppressedTickEnds % 20 === 0) {
          this.logger.add(
            `Bloķēts tick_end ārpus PLAY (state=${thisBot._client.state}, count=${suppressedTickEnds})`
          )
        }
        return
      }
      return originalWrite(name, data)
    }

    this.workflow = new WorkflowEngine({
      profile,
      bot: thisBot,
      logger: this.logger,
      getPassword: () => this.secretStore.get(profile.id),
      onStage: step => {
        this.setStage('WORKFLOW', step)
        this.syncWorkflow()
      },
      onAfk: () => {
        this.updatePositionFrom(thisBot)
        this.runtime.afkSince = Date.now()
        this.runtime.lastError = null
        this.resetReconnectSafety('AFK gala stāvoklis sasniegts', true)
        this.setStage('AFK')
        this.logger.add(
          `ALT AFK pozīcija: X=${this.runtime.x} Y=${this.runtime.y} Z=${this.runtime.z}`
        )
        this.syncWorkflow()
      },
      onStateChange: () => this.syncWorkflow(),
      onError: err => {
        this.runtime.lastError = err.message
        this.setStage('ERROR')
        this.intentionalBots.add(thisBot)
        try { thisBot.quit('Workflow error') } catch {}
      }
    })

    thisBot._client.on('state', state => {
      this.runtime.protocolState = state
      this.logger.add(`Protocol → ${state}`)
    })

    thisBot._client.on('start_configuration', () => {
      this.logger.add('VELOCITY/CONFIGURATION → START')
      this.workflow?.onConfigurationStart()
      this.clearTimer('stableConnection')
      this.setStage('CONFIGURATION')

      if (profile.compatibility?.disablePhysicsDuringConfiguration !== false) {
        thisBot.physicsEnabled = false
        this.logger.add('Physics → OFF')
      }
    })

    thisBot._client.on('finish_configuration', () => {
      this.logger.add('VELOCITY/CONFIGURATION → FINISH')
      this.workflow?.onConfigurationFinish()

      if (profile.compatibility?.disablePhysicsDuringConfiguration !== false) {
        setTimeout(() => {
          if (disconnected || this.shuttingDown) return
          thisBot.physicsEnabled = true
          this.logger.add('Physics → ON')
        }, 1500)
      }
    })

    thisBot.on('login', () => {
      this.runtime.connected = true
      this.armStableConnectionReset(thisBot)
      this.logger.add('✓ Minecraft PLAY savienojums')
      this.logger.add(`Username: ${thisBot.username}`)
      this.logger.add(`Version: ${c.version}`)

      try {
        const tickEnd = thisBot.supportFeature('sendsClientTickEndPacket')
        this.logger.add(`TickEnd: ${tickEnd ? 'AKTĪVS' : 'NAV AKTĪVS'}`)
      } catch (err) {
        this.runtime.lastError = err.message
        this.logger.add(`TickEnd pārbaudes kļūda: ${err.message}`, 'error')
      }
    })

    thisBot.on('spawn', () => {
      this.updatePositionFrom(thisBot)
      this.logger.add(
        `SPAWN: X=${this.runtime.x} Y=${this.runtime.y} Z=${this.runtime.z}`
      )
      this.setStage('SPAWNED')
      this.workflow?.onSpawn()
      this.syncWorkflow()
    })

    thisBot.on('messagestr', (message, position) => {
      this.logger.add(`[SERVER ${position}] ${message}`, 'server')
      this.workflow?.onMessage(message)
      this.syncWorkflow()
    })

    thisBot.on('move', () => this.updatePositionFrom(thisBot))

    thisBot.on('health', () => {
      this.runtime.hp = thisBot.health
      this.runtime.food = thisBot.food
    })

    thisBot.on('kicked', reason => {
      const text = this.extractReason(reason)
      this.runtime.lastError = `KICK: ${text}`
      this.logger.add(`✗ KICK: ${text}`, 'error')
    })

    thisBot.on('error', err => {
      this.runtime.lastError = err.message
      this.logger.add(`✗ ERROR: ${err.message}`, 'error')
    })

    thisBot.on('end', reason => {
      if (disconnected) return
      disconnected = true

      const intentional = this.intentionalBots.has(thisBot)
      const isCurrent = this.bot === thisBot

      this.workflow?.destroy()
      this.clearTimer('stableConnection')
      if (isCurrent) this.workflow = null

      this.runtime.connected = false
      this.runtime.protocolState = null
      this.runtime.afkSince = null
      this.runtime.lastDisconnectReason = String(reason)
      this.updatePositionFrom(thisBot)

      this.logger.add(
        `Savienojums pabeigts: ${reason}`,
        intentional ? 'info' : 'error'
      )
      this.logger.add(`Configuration tick_end bloķēti: ${suppressedTickEnds}`)

      if (isCurrent) this.bot = null
      if (this.shuttingDown) return

      if (intentional) {
        if (this.restarting) return
        if (isCurrent) {
          this.runtime.running = false
          this.runtime.reconnecting = false
          this.runtime.reconnectAt = null
          if (this.runtime.stage !== 'ERROR') this.setStage('STOPPED')
        }
        return
      }

      if (!this.manualStop && isCurrent) {
        this.consecutiveFailures++
        this.runtime.consecutiveFailures = this.consecutiveFailures
        this.scheduleReconnect()
      }
    })
  }

  syncWorkflow() {
    this.runtime.workflow = this.workflow?.summary() || []
  }

  scheduleReconnect() {
    const profile = this.activeProfile()
    const cfg = this.reconnectConfig(profile)
    this.syncReconnectRuntime(profile)

    if (this.manualStop || this.shuttingDown || !cfg.enabled) {
      this.runtime.running = false
      this.runtime.reconnecting = false
      this.runtime.reconnectAt = null
      this.setStage('STOPPED')
      return
    }

    this.clearTimer('reconnect')

    if (this.reconnectAttempts >= cfg.maxAttempts) {
      this.circuitBreakerOpen = true
      this.runtime.running = false
      this.runtime.reconnecting = false
      this.runtime.reconnectAt = null
      this.runtime.circuitBreakerOpen = true
      this.runtime.circuitBreakerReason =
        `Sasniegts reconnect mēģinājumu limits (${cfg.maxAttempts}/${cfg.maxAttempts}).`
      this.syncReconnectRuntime(profile)
      this.setStage('RECONNECT_BLOCKED')
      this.logger.add(
        `✗ Reconnect apturēts pēc ${cfg.maxAttempts} neveiksmīgiem automātiskiem mēģinājumiem. ` +
        'Nospied Start ALT, lai sāktu jaunu mēģinājumu ciklu.',
        'error'
      )
      return
    }

    this.reconnectAttempts++
    const attempt = this.reconnectAttempts
    const delay = this.reconnectDelayForAttempt(attempt, cfg)

    this.runtime.running = true
    this.runtime.reconnecting = true
    this.runtime.reconnectAt = Date.now() + delay
    this.runtime.reconnectAttempt = attempt
    this.runtime.consecutiveFailures = this.consecutiveFailures
    this.runtime.circuitBreakerOpen = false
    this.runtime.circuitBreakerReason = null
    this.setStage('RECONNECT_WAIT')
    this.logger.add(
      `Reconnect mēģinājums ${attempt}/${cfg.maxAttempts} pēc ${Math.round(delay / 1000)} sekundēm...`
    )

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      this.runtime.reconnecting = false
      this.runtime.reconnectAt = null
      if (!this.manualStop && !this.shuttingDown && !this.circuitBreakerOpen) this.connect()
    }, delay)
  }

  stop() {
    if (this.shuttingDown) return false

    this.manualStop = true
    this.clearAllTimers()
    this.resetReconnectSafety()
    this.runtime.reconnecting = false
    this.runtime.reconnectAt = null
    this.runtime.afkSince = null

    if (!this.bot) {
      this.runtime.running = false
      if (this.runtime.stage !== 'ERROR') this.setStage('STOPPED')
      return false
    }

    const target = this.bot
    this.intentionalBots.add(target)
    this.setStage('STOPPING')
    this.logger.add('→ Apturu tikai Minecraft ALT...')

    try { target.quit('Manual stop') } catch (err) {
      this.runtime.lastError = err.message
      this.logger.add(`Stop kļūda: ${err.message}`, 'error')
    }

    this.forceStopTimer = setTimeout(() => {
      this.forceStopTimer = null
      if (this.bot === target) {
        this.logger.add('ALT korekti neaizvērās — pārtraucu tikai tā socket.', 'error')
        try { target._client.end('Forced manual stop') } catch {}
        this.bot = null
        this.runtime.running = false
        this.runtime.connected = false
        this.setStage('STOPPED')
      }
    }, 2000)

    return true
  }

  restart() {
    if (this.shuttingDown || this.restartTimer || this.restarting) return false

    this.restarting = true
    this.clearTimer('reconnect')
    this.clearTimer('forceStop')
    this.manualStop = true
    this.resetReconnectSafety()
    this.runtime.reconnecting = false
    this.runtime.reconnectAt = null
    this.runtime.afkSince = null
    this.setStage('RESTARTING')
    this.logger.add('→ ALT restart pieprasīts.')

    const oldBot = this.bot
    if (oldBot) {
      this.intentionalBots.add(oldBot)
      try { oldBot.quit('Manual restart') } catch (err) {
        this.runtime.lastError = err.message
        this.logger.add(`Restart quit kļūda: ${err.message}`, 'error')
      }

      setTimeout(() => {
        if (this.bot === oldBot) {
          try { oldBot._client.end('Forced restart') } catch {}
          this.bot = null
        }
      }, 1500)
    }

    this.restartTimer = setTimeout(() => {
      this.restartTimer = null
      if (this.bot === oldBot) this.bot = null
      this.restarting = false
      this.manualStop = false
      this.start()
    }, oldBot ? 2200 : 300)

    return true
  }

  maskManualChat(text, password = null) {
    let safe = String(text || '')
    if (password) safe = safe.split(password).join('••••••••')
    return safe
      .replace(/\/login\s+\S+/i, '/login ••••••••')
      .replace(/\/register\s+\S+\s+\S+/i, '/register •••••••• ••••••••')
  }

  expandManualChat(text) {
    const profile = this.activeProfile()
    const c = profile.connection || {}
    let out = String(text || '')
      .replaceAll('{username}', c.username || '')
      .replaceAll('{host}', c.host || '')
      .replaceAll('{port}', String(c.port || ''))

    let password = null
    if (out.includes('{password}')) {
      password = this.secretStore.get(profile.id)
      if (!password) throw new Error('Šim profilam nav saglabātas paroles.')
      out = out.replaceAll('{password}', password)
    }

    return { text: out, password }
  }

  sendChat(text) {
    const raw = String(text || '').trim()
    if (!raw) throw new Error('Komanda/ziņojums ir tukšs.')
    if (raw.length > 500) throw new Error('Komanda/ziņojums ir par garu.')
    if (!this.bot || !this.runtime.connected || this.bot._client?.state !== 'play') {
      throw new Error('ALT pašlaik nav PLAY savienojumā ar serveri.')
    }

    const expanded = this.expandManualChat(raw)
    this.logger.add(`MANUAL → ${this.maskManualChat(expanded.text, expanded.password)}`)
    this.bot.chat(expanded.text)
    return true
  }

  setActiveProfile(id) {
    if (this.runtime.running || this.bot) {
      throw new Error('Pirms profila maiņas apturi ALT.')
    }
    this.profileStore.setActiveId(id)
    this.refreshProfileRuntime()
    this.runtime.lastError = null
    this.runtime.lastDisconnectReason = null
    this.runtime.workflow = []
    this.resetReconnectSafety()
    this.setStage('STOPPED')
    return this.activeProfile()
  }

  shutdownBot() {
    this.shuttingDown = true
    this.manualStop = true
    this.restarting = false
    this.clearAllTimers()
    this.workflow?.destroy()
    this.workflow = null

    const target = this.bot
    if (target) {
      this.intentionalBots.add(target)
      try { target.quit('Manager shutdown') } catch {}
      setTimeout(() => {
        try { target._client.end('Manager shutdown') } catch {}
      }, 700)
    }
    this.bot = null
  }

  status() {
    const reconnectIn = this.runtime.reconnectAt
      ? Math.max(0, this.runtime.reconnectAt - Date.now())
      : null

    return {
      ...this.runtime,
      reconnectIn,
      sessionUptime: this.runtime.sessionStartedAt
        ? Date.now() - this.runtime.sessionStartedAt
        : null,
      afkTime: this.runtime.afkSince ? Date.now() - this.runtime.afkSince : null
    }
  }

  extractReason(reason) {
    try {
      if (reason?.value?.text?.value) return reason.value.text.value
      return JSON.stringify(reason)
    } catch {
      return String(reason)
    }
  }
}

module.exports = BotManager
