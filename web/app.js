const CONTROL_HEADERS = { 'X-Manager-Control': '1', 'Content-Type': 'application/json' }
let latestLogs = []
let latestStatus = null
let profilesCache = []
let editedProfile = null
let editedExistingId = null
let toastTimer = null
let profileIdAuto = false

const $ = id => document.getElementById(id)

function esc(v) {
  return String(v ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

function clientSafeId(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function duration(ms) {
  if (ms === null || ms === undefined) return '—'
  let s = Math.max(0, Math.floor(ms / 1000))
  const d = Math.floor(s / 86400); s %= 86400
  const h = Math.floor(s / 3600); s %= 3600
  const m = Math.floor(s / 60); s %= 60
  if (d) return `${d}d ${h}h ${m}m`
  if (h) return `${h}h ${m}m ${s}s`
  if (m) return `${m}m ${s}s`
  return `${s}s`
}

function toast(text) {
  const el = $('toast')
  el.textContent = text
  el.classList.add('show')
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => el.classList.remove('show'), 2600)
}

function showTab(name) {
  $('dashboardView').classList.toggle('hidden', name !== 'dashboard')
  $('profilesView').classList.toggle('hidden', name !== 'profiles')
  $('guideView').classList.toggle('hidden', name !== 'guide')
  $('tabDashboard').classList.toggle('active', name === 'dashboard')
  $('tabProfiles').classList.toggle('active', name === 'profiles')
  $('tabGuide').classList.toggle('active', name === 'guide')
  if (name === 'profiles') refreshProfiles()
}

async function api(url, options = {}) {
  const response = await fetch(url, { cache: 'no-store', ...options })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`)
  return data
}

async function writeApi(url, method = 'POST', body = undefined) {
  return api(url, {
    method,
    headers: CONTROL_HEADERS,
    body: body === undefined ? undefined : JSON.stringify(body)
  })
}

function stageView(s) {
  const map = {
    STOPPED: ['Apturēts', 'ALT nav pieslēgts.', 'ALT OFF', ''],
    CONNECTING: ['Savienojas', 'Veido savienojumu ar serveri.', 'CONNECTING', 'wait'],
    CONFIGURATION: ['Servera pāreja', 'Minecraft CONFIGURATION fāze.', 'CONFIG', 'wait'],
    SPAWNED: ['Spawn', 'ALT ir ielādēts servera pasaulē.', 'SPAWN', 'wait'],
    WORKFLOW: ['Automatizācija', s.currentStepName || 'Izpilda profila darbību secību.', 'WORKFLOW', 'wait'],
    AFK: ['AFK', 'Profila automatizācija ir pabeigta.', 'AFK', 'ok'],
    RECONNECT_WAIT: ['Reconnect', `Mēģinājums ${s.reconnectAttempt || 0}/${s.reconnectMaxAttempts || '—'} pēc ${Math.ceil((s.reconnectIn || 0) / 1000)} s.`, 'RECONNECT', 'wait'],
    RECONNECT_BLOCKED: ['Reconnect apturēts', 'Sasniegts automātisko reconnect mēģinājumu limits. Nospied Start ALT, lai mēģinātu vēlreiz.', 'RECONNECT STOP', 'error'],
    STOPPING: ['Aptur ALT', 'Tiek aizvērts Minecraft savienojums.', 'STOPPING', 'wait'],
    RESTARTING: ['Restartē ALT', 'Tiek pārstartēts Minecraft savienojums.', 'RESTART', 'wait'],
    ERROR: ['Kļūda', 'Automatizācija vai savienojums apstājies kļūdas dēļ.', 'ERROR', 'error'],
    SHUTTING_DOWN: ['Izslēdzas', 'Manager process tiek aizvērts.', 'SHUTDOWN', 'error']
  }
  return map[s.stage] || [s.stage || '—', 'Gaida statusu.', s.stage || '—', '']
}

function renderStatus(s) {
  latestStatus = s
  const view = stageView(s)
  $('activeProfileName').textContent = s.profileName || '—'
  $('activeProfileMeta').textContent = `${s.username || '—'} · ${s.server?.host || '—'}:${s.server?.port || '—'}`
  $('bigStatus').textContent = view[0]
  $('subStatus').textContent = view[1]
  $('statusBadge').textContent = view[2]
  $('statusBadge').className = `badge ${view[3]}`
  $('serverValue').textContent = `${s.server?.host || '—'}:${s.server?.port || '—'}`
  $('usernameValue').textContent = s.username || '—'
  $('versionValue').textContent = s.version || '—'
  $('sessionValue').textContent = s.session || '—'
  $('protocolValue').textContent = s.protocolState || '—'
  $('pidValue').textContent = s.pid || '—'
  $('afkValue').textContent = s.afkSince ? duration(s.afkTime) : '—'
  $('hpValue').textContent = s.hp == null ? '—' : `${s.hp} / 20`
  $('foodValue').textContent = s.food == null ? '—' : `${s.food} / 20`
  $('hpBar').style.width = `${Math.max(0, Math.min(100, ((s.hp || 0) / 20) * 100))}%`
  $('foodBar').style.width = `${Math.max(0, Math.min(100, ((s.food || 0) / 20) * 100))}%`
  $('positionValue').textContent = [s.x, s.y, s.z].some(v => v == null) ? '—' : `${s.x} · ${s.y} · ${s.z}`
  $('minecraftValue').textContent = s.connected ? 'CONNECTED' : (s.running ? 'DISCONNECTED' : 'STOPPED')
  $('reconnectValue').textContent = s.circuitBreakerOpen
    ? `APTURĒTS · ${s.reconnectAttempt || 0}/${s.reconnectMaxAttempts || '—'}`
    : s.reconnecting
      ? `${s.reconnectAttempt || 0}/${s.reconnectMaxAttempts || '—'} · ${Math.ceil((s.reconnectIn || 0) / 1000)}s`
      : 'Nav aktīvs'
  $('sessionUptimeValue').textContent = s.running ? duration(s.sessionUptime) : '—'
  $('tickValue').textContent = s.suppressedTickEnds ?? 0
  $('disconnectValue').textContent = s.lastDisconnectReason || '—'

  const errorBox = $('errorBox')
  if (s.lastError) {
    errorBox.style.display = 'block'
    errorBox.textContent = `Pēdējā kļūda: ${s.lastError}`
  } else {
    errorBox.style.display = 'none'
    errorBox.textContent = ''
  }

  $('startBtn').disabled = !!s.running
  $('stopBtn').disabled = !s.running
  $('restartBtn').disabled = !s.running
  $('manualSendBtn').disabled = !s.connected || s.protocolState !== 'play'
  $('quickProfileSelect').disabled = !!s.running
  $('quickProfileBtn').disabled = !!s.running
  $('footerVersion').textContent = `Minecraft ALT Manager v${s.appVersion} · ${String(s.appMode || 'local').toUpperCase()}`
  $('lastRefresh').textContent = `Atjaunots ${new Date().toLocaleTimeString()}`

  const wf = Array.isArray(s.workflow) ? s.workflow : []
  $('workflowProgress').innerHTML = wf.length
    ? wf.map(step => `<div class="wf-item ${step.executed ? 'done' : step.pending ? 'pending' : ''}"><span class="wf-dot"></span><span>${esc(step.name)}</span></div>`).join('')
    : '<span class="muted">Workflow nav definēts vai vēl nav sācies.</span>'

  renderQuickProfileSelect()
}

function cleanServerLogText(message) {
  return String(message || '').replace(/^\[SERVER [^\]]+\]\s*/, '')
}

function renderLogs(items) {
  latestLogs = items
  const el = $('logs')
  const nearBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 80
  el.innerHTML = items.map(entry => {
    let cls = 'log-line'
    let extra = ''
    if (entry.type === 'server') {
      cls += ' log-server copyable'
      extra = ` data-copy="${esc(cleanServerLogText(entry.message))}" title="Klikšķini, lai nokopētu servera tekstu"`
    }
    if (entry.type === 'error') cls += ' log-error'
    return `<div class="${cls}"${extra}><span class="log-time">[${esc(entry.time)}]</span> ${esc(entry.message)}</div>`
  }).join('')
  if (nearBottom) el.scrollTop = el.scrollHeight
}

async function refreshDashboard() {
  try {
    const [status, logs] = await Promise.all([api('/api/status'), api('/api/logs')])
    $('managerState').textContent = 'Manager online'
    $('managerState').className = 'pill ok'
    renderStatus(status)
    renderLogs(logs)
  } catch {
    $('managerState').textContent = 'Manager offline'
    $('managerState').className = 'pill'
    $('bigStatus').textContent = 'Manager nav sasniedzams'
    $('subStatus').textContent = 'Process ir izslēgts vai ports nav pieejams.'
  }
}

async function control(name) {
  try {
    await writeApi(`/api/${name}`)
    toast(`${name} komanda nosūtīta`)
    setTimeout(refreshDashboard, 200)
  } catch (err) {
    toast(err.message)
  }
}

async function clearLogs() {
  try { await writeApi('/api/logs/clear'); await refreshDashboard() } catch (err) { toast(err.message) }
}

async function copyLogs() {
  try {
    await navigator.clipboard.writeText(latestLogs.map(e => `[${e.time}] ${e.message}`).join('\n'))
    toast('Logs nokopēts')
  } catch { toast('Kopēšana neizdevās') }
}

async function shutdownManager() {
  if (!confirm('Izslēgt visu Minecraft ALT Manager?\n\nTiks atvienots arī ALT un web panelis aizvērsies.')) return
  try {
    await writeApi('/api/shutdown')
    $('bigStatus').textContent = 'Manager izslēdzas...'
    toast('Manager tiek izslēgts')
  } catch (err) { toast(err.message) }
}

async function sendManual(event) {
  event?.preventDefault()
  const text = $('manualText').value.trim()
  if (!text) return
  try {
    await writeApi('/api/chat', 'POST', { text })
    $('manualText').value = ''
    toast('Komanda nosūtīta')
  } catch (err) { toast(err.message) }
}

function renderQuickProfileSelect() {
  const select = $('quickProfileSelect')
  if (!select || !profilesCache.length) return
  const current = latestStatus?.profileId || profilesCache.find(p => p.active)?.id
  select.innerHTML = profilesCache.map(p => `<option value="${esc(p.id)}" ${p.id === current ? 'selected' : ''}>${esc(p.name)}</option>`).join('')
}

async function quickUseProfile() {
  try {
    const id = $('quickProfileSelect').value
    if (!id) return
    await writeApi(`/api/profiles/${encodeURIComponent(id)}/select`)
    await refreshProfiles()
    await refreshDashboard()
    toast('Aktīvais profils nomainīts')
  } catch (err) { toast(err.message) }
}

async function configureActiveProfile() {
  showTab('profiles')
  const id = latestStatus?.profileId || profilesCache.find(p => p.active)?.id
  if (id) await loadProfile(id)
}

async function refreshProfiles() {
  try {
    const [result, settings] = await Promise.all([api('/api/profiles'), api('/api/settings')])
    profilesCache = result.profiles
    $('autoStart').checked = settings.autoStart !== false
    renderProfileList(result.activeProfileId)
    renderQuickProfileSelect()
    if (!editedProfile && profilesCache.length) await loadProfile(result.activeProfileId)
  } catch (err) { toast(err.message) }
}

function renderProfileList(activeId) {
  $('profileList').innerHTML = profilesCache.map(p => `
    <div class="profile-item ${p.active ? 'active' : ''} ${editedExistingId === p.id ? 'selected' : ''}" onclick="loadProfile('${esc(p.id)}')">
      <strong>${esc(p.name)}${p.active ? ' · AKTĪVS' : ''}</strong>
      <span>${esc(p.username)} → ${esc(p.host)}:${esc(p.port)}</span>
      <span>${esc(p.version)} · ${p.passwordSet ? 'parole saglabāta' : 'parole nav saglabāta'}</span>
    </div>`).join('')
}

async function loadProfile(id) {
  try {
    const p = await api(`/api/profiles/${encodeURIComponent(id)}`)
    editedProfile = p
    editedExistingId = p.id
    profileIdAuto = false
    fillEditor(p, false)
    renderProfileList(profilesCache.find(x => x.active)?.id)
  } catch (err) { toast(err.message) }
}

function baseNewProfile() {
  return {
    id: '', name: 'Jauns ALT profils', passwordSet: false,
    connection: { host: '', port: 25565, version: '1.21.11', username: '', auth: 'offline' },
    reconnect: { enabled: true, delayMs: 15000, backoffEnabled: true, maxDelayMs: 300000, maxAttempts: 5, resetAfterMs: 120000 },
    compatibility: { tickEndGuard: true, disablePhysicsDuringConfiguration: true },
    workflow: { steps: [] }
  }
}

function newProfile(template = 'monitor') {
  editedExistingId = null
  editedProfile = baseNewProfile()
  profileIdAuto = true
  applyTemplateToObject(editedProfile, template)
  fillEditor(editedProfile, true)
  $('pName').focus()
}

function applyTemplateToObject(profile, type) {
  const workflows = {
    monitor: [],
    direct: [
      { id: 'afk', name: 'Atzīmēt kā AFK', enabled: true, trigger: { type: 'spawn', occurrence: 1 }, delayMs: 2000, action: { type: 'markAfk' } }
    ],
    login: [
      { id: 'login', name: 'Autorizēties', enabled: true, trigger: { type: 'spawn', occurrence: 1 }, delayMs: 4000, action: { type: 'chat', text: '/login {password}' } },
      { id: 'afk', name: 'Pēc autorizācijas atzīmēt AFK', enabled: true, trigger: { type: 'message', match: 'contains', caseInsensitive: true, any: ['Successfully logged in', 'already logged in'], afterStepId: 'login' }, delayMs: 1000, action: { type: 'markAfk' } }
    ],
    hub: [
      { id: 'login', name: 'Autorizēties', enabled: true, trigger: { type: 'spawn', occurrence: 1 }, delayMs: 4000, action: { type: 'chat', text: '/login {password}' } },
      { id: 'server', name: 'Pāriet uz vajadzīgo serveri', enabled: true, trigger: { type: 'message', match: 'contains', caseInsensitive: true, any: ['Successfully logged in', 'already logged in'], afterStepId: 'login' }, delayMs: 3000, action: { type: 'chat', text: '/server-survival' } },
      { id: 'home', name: 'Doties uz AFK vietu', enabled: true, trigger: { type: 'message', match: 'contains', caseInsensitive: true, any: ['Welcome to Survival server!'], afterStepId: 'server' }, delayMs: 3000, action: { type: 'chat', text: '/tp land-home' } },
      { id: 'afk', name: 'Atzīmēt kā AFK', enabled: true, trigger: { type: 'spawnAfterStep', afterStepId: 'home', requireConfigurationCycle: true }, delayMs: 500, action: { type: 'markAfk' } }
    ]
  }
  profile.workflow = { steps: clone(workflows[type] || workflows.monitor) }
}

function applyTemplate(type) {
  if (editedExistingId && !confirm('Aizvietot šī profila pašreizējo workflow ar izvēlēto šablonu?')) return
  const current = collectProfileSafe()
  applyTemplateToObject(current, type)
  editedProfile = current
  renderSteps(current.workflow.steps)
  renderDiagnostics({ valid: true, warnings: ['Šablons ielādēts. Nomaini komandas un servera tekstus atbilstoši savam serverim, pēc tam nospied “Pārbaudīt”.'] })
  toast('Šablons ielādēts')
}

function fillEditor(p, isNew) {
  $('editorTitle').textContent = isNew ? 'Jauns profils' : p.name
  $('editorNotice').textContent = isNew ? 'Izvēlies šablonu, ievadi serveri un pielāgo ceļu līdz AFK.' : `Profila ID: ${p.id}`
  $('templateChooser').classList.toggle('new-profile-highlight', isNew)
  $('pName').value = p.name || ''
  $('pId').value = p.id || (isNew ? clientSafeId(p.name) : '')
  $('pId').disabled = !isNew
  $('pHost').value = p.connection?.host || ''
  $('pPort').value = p.connection?.port || 25565
  $('pVersion').value = p.connection?.version || ''
  $('pUsername').value = p.connection?.username || ''
  $('pAuth').value = p.connection?.auth || 'offline'
  $('pReconnectEnabled').checked = p.reconnect?.enabled !== false
  $('pReconnectDelay').value = Math.round((p.reconnect?.delayMs || 15000) / 1000)
  $('pReconnectBackoff').checked = p.reconnect?.backoffEnabled !== false
  $('pReconnectMaxDelay').value = Math.round((p.reconnect?.maxDelayMs || 300000) / 1000)
  $('pReconnectMaxAttempts').value = p.reconnect?.maxAttempts || 5
  $('pReconnectResetAfter').value = Math.round((p.reconnect?.resetAfterMs || 120000) / 1000)
  $('pTickGuard').checked = p.compatibility?.tickEndGuard !== false
  $('pPhysicsGuard').checked = p.compatibility?.disablePhysicsDuringConfiguration !== false
  $('pPassword').value = ''
  setPasswordStatus(!!p.passwordSet)
  $('deleteProfileBtn').disabled = isNew
  $('selectProfileBtn').disabled = isNew
  $('exportProfileBtn').disabled = isNew
  renderSteps(p.workflow?.steps || [])
  renderDiagnostics(p.diagnostics || null)
}

function syncNewProfileId() {
  if (!editedExistingId && profileIdAuto) $('pId').value = clientSafeId($('pName').value)
}

function profileIdEdited() {
  if (!editedExistingId) profileIdAuto = false
}

function setPasswordStatus(isSet) {
  $('passwordStatus').textContent = isSet ? 'Parole ir saglabāta šim profilam' : 'Parole nav saglabāta šim profilam'
  $('passwordStatus').className = `password-state ${isSet ? 'ok' : 'no'}`
}

function collectProfileSafe() {
  try { return collectProfile() } catch { return clone(editedProfile || baseNewProfile()) }
}

function collectProfile() {
  const steps = collectSteps()
  return {
    id: $('pId').value.trim(),
    name: $('pName').value.trim(),
    connection: {
      host: $('pHost').value.trim(),
      port: Number($('pPort').value),
      version: $('pVersion').value.trim(),
      username: $('pUsername').value.trim(),
      auth: $('pAuth').value
    },
    reconnect: {
      enabled: $('pReconnectEnabled').checked,
      delayMs: Math.max(1, Number($('pReconnectDelay').value) || 15) * 1000,
      backoffEnabled: $('pReconnectBackoff').checked,
      maxDelayMs: Math.max(1, Number($('pReconnectMaxDelay').value) || 300) * 1000,
      maxAttempts: Math.max(1, Number($('pReconnectMaxAttempts').value) || 5),
      resetAfterMs: Math.max(30, Number($('pReconnectResetAfter').value) || 120) * 1000
    },
    compatibility: {
      tickEndGuard: $('pTickGuard').checked,
      disablePhysicsDuringConfiguration: $('pPhysicsGuard').checked
    },
    workflow: { steps }
  }
}

async function validateProfile(showSuccessToast = true) {
  try {
    const body = collectProfile()
    const result = await writeApi('/api/profiles/validate', 'POST', body)
    renderDiagnostics(result.diagnostics)
    if (showSuccessToast) toast(result.diagnostics?.warnings?.length ? 'Profils derīgs, bet ir ieteikumi' : 'Profils izskatās korekts')
    return result
  } catch (err) {
    renderDiagnostics({ valid: false, error: err.message, warnings: [] })
    toast(err.message)
    return null
  }
}

function renderDiagnostics(d) {
  const box = $('diagnosticsBox')
  if (!d) {
    box.classList.add('hidden')
    box.innerHTML = ''
    return
  }
  box.classList.remove('hidden')
  if (d.valid === false) {
    box.className = 'diagnostics error'
    box.innerHTML = `<strong>Konfigurācijas kļūda</strong><div>${esc(d.error || 'Nezināma kļūda')}</div>`
    return
  }
  const warnings = Array.isArray(d.warnings) ? d.warnings : []
  box.className = `diagnostics ${warnings.length ? 'warn' : 'ok'}`
  box.innerHTML = warnings.length
    ? `<strong>Profils ir derīgs, bet pārbaudi šo:</strong>${warnings.map(w => `<div>• ${esc(w)}</div>`).join('')}`
    : '<strong>Profila struktūra ir korekta.</strong><div>Vari saglabāt, izvēlēties profilu un testēt serverī.</div>'
}

async function saveProfile() {
  try {
    const validation = await validateProfile(false)
    if (!validation) return
    const body = collectProfile()
    const result = editedExistingId
      ? await writeApi(`/api/profiles/${encodeURIComponent(editedExistingId)}`, 'PUT', body)
      : await writeApi('/api/profiles', 'POST', body)
    editedExistingId = result.profile.id
    editedProfile = result.profile
    profileIdAuto = false
    fillEditor(result.profile, false)
    await refreshProfiles()
    toast('Profils saglabāts')
  } catch (err) { toast(err.message) }
}

async function savePassword() {
  try {
    if (!editedExistingId) throw new Error('Vispirms saglabā jauno profilu.')
    const password = $('pPassword').value
    if (!password) throw new Error('Ievadi jauno paroli.')
    await writeApi(`/api/profiles/${encodeURIComponent(editedExistingId)}/password`, 'POST', { password })
    $('pPassword').value = ''
    setPasswordStatus(true)
    await refreshProfiles()
    toast('Parole droši saglabāta')
  } catch (err) { toast(err.message) }
}

async function selectEditedProfile() {
  try {
    if (!editedExistingId) throw new Error('Vispirms saglabā profilu.')
    await writeApi(`/api/profiles/${encodeURIComponent(editedExistingId)}/select`)
    await refreshProfiles()
    await refreshDashboard()
    toast('Aktīvais profils nomainīts')
  } catch (err) { toast(err.message) }
}

async function deleteEditedProfile() {
  if (!editedExistingId) return
  if (!confirm(`Dzēst profilu "${$('pName').value}"? Tiks dzēsta arī tā DPAPI parole.`)) return
  try {
    await writeApi(`/api/profiles/${encodeURIComponent(editedExistingId)}`, 'DELETE')
    editedExistingId = null
    editedProfile = null
    await refreshProfiles()
    toast('Profils dzēsts')
  } catch (err) { toast(err.message) }
}

function duplicateProfile() {
  if (!editedProfile && !editedExistingId) return
  const p = collectProfile()
  p.id = `${(p.id || 'profile')}-copy`
  p.name = `${p.name || 'Profils'} kopija`
  p.passwordSet = false
  editedExistingId = null
  editedProfile = p
  profileIdAuto = false
  fillEditor(p, true)
  toast('Izveidota profila kopija — saglabā to')
}

function exportProfile() {
  if (!editedExistingId) return toast('Vispirms saglabā profilu')
  try {
    const p = collectProfile()
    const blob = new Blob([JSON.stringify(p, null, 2) + '\n'], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${clientSafeId(p.id || p.name)}.json`
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
    toast('Profils eksportēts bez paroles')
  } catch (err) { toast(err.message) }
}

function openImport() {
  $('profileImportFile').value = ''
  $('profileImportFile').click()
}

async function importProfileFile(event) {
  const file = event.target.files?.[0]
  if (!file) return
  try {
    const raw = await file.text()
    const p = JSON.parse(raw)
    p.passwordSet = false
    p.id = clientSafeId(p.id || p.name || 'importets-profils')
    if (profilesCache.some(x => x.id === p.id)) p.id = `${p.id}-import`
    editedExistingId = null
    editedProfile = p
    profileIdAuto = false
    fillEditor(p, true)
    toast('Profils ielādēts. Pārbaudi un nospied Saglabāt.')
  } catch (err) { toast(`Importēšana neizdevās: ${err.message}`) }
}

async function saveGlobalSettings() {
  try {
    await writeApi('/api/settings', 'PUT', { autoStart: $('autoStart').checked })
    toast('Iestatījums saglabāts')
  } catch (err) { toast(err.message) }
}

function addCommandStep() {
  const steps = collectStepsSafe()
  const id = uniqueStepId(steps, `step-${steps.length + 1}`)
  const previous = steps.at(-1)
  steps.push({
    id,
    name: `Nosūtīt komandu ${steps.length + 1}`,
    enabled: true,
    trigger: previous ? { type: 'afterStep', afterStepId: previous.id } : { type: 'spawn', occurrence: 1 },
    delayMs: previous ? 2000 : 1000,
    action: { type: 'chat', text: '/' }
  })
  renderSteps(steps)
}

function addAfkStep() {
  const steps = collectStepsSafe()
  const id = uniqueStepId(steps, 'afk')
  const previous = steps.at(-1)
  steps.push({
    id,
    name: 'Atzīmēt kā AFK',
    enabled: true,
    trigger: previous ? { type: 'afterStep', afterStepId: previous.id } : { type: 'spawn', occurrence: 1 },
    delayMs: previous ? 2000 : 1000,
    action: { type: 'markAfk' }
  })
  renderSteps(steps)
}

function uniqueStepId(steps, base) {
  const clean = clientSafeId(base) || 'step'
  let id = clean
  let n = 2
  while (steps.some(s => s.id === id)) id = `${clean}-${n++}`
  return id
}

function stepNameById(steps, id) {
  return steps.find(s => s.id === id)?.name || id || '—'
}

function stepSummary(step, steps) {
  const t = step.trigger || {}
  const a = step.action || {}
  let when = 'nav nosacījuma'
  if (t.type === 'spawn') when = `spawn #${Number(t.occurrence || 1)}`
  if (t.type === 'message') when = `serveris raksta “${(t.any || [])[0] || '...'}”${t.afterStepId ? ` pēc “${stepNameById(steps, t.afterStepId)}”` : ''}`
  if (t.type === 'afterStep') when = `pabeigts “${stepNameById(steps, t.afterStepId)}”`
  if (t.type === 'spawnAfterStep') when = `jauns spawn pēc “${stepNameById(steps, t.afterStepId)}”`
  const then = a.type === 'markAfk' ? 'atzīmēt AFK' : `sūtīt ${a.text || 'komandu'}`
  const delay = Number(step.delayMs || 0) / 1000
  return `KAD ${when} → ${delay ? `gaidīt ${delay}s → ` : ''}${then}`
}

function renderSteps(steps) {
  const allIds = steps.map(s => s.id)
  $('stepsEditor').innerHTML = steps.length ? steps.map((step, index) => {
    const t = step.trigger || { type: 'message' }
    const a = step.action || { type: 'chat' }
    return `
    <div class="step-card" data-index="${index}">
      <div class="step-head">
        <div class="step-num">${index + 1}</div>
        <div class="step-title-wrap">
          <input class="step-name" value="${esc(step.name || '')}" placeholder="Soļa nosaukums">
          <div class="step-summary">${esc(stepSummary(step, steps))}</div>
        </div>
        <div class="step-buttons">
          <button class="small" onclick="moveStep(${index},-1)" title="Uz augšu">↑</button>
          <button class="small" onclick="moveStep(${index},1)" title="Uz leju">↓</button>
          <button class="small danger" onclick="removeStep(${index})" title="Dzēst">×</button>
        </div>
      </div>
      <div class="step-body">
        <label class="check"><input class="step-enabled" type="checkbox" ${step.enabled !== false ? 'checked' : ''}> Solis ieslēgts</label>
        <label>Pirms darbības gaidīt (sek.)<input class="step-delay" type="number" min="0" max="300" step="0.1" value="${(Number(step.delayMs || 0) / 1000)}"></label>

        <label class="full">KAD šo soli aktivizēt?<select class="trigger-type" onfocus="this.dataset.prev=this.value" onchange="changeTriggerType(${index},this.dataset.prev,this.value)">
          <option value="spawn" ${t.type === 'spawn' ? 'selected' : ''}>Kad ALT spawn / ielādējas pasaulē</option>
          <option value="message" ${t.type === 'message' ? 'selected' : ''}>Kad serveris uzraksta noteiktu tekstu</option>
          <option value="afterStep" ${t.type === 'afterStep' ? 'selected' : ''}>Pēc iepriekšējā workflow soļa</option>
          <option value="spawnAfterStep" ${t.type === 'spawnAfterStep' ? 'selected' : ''}>Kad pēc iepriekšējā soļa notiek jauns spawn</option>
        </select></label>
        ${triggerFields(t, allIds, step.id, steps)}

        <label>DARBĪBA<select class="action-type" onfocus="this.dataset.prev=this.value" onchange="changeActionType(${index},this.dataset.prev,this.value)">
          <option value="chat" ${a.type === 'chat' ? 'selected' : ''}>Nosūtīt komandu / čata tekstu</option>
          <option value="markAfk" ${a.type === 'markAfk' ? 'selected' : ''}>Atzīmēt workflow kā AFK pabeigtu</option>
        </select></label>
        ${a.type === 'chat' ? `<label class="wide">Ko nosūtīt?<input class="action-text" value="${esc(a.text || '')}" placeholder="/login {password}"><span class="field-help">Mainīgie: {password}, {username}, {host}, {port}</span></label>` : '<div class="wide action-explain">Šis ir profila gala stāvoklis. Manager turpina uzturēt Minecraft savienojumu un rāda AFK laiku.</div>'}

        <details class="step-tech full"><summary>Tehniskie soļa iestatījumi</summary><div class="step-tech-body"><label>Step ID<input class="step-id" value="${esc(step.id || '')}"></label><div class="muted small-text">ID izmanto soļu savstarpējām atsaucēm. Maini tikai tad, ja zini, kāpēc tas nepieciešams.</div></div></details>
      </div>
    </div>`
  }).join('') : '<div class="empty-workflow"><strong>Workflow ir tukšs.</strong><span>ALT var pieslēgties serverim izpētes režīmā. Kad zini nepieciešamās komandas un servera tekstus, pievieno pirmo komandu vai AFK beigas.</span></div>'
}

function refOptions(allIds, currentId, selected, steps, allowNone = false) {
  const none = allowNone ? '<option value="">Nav — teksts var aktivizēt soli jebkurā brīdī</option>' : ''
  return none + allIds.filter(id => id !== currentId).map(id => `<option value="${esc(id)}" ${id === selected ? 'selected' : ''}>${esc(stepNameById(steps, id))}</option>`).join('')
}

function triggerFields(t, allIds, currentId, steps) {
  if (t.type === 'spawn') {
    return `<label>Kurš spawn?<input class="trigger-occurrence" type="number" min="1" value="${Number(t.occurrence || 1)}"><span class="field-help">Parasti 1. Pēc servera/pasaules pārejām spawn skaits palielinās.</span></label><div></div>`
  }
  if (t.type === 'afterStep') {
    return `<label class="wide">Pēc kura soļa?<select class="trigger-after">${refOptions(allIds, currentId, t.afterStepId, steps)}</select><span class="field-help">Šis variants neprasa servera ziņojumu vai jaunu spawn. Noder vienkāršām komandu ķēdēm.</span></label>`
  }
  if (t.type === 'spawnAfterStep') {
    return `<label>Pēc kura soļa?<select class="trigger-after">${refOptions(allIds, currentId, t.afterStepId, steps)}</select></label><label class="check"><input class="trigger-config" type="checkbox" ${t.requireConfigurationCycle !== false ? 'checked' : ''}> Prasīt CONFIGURATION ciklu</label>`
  }
  return `<label>Teksta salīdzināšana<select class="trigger-match"><option value="contains" ${t.match !== 'equals' ? 'selected' : ''}>Ziņojums satur tekstu</option><option value="equals" ${t.match === 'equals' ? 'selected' : ''}>Ziņojums ir precīzi vienāds</option></select></label>
    <label class="wide">Kādu servera tekstu gaidīt?<textarea class="trigger-any" rows="3" placeholder="Successfully logged in\nalready logged in">${esc((t.any || []).join('\n'))}</textarea><span class="field-help">Katru iespējamo variantu raksti jaunā rindā. Dzīvajā logā uzklikšķini uz servera rindas, lai nokopētu tekstu.</span></label>
    <label class="full">Aktivizēt šo tekstu tikai pēc konkrēta soļa?<select class="trigger-message-after">${refOptions(allIds, currentId, t.afterStepId || '', steps, true)}</select></label>`
}

function collectStepsSafe() {
  try { return collectSteps() } catch { return editedProfile?.workflow?.steps ? clone(editedProfile.workflow.steps) : [] }
}

function collectSteps() {
  return [...document.querySelectorAll('.step-card')].map(card => {
    const triggerType = card.querySelector('.trigger-type').value
    const actionType = card.querySelector('.action-type').value
    const trigger = { type: triggerType }

    if (triggerType === 'spawn') {
      trigger.occurrence = Number(card.querySelector('.trigger-occurrence').value || 1)
    } else if (triggerType === 'afterStep') {
      trigger.afterStepId = card.querySelector('.trigger-after')?.value || ''
    } else if (triggerType === 'spawnAfterStep') {
      trigger.afterStepId = card.querySelector('.trigger-after')?.value || ''
      trigger.requireConfigurationCycle = !!card.querySelector('.trigger-config')?.checked
    } else {
      trigger.match = card.querySelector('.trigger-match').value
      trigger.caseInsensitive = true
      trigger.any = card.querySelector('.trigger-any').value.split(/\r?\n/).map(v => v.trim()).filter(Boolean)
      const after = card.querySelector('.trigger-message-after')?.value || ''
      if (after) trigger.afterStepId = after
    }

    const action = { type: actionType }
    if (actionType === 'chat') action.text = card.querySelector('.action-text').value.trim()

    return {
      id: card.querySelector('.step-id').value.trim(),
      name: card.querySelector('.step-name').value.trim(),
      enabled: card.querySelector('.step-enabled').checked,
      delayMs: Math.max(0, Number(card.querySelector('.step-delay').value || 0) * 1000),
      trigger,
      action
    }
  })
}

function changeTriggerType(index, previousType, newType) {
  const card = document.querySelector(`.step-card[data-index="${index}"]`)
  const select = card?.querySelector('.trigger-type')
  if (!card || !select) return

  select.value = previousType || 'message'
  const steps = collectSteps()
  const previous = steps[index - 1]?.id || steps.find((s, i) => i !== index)?.id || ''

  if (newType === 'spawn') {
    steps[index].trigger = { type: 'spawn', occurrence: 1 }
  } else if (newType === 'afterStep') {
    steps[index].trigger = { type: 'afterStep', afterStepId: previous }
  } else if (newType === 'spawnAfterStep') {
    steps[index].trigger = { type: 'spawnAfterStep', afterStepId: previous, requireConfigurationCycle: true }
  } else {
    steps[index].trigger = { type: 'message', match: 'contains', caseInsensitive: true, any: ['servera teksts'], ...(previous ? { afterStepId: previous } : {}) }
  }

  renderSteps(steps)
}

function changeActionType(index, previousType, newType) {
  const card = document.querySelector(`.step-card[data-index="${index}"]`)
  const select = card?.querySelector('.action-type')
  if (!card || !select) return

  select.value = previousType || 'chat'
  const steps = collectSteps()
  steps[index].action = newType === 'markAfk'
    ? { type: 'markAfk' }
    : { type: 'chat', text: '/' }
  renderSteps(steps)
}

function removeStep(index) {
  const steps = collectSteps()
  const removed = steps[index]
  const dependents = steps.filter((s, i) => i !== index && s.trigger?.afterStepId === removed.id)
  if (dependents.length && !confirm(`Uz šo soli atsaucas vēl ${dependents.length} solis/soļi. Dzēšot to, profila pārbaude prasīs pārkārtot atsauces. Turpināt?`)) return
  steps.splice(index, 1)
  renderSteps(steps)
}

function moveStep(index, delta) {
  const steps = collectSteps()
  const other = index + delta
  if (other < 0 || other >= steps.length) return
  ;[steps[index], steps[other]] = [steps[other], steps[index]]
  renderSteps(steps)
}

$('logs').addEventListener('click', async event => {
  const line = event.target.closest('.log-server[data-copy]')
  if (!line) return
  try {
    await navigator.clipboard.writeText(line.dataset.copy || '')
    toast('Servera teksts nokopēts workflow nosacījumam')
  } catch { toast('Kopēšana neizdevās') }
})

refreshDashboard()
refreshProfiles()
setInterval(refreshDashboard, 1000)
