const fs = require('fs')
const path = require('path')
const { execFileSync, spawnSync } = require('child_process')
const { safeId } = require('./profile-store')

class SecretStore {
  constructor(rootDir, options = {}) {
    this.rootDir = rootDir
    this.secretsDir = options.secretsDir ? path.resolve(options.secretsDir) : path.join(rootDir, 'data', 'secrets')
    this.decryptScript = path.join(rootDir, 'decrypt-password.ps1')
    this.saveScript = path.join(rootDir, 'save-secret.ps1')
    fs.mkdirSync(this.secretsDir, { recursive: true })
  }

  fileFor(profileId) {
    return path.join(this.secretsDir, `${safeId(profileId)}.dat`)
  }

  migrateLegacySecret(profileId = 'knt-survival') {
    const legacy = path.join(this.rootDir, 'secret.dat')
    const target = this.fileFor(profileId)
    if (fs.existsSync(legacy) && !fs.existsSync(target)) {
      fs.copyFileSync(legacy, target)
      return true
    }
    return false
  }

  has(profileId) {
    const file = this.fileFor(profileId)
    return fs.existsSync(file) && fs.statSync(file).size > 0
  }

  get(profileId) {
    const file = this.fileFor(profileId)
    if (!fs.existsSync(file)) {
      throw new Error('Šim profilam parole vēl nav saglabāta.')
    }
    if (!fs.existsSync(this.decryptScript)) {
      throw new Error(`Nav atrasts ${path.basename(this.decryptScript)}.`)
    }

    const password = execFileSync(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', this.decryptScript,
        '-SecretFile', file
      ],
      { encoding: 'utf8', windowsHide: true }
    ).trim()

    if (!password) throw new Error('Saglabātā parole ir tukša.')
    return password
  }

  set(profileId, password) {
    const value = String(password || '')
    if (!value) throw new Error('Parole nedrīkst būt tukša.')
    if (!fs.existsSync(this.saveScript)) {
      throw new Error(`Nav atrasts ${path.basename(this.saveScript)}.`)
    }

    const result = spawnSync(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', this.saveScript,
        '-SecretFile', this.fileFor(profileId)
      ],
      {
        input: value,
        encoding: 'utf8',
        windowsHide: true
      }
    )

    if (result.status !== 0) {
      throw new Error((result.stderr || result.stdout || 'Paroles saglabāšana neizdevās.').trim())
    }
  }

  delete(profileId) {
    const file = this.fileFor(profileId)
    if (fs.existsSync(file)) fs.unlinkSync(file)
  }
}

module.exports = SecretStore
