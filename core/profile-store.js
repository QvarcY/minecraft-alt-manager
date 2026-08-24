const fs = require('fs')
const path = require('path')

const DEFAULT_PROFILE = {
  id: 'default-profile',
  name: 'Jauns ALT profils',
  connection: {
    host: 'play.example.com',
    port: 25565,
    version: '1.21.11',
    username: 'ALT_USERNAME',
    auth: 'offline'
  },
  reconnect: {
    enabled: true,
    delayMs: 15000,
    backoffEnabled: true,
    maxDelayMs: 300000,
    maxAttempts: 5,
    resetAfterMs: 120000
  },
  compatibility: {
    tickEndGuard: true,
    disablePhysicsDuringConfiguration: true
  },
  workflow: {
    steps: []
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function safeId(value) {
  const id = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')

  if (!id) throw new Error('Profilam nav derīga ID.')
  return id.slice(0, 64)
}

function normalizeOptionalStepId(value) {
  const text = String(value || '').trim()
  return text ? safeId(text) : null
}

function normalizeStep(step, index) {
  const out = clone(step || {})
  out.id = safeId(out.id || `step-${index + 1}`)
  out.name = String(out.name || `Darbība ${index + 1}`).trim().slice(0, 120)
  out.enabled = out.enabled !== false
  out.delayMs = Math.max(0, Math.min(300000, Number(out.delayMs) || 0))

  if (!out.trigger || typeof out.trigger !== 'object') {
    throw new Error(`Darbībai "${out.name}" nav nosacījuma.`)
  }

  if (!out.action || typeof out.action !== 'object') {
    throw new Error(`Darbībai "${out.name}" nav darbības.`)
  }

  const triggerType = out.trigger.type
  if (!['spawn', 'message', 'afterStep', 'spawnAfterStep'].includes(triggerType)) {
    throw new Error(`Neatbalstīts nosacījuma tips: ${triggerType}`)
  }

  if (triggerType === 'spawn') {
    out.trigger.occurrence = Math.max(1, Number(out.trigger.occurrence) || 1)
  }

  if (triggerType === 'message') {
    out.trigger.match = out.trigger.match === 'equals' ? 'equals' : 'contains'
    out.trigger.caseInsensitive = out.trigger.caseInsensitive !== false
    const values = Array.isArray(out.trigger.any) ? out.trigger.any : []
    out.trigger.any = values
      .map(v => String(v || '').trim())
      .filter(Boolean)
      .slice(0, 20)
    if (!out.trigger.any.length) {
      throw new Error(`Ziņojuma nosacījumam "${out.name}" nav meklējamā teksta.`)
    }
    const afterStepId = normalizeOptionalStepId(out.trigger.afterStepId)
    if (afterStepId) out.trigger.afterStepId = afterStepId
    else delete out.trigger.afterStepId
  }

  if (triggerType === 'afterStep') {
    out.trigger.afterStepId = safeId(out.trigger.afterStepId)
  }

  if (triggerType === 'spawnAfterStep') {
    out.trigger.afterStepId = safeId(out.trigger.afterStepId)
    out.trigger.requireConfigurationCycle = out.trigger.requireConfigurationCycle !== false
  }

  const actionType = out.action.type
  if (!['chat', 'markAfk'].includes(actionType)) {
    throw new Error(`Neatbalstīts darbības tips: ${actionType}`)
  }

  if (actionType === 'chat') {
    out.action.text = String(out.action.text || '').trim().slice(0, 500)
    if (!out.action.text) {
      throw new Error(`Darbībai "${out.name}" nav komandas teksta.`)
    }
  }

  return out
}

function normalizeProfile(profile) {
  const p = clone(profile || {})
  p.id = safeId(p.id || p.name)
  p.name = String(p.name || p.id).trim().slice(0, 120)

  p.connection = p.connection || {}
  p.connection.host = String(p.connection.host || '').trim().slice(0, 255)
  p.connection.port = Math.max(1, Math.min(65535, Number(p.connection.port) || 25565))
  p.connection.version = String(p.connection.version || '').trim().slice(0, 40)
  p.connection.username = String(p.connection.username || '').trim().slice(0, 80)
  p.connection.auth = p.connection.auth === 'microsoft' ? 'microsoft' : 'offline'

  if (!p.connection.host) throw new Error('Nav norādīts servera IP/host.')
  if (!p.connection.version) throw new Error('Nav norādīta Minecraft versija.')
  if (!p.connection.username) throw new Error('Nav norādīts ALT lietotājvārds.')

  p.reconnect = p.reconnect || {}
  p.reconnect.enabled = p.reconnect.enabled !== false
  p.reconnect.delayMs = Math.max(1000, Math.min(300000, Number(p.reconnect.delayMs) || 15000))
  p.reconnect.backoffEnabled = p.reconnect.backoffEnabled !== false
  p.reconnect.maxDelayMs = Math.max(
    p.reconnect.delayMs,
    Math.min(900000, Number(p.reconnect.maxDelayMs) || 300000)
  )
  p.reconnect.maxAttempts = Math.max(1, Math.min(20, Number(p.reconnect.maxAttempts) || 5))
  p.reconnect.resetAfterMs = Math.max(30000, Math.min(3600000, Number(p.reconnect.resetAfterMs) || 120000))

  p.compatibility = p.compatibility || {}
  p.compatibility.tickEndGuard = p.compatibility.tickEndGuard !== false
  p.compatibility.disablePhysicsDuringConfiguration = p.compatibility.disablePhysicsDuringConfiguration !== false

  p.workflow = p.workflow || {}
  const steps = Array.isArray(p.workflow.steps) ? p.workflow.steps : []
  p.workflow.steps = steps.map(normalizeStep)

  const ids = new Set()
  for (const step of p.workflow.steps) {
    if (ids.has(step.id)) throw new Error(`Dublēts workflow step ID: ${step.id}`)
    ids.add(step.id)
  }

  for (const step of p.workflow.steps) {
    const trigger = step.trigger || {}
    const ref = trigger.afterStepId
    if (ref && !ids.has(ref)) {
      throw new Error(`Darbība "${step.name}" atsaucas uz neesošu soli: ${ref}`)
    }
    if (ref && ref === step.id) {
      throw new Error(`Darbība "${step.name}" nevar gaidīt pati uz sevi.`)
    }
  }

  return p
}

class ProfileStore {
  constructor(rootDir, options = {}) {
    this.rootDir = rootDir
    this.dataDir = options.dataDir ? path.resolve(options.dataDir) : path.join(rootDir, 'data')
    this.profilesDir = path.join(this.dataDir, 'profiles')
    this.settingsFile = path.join(this.dataDir, 'settings.json')

    ensureDir(this.profilesDir)
    this.ensureDefaultProfile()
    this.ensureSettings()
  }

  ensureDefaultProfile() {
    const hasAnyProfile = fs
      .readdirSync(this.profilesDir)
      .some(name => name.toLowerCase().endsWith('.json'))

    if (!hasAnyProfile) {
      const file = this.fileFor(DEFAULT_PROFILE.id)
      fs.writeFileSync(file, JSON.stringify(DEFAULT_PROFILE, null, 2), 'utf8')
    }
  }

  ensureSettings() {
    if (!fs.existsSync(this.settingsFile)) {
      const firstProfile = this.list()[0]
      fs.writeFileSync(
        this.settingsFile,
        JSON.stringify(
          {
            activeProfileId: firstProfile?.id || DEFAULT_PROFILE.id,
            autoStart: false
          },
          null,
          2
        ),
        'utf8'
      )
    }
  }

  fileFor(id) {
    return path.join(this.profilesDir, `${safeId(id)}.json`)
  }

  list() {
    const files = fs
      .readdirSync(this.profilesDir)
      .filter(name => name.toLowerCase().endsWith('.json'))

    return files
      .map(name => {
        try {
          const p = JSON.parse(fs.readFileSync(path.join(this.profilesDir, name), 'utf8'))
          const normalized = normalizeProfile(p)
          return {
            id: normalized.id,
            name: normalized.name,
            host: normalized.connection.host,
            port: normalized.connection.port,
            version: normalized.connection.version,
            username: normalized.connection.username
          }
        } catch {
          return null
        }
      })
      .filter(Boolean)
      .sort((a, b) => a.name.localeCompare(b.name, 'lv'))
  }

  get(id) {
    const file = this.fileFor(id)
    if (!fs.existsSync(file)) return null
    return normalizeProfile(JSON.parse(fs.readFileSync(file, 'utf8')))
  }

  save(profile) {
    const normalized = normalizeProfile(profile)
    fs.writeFileSync(this.fileFor(normalized.id), JSON.stringify(normalized, null, 2), 'utf8')
    return normalized
  }

  delete(id) {
    const safe = safeId(id)
    const list = this.list()
    if (list.length <= 1) throw new Error('Nevar izdzēst vienīgo profilu.')

    const file = this.fileFor(safe)
    if (fs.existsSync(file)) fs.unlinkSync(file)

    const settings = this.getSettings()
    if (settings.activeProfileId === safe) {
      settings.activeProfileId = this.list()[0].id
      this.saveSettings(settings)
    }
  }

  getSettings() {
    try {
      return JSON.parse(fs.readFileSync(this.settingsFile, 'utf8'))
    } catch {
      return { activeProfileId: DEFAULT_PROFILE.id, autoStart: false }
    }
  }

  saveSettings(settings) {
    fs.writeFileSync(this.settingsFile, JSON.stringify(settings, null, 2), 'utf8')
  }

  getActiveId() {
    const settings = this.getSettings()
    const candidate = safeId(settings.activeProfileId || DEFAULT_PROFILE.id)
    return this.get(candidate) ? candidate : this.list()[0].id
  }

  setActiveId(id) {
    const safe = safeId(id)
    if (!this.get(safe)) throw new Error('Profils nav atrasts.')
    const settings = this.getSettings()
    settings.activeProfileId = safe
    this.saveSettings(settings)
    return safe
  }
}

module.exports = {
  ProfileStore,
  DEFAULT_PROFILE,
  normalizeProfile,
  safeId
}
