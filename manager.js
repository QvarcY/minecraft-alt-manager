const express = require('express')
const fs = require('fs')
const path = require('path')
const Logger = require('./core/logger')
const { ProfileStore, normalizeProfile, safeId } = require('./core/profile-store')
const SecretStore = require('./core/secret-store')
const BotManager = require('./core/bot-manager')
const APP_META = require('./core/app-meta')

const APP_VERSION = APP_META.version
const STARTED_AT = Date.now()
const ROOT = __dirname
const WEB_HOST = '127.0.0.1'
const WEB_PORT = Math.max(1024, Math.min(65535, Number(process.env.MAM_WEB_PORT) || 3077))
const PID_FILE = process.env.MAM_PID_FILE
  ? path.resolve(process.env.MAM_PID_FILE)
  : path.join(ROOT, 'manager.pid')
const APP_MODE = String(process.env.MAM_MODE || 'local').trim().toLowerCase()
const PROFILE_DATA_DIR = process.env.MAM_PROFILE_DATA_DIR
  ? path.resolve(process.env.MAM_PROFILE_DATA_DIR)
  : path.join(ROOT, 'data')
const SECRETS_DIR = process.env.MAM_SECRETS_DIR
  ? path.resolve(process.env.MAM_SECRETS_DIR)
  : path.join(PROFILE_DATA_DIR, 'secrets')
const AUTH_DATA_DIR = process.env.MAM_AUTH_DATA_DIR
  ? path.resolve(process.env.MAM_AUTH_DATA_DIR)
  : path.join(PROFILE_DATA_DIR, 'microsoft-auth')

const logger = new Logger(600)
const profileStore = new ProfileStore(ROOT, { dataDir: PROFILE_DATA_DIR })
const secretStore = new SecretStore(ROOT, { secretsDir: SECRETS_DIR })
const botManager = new BotManager({ rootDir: ROOT, profileStore, secretStore, logger, authDataDir: AUTH_DATA_DIR })

if (secretStore.migrateLegacySecret('knt-survival')) {
  logger.add('Vecā secret.dat parole pārcelta uz KNT profila drošo glabātuvi.')
}

const app = express()
app.disable('x-powered-by')
app.use(express.json({ limit: '64kb' }))

function controlOnly(req, res, next) {
  if (req.get('x-manager-control') !== '1') {
    return res.status(403).json({ ok: false, error: 'Forbidden' })
  }
  next()
}

function asyncRoute(fn) {
  return (req, res) => {
    try {
      fn(req, res)
    } catch (err) {
      logger.add(`API kļūda: ${err.message}`, 'error')
      res.status(400).json({ ok: false, error: err.message })
    }
  }
}

function profileNeedsPassword(profile) {
  return (profile.workflow?.steps || []).some(
    step => step.enabled !== false && step.action?.type === 'chat' && String(step.action.text || '').includes('{password}')
  )
}

function profileDiagnostics(profile, passwordSet = secretStore.has(profile.id)) {
  const steps = profile.workflow?.steps || []
  const usesPassword = steps.some(
    step => step.enabled !== false && step.action?.type === 'chat' && String(step.action.text || '').includes('{password}')
  )
  const afkSteps = steps.filter(step => step.enabled !== false && step.action?.type === 'markAfk')
  const warnings = []

  if (!steps.length) {
    warnings.push('Workflow ir tukšs: ALT pieslēgsies serverim un rādīs logus, bet AFK statuss netiks atzīmēts. Tas ir noderīgi servera izpētei.')
  } else if (!afkSteps.length) {
    warnings.push('Workflow nav AFK noslēguma soļa. Pievieno darbību “Atzīmēt kā AFK”, ja vēlies skaidru gala stāvokli.')
  } else if (afkSteps.length > 1) {
    warnings.push('Profilā ir vairāki AFK noslēguma soļi. Parasti pietiek ar vienu.')
  }

  if (usesPassword && !passwordSet) {
    warnings.push('Workflow izmanto {password}, bet šim profilam parole vēl nav saglabāta DPAPI glabātuvē.')
  }

  return {
    valid: true,
    stepCount: steps.length,
    usesPassword,
    passwordSet: !!passwordSet,
    hasAfkStep: afkSteps.length > 0,
    warnings
  }
}

function profileView(profile) {
  const passwordSet = secretStore.has(profile.id)
  return {
    ...profile,
    passwordSet,
    diagnostics: profileDiagnostics(profile, passwordSet)
  }
}

app.get('/api/status', (req, res) => {
  const profile = botManager.activeProfile()
  res.json({
    appVersion: APP_VERSION,
    appName: APP_META.name,
    appAuthor: APP_META.author,
    appWebsite: APP_META.website,
    appTagline: APP_META.tagline,
    appMode: APP_MODE,
    webPort: WEB_PORT,
    managerOnline: true,
    managerUptime: Date.now() - STARTED_AT,
    pid: process.pid,
    server: {
      host: profile.connection.host,
      port: profile.connection.port
    },
    ...botManager.status()
  })
})

app.get('/api/logs', (req, res) => res.json(logger.all()))

app.post('/api/logs/clear', controlOnly, (req, res) => {
  logger.clear()
  res.json({ ok: true })
})

app.get('/api/profiles', (req, res) => {
  const activeId = profileStore.getActiveId()
  res.json({
    activeProfileId: activeId,
    profiles: profileStore.list().map(item => ({
      ...item,
      active: item.id === activeId,
      passwordSet: secretStore.has(item.id)
    }))
  })
})

app.get('/api/profiles/:id', asyncRoute((req, res) => {
  const profile = profileStore.get(req.params.id)
  if (!profile) return res.status(404).json({ ok: false, error: 'Profils nav atrasts.' })
  res.json(profileView(profile))
}))

app.post('/api/profiles/validate', controlOnly, asyncRoute((req, res) => {
  const body = { ...req.body }
  body.id = safeId(body.id || body.name)
  const profile = normalizeProfile(body)
  const passwordSet = secretStore.has(profile.id)
  res.json({ ok: true, profile, diagnostics: profileDiagnostics(profile, passwordSet) })
}))

app.post('/api/profiles', controlOnly, asyncRoute((req, res) => {
  const body = { ...req.body }
  body.id = safeId(body.id || body.name)
  if (profileStore.get(body.id)) throw new Error('Profils ar šādu ID jau eksistē.')
  const profile = profileStore.save(normalizeProfile(body))
  logger.add(`Izveidots profils: ${profile.name}`)
  res.json({ ok: true, profile: profileView(profile) })
}))

app.put('/api/profiles/:id', controlOnly, asyncRoute((req, res) => {
  const id = safeId(req.params.id)
  const existing = profileStore.get(id)
  if (!existing) return res.status(404).json({ ok: false, error: 'Profils nav atrasts.' })

  if (profileStore.getActiveId() === id && botManager.runtime.running) {
    throw new Error('Pirms aktīvā profila rediģēšanas apturi ALT.')
  }

  const body = { ...req.body, id }
  const profile = profileStore.save(normalizeProfile(body))
  if (profileStore.getActiveId() === id) botManager.refreshProfileRuntime()
  logger.add(`Saglabāts profils: ${profile.name}`)
  res.json({ ok: true, profile: profileView(profile) })
}))

app.delete('/api/profiles/:id', controlOnly, asyncRoute((req, res) => {
  const id = safeId(req.params.id)
  if (profileStore.getActiveId() === id && botManager.runtime.running) {
    throw new Error('Pirms aktīvā profila dzēšanas apturi ALT.')
  }
  const profile = profileStore.get(id)
  if (!profile) return res.status(404).json({ ok: false, error: 'Profils nav atrasts.' })
  profileStore.delete(id)
  secretStore.delete(id)
  botManager.refreshProfileRuntime()
  logger.add(`Dzēsts profils: ${profile.name}`)
  res.json({ ok: true, activeProfileId: profileStore.getActiveId() })
}))

app.post('/api/profiles/:id/select', controlOnly, asyncRoute((req, res) => {
  const profile = botManager.setActiveProfile(req.params.id)
  logger.add(`Aktīvais profils → ${profile.name}`)
  res.json({ ok: true, profile: profileView(profile) })
}))

app.post('/api/profiles/:id/password', controlOnly, asyncRoute((req, res) => {
  const profile = profileStore.get(req.params.id)
  if (!profile) return res.status(404).json({ ok: false, error: 'Profils nav atrasts.' })
  secretStore.set(profile.id, req.body?.password)
  logger.add(`Profila "${profile.name}" parole atjaunināta drošajā DPAPI glabātuvē.`)
  res.json({ ok: true, passwordSet: true })
}))

app.post('/api/chat', controlOnly, asyncRoute((req, res) => {
  const text = String(req.body?.text || '').trim()
  botManager.sendChat(text)
  res.json({ ok: true })
}))

app.post('/api/start', controlOnly, asyncRoute((req, res) => {
  const profile = botManager.activeProfile()
  if (profileNeedsPassword(profile) && !secretStore.has(profile.id)) {
    throw new Error('Šī profila workflow izmanto {password}, bet parole vēl nav saglabāta.')
  }
  res.json({ ok: true, started: botManager.start() })
}))

app.post('/api/stop', controlOnly, (req, res) => {
  res.json({ ok: true, stopped: botManager.stop() })
})

app.post('/api/restart', controlOnly, asyncRoute((req, res) => {
  const profile = botManager.activeProfile()
  if (profileNeedsPassword(profile) && !secretStore.has(profile.id)) {
    throw new Error('Šī profila workflow izmanto {password}, bet parole vēl nav saglabāta.')
  }
  res.json({ ok: true, restarted: botManager.restart() })
}))

app.get('/api/settings', (req, res) => {
  const settings = profileStore.getSettings()
  res.json({ autoStart: settings.autoStart !== false })
})

app.put('/api/settings', controlOnly, asyncRoute((req, res) => {
  const settings = profileStore.getSettings()
  settings.autoStart = req.body?.autoStart !== false
  profileStore.saveSettings(settings)
  res.json({ ok: true, autoStart: settings.autoStart })
}))

let webServer = null
let shuttingDown = false

function cleanupPid() {
  try {
    if (fs.existsSync(PID_FILE)) {
      const pid = fs.readFileSync(PID_FILE, 'utf8').trim()
      if (pid === String(process.pid)) fs.unlinkSync(PID_FILE)
    }
  } catch {}
}

function shutdown(reason = 'Manager shutdown') {
  if (shuttingDown) return
  shuttingDown = true
  botManager.setStage('SHUTTING_DOWN')
  logger.add(`→ Izslēdzu Manager: ${reason}`)
  botManager.shutdownBot()

  let finished = false
  const finish = () => {
    if (finished) return
    finished = true
    cleanupPid()
    process.exit(0)
  }

  if (webServer?.listening) {
    try { webServer.close(finish) } catch {}
  }
  setTimeout(finish, 1300)
}

app.post('/api/shutdown', controlOnly, (req, res) => {
  res.json({ ok: true })
  setTimeout(() => shutdown('GUI shutdown'), 150)
})

app.use(express.static(path.join(ROOT, 'web'), {
  etag: false,
  lastModified: false,
  maxAge: 0
}))

app.get('/', (req, res) => {
  res.sendFile(path.join(ROOT, 'web', 'index.html'))
})

webServer = app.listen(WEB_PORT, WEB_HOST)

webServer.on('listening', () => {
  fs.writeFileSync(PID_FILE, String(process.pid), 'utf8')
  logger.add(`Web panelis: http://${WEB_HOST}:${WEB_PORT}`)
  logger.add(`${APP_META.name} v${APP_VERSION} | PID ${process.pid}`)
  logger.add(`${APP_META.tagline} | ${APP_META.website}`)
  logger.add(`Režīms: ${APP_MODE} | Profili: ${PROFILE_DATA_DIR} | Secrets: ${SECRETS_DIR}`)
  logger.add(`Microsoft auth dati: ${AUTH_DATA_DIR}`)

  const settings = profileStore.getSettings()
  if (settings.autoStart !== false) {
    const profile = botManager.activeProfile()
    if (profileNeedsPassword(profile) && !secretStore.has(profile.id)) {
      logger.add('AutoStart izlaists: aktīvajam profilam nav saglabātas paroles.', 'error')
      botManager.setStage('STOPPED')
    } else {
      botManager.start()
    }
  }
})

webServer.on('error', err => {
  if (err?.code === 'EADDRINUSE') {
    console.error(`KĻŪDA: ports ${WEB_PORT} jau tiek izmantots. Iespējams, Manager jau darbojas.`)
    process.exit(2)
  }
  console.error(err)
  process.exit(1)
})

process.on('SIGINT', () => shutdown('Ctrl+C'))
process.on('SIGTERM', () => shutdown('SIGTERM'))
process.on('exit', cleanupPid)

process.on('uncaughtException', err => {
  logger.add(`UNCAUGHT EXCEPTION: ${err.message}`, 'error')
  console.error(err)
  setTimeout(() => shutdown('Fatal exception'), 100)
})

process.on('unhandledRejection', err => {
  const text = err instanceof Error ? err.message : String(err)
  logger.add(`UNHANDLED REJECTION: ${text}`, 'error')
  console.error(err)
})
