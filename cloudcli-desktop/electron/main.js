const { app, BrowserWindow, shell, dialog, utilityProcess } = require('electron')
const path = require('path')
const net = require('net')
const http = require('http')

const isDev = !app.isPackaged

// 找一个可用端口
function findFreePort(start = 3001) {
  return new Promise((resolve, reject) => {
    const server = net.createServer()
    server.unref()
    server.on('error', () => findFreePort(start + 1).then(resolve, reject))
    server.listen(start, () => {
      const { port } = server.address()
      server.close(() => resolve(port))
    })
  })
}

// 等待服务器健康检查通过（最多等 15 秒）
function waitForServer(port, retries = 30) {
  return new Promise((resolve, reject) => {
    let attempts = 0
    const check = () => {
      const req = http.get(`http://127.0.0.1:${port}/health`, (res) => {
        if (res.statusCode === 200) return resolve()
        retry()
      })
      req.on('error', retry)
      req.setTimeout(1000, () => { req.destroy(); retry() })
    }
    const retry = () => {
      if (++attempts >= retries) return reject(new Error('服务器启动超时，请检查日志'))
      setTimeout(check, 500)
    }
    check()
  })
}

let serverProcess = null
let mainWindow = null
let serverPort = null

async function startServer(port) {
  const serverEntry = isDev
    ? path.join(__dirname, '..', 'webapp', 'server', 'index.js')
    : path.join(process.resourcesPath, 'webapp', 'server', 'index.js')

  // 使用 utilityProcess.fork()：Electron 官方推荐的子进程方式，
  // 天然支持 ES Module、原生模块，stdio pipe 可靠
  serverProcess = utilityProcess.fork(serverEntry, [], {
    env: {
      ...process.env,
      SERVER_PORT: String(port),
      HOST: '127.0.0.1',
      NODE_ENV: 'production',
      VITE_IS_PLATFORM: 'true',
      DIST_PATH: isDev
        ? path.join(__dirname, '..', 'webapp', 'dist')
        : path.join(process.resourcesPath, 'webapp', 'dist'),
    },
    stdio: 'pipe',
  })

  serverProcess.stdout.on('data', (d) => process.stdout.write(`[server] ${d}`))
  serverProcess.stderr.on('data', (d) => process.stderr.write(`[server] ${d}`))

  serverProcess.on('exit', (code) => {
    if (!app.isQuitting && code !== 0 && code !== null) {
      dialog.showErrorBox(
        '后台服务异常退出',
        `退出码: ${code}\n请重启应用`
      )
    }
  })
}

// platform 模式需要 DB 中至少存在一个用户，自动创建
async function ensureDefaultUser(port) {
  try {
    const res = await new Promise((resolve, reject) => {
      const req = http.get(`http://127.0.0.1:${port}/api/auth/status`, resolve)
      req.on('error', reject)
    })
    let body = ''
    res.on('data', (d) => { body += d })
    await new Promise((resolve) => res.on('end', resolve))
    const status = JSON.parse(body)
    if (!status.needsSetup) return // 已有用户

    // 创建默认用户（密码不对外暴露，仅供 platform 模式存档）
    await new Promise((resolve, reject) => {
      const payload = JSON.stringify({ username: 'local', password: 'claudelocal' })
      const req = http.request({
        hostname: '127.0.0.1', port, path: '/api/auth/register',
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
      }, resolve)
      req.on('error', reject)
      req.write(payload)
      req.end()
    })
  } catch (e) {
    console.error('[main] ensureDefaultUser error:', e.message)
  }
}

async function createWindow(port) {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    title: 'Claude Code UI',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  // 拦截外部链接，用系统浏览器打开
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://127.0.0.1') || url.startsWith('http://localhost')) {
      return { action: 'allow' }
    }
    shell.openExternal(url)
    return { action: 'deny' }
  })

  // 阻止拖入文件时导航到 file:// URL（否则整个页面会被文件替换）
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith(`http://127.0.0.1:${port}`)) {
      event.preventDefault()
    }
  })

  mainWindow.loadURL(`http://127.0.0.1:${port}`)

  // DevTools 仅在显式设置环境变量时打开
  if (process.env.ELECTRON_DEVTOOLS) {
    mainWindow.webContents.openDevTools({ mode: 'detach' })
  }

  mainWindow.on('closed', () => { mainWindow = null })
}

app.whenReady().then(async () => {
  try {
    serverPort = await findFreePort(3001)
    await startServer(serverPort)
    await waitForServer(serverPort)
    await ensureDefaultUser(serverPort)
    await createWindow(serverPort)
  } catch (err) {
    dialog.showErrorBox('Claude Code UI 启动失败', err.message)
    app.quit()
  }
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.isQuitting = true
    if (serverProcess) serverProcess.kill()
    app.quit()
  }
})

app.on('activate', () => {
  if (mainWindow === null && serverPort) {
    createWindow(serverPort).catch(console.error)
  }
})

app.on('before-quit', () => {
  app.isQuitting = true
  if (serverProcess) serverProcess.kill()
})
