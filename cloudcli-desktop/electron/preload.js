const { contextBridge } = require('electron')

contextBridge.exposeInMainWorld('electronEnv', {
  platform: process.platform,
})

// 默认语言强制设置为 zh-CN（只在版本标记变化时重置一次，之后尊重用户在设置里的选择）
const LANG_BUILD_ID = 'zh-CN-default-v1'
if (localStorage.getItem('langBuildId') !== LANG_BUILD_ID) {
  localStorage.setItem('userLanguage', 'zh-CN')
  localStorage.setItem('langBuildId', LANG_BUILD_ID)
}

// 全窗口文件拖放：让整个 Electron 窗口都能接收拖入的文件
// 把文件信息通过 CustomEvent 广播给 React，不依赖 react-dropzone 的落点
window.addEventListener('dragover', (e) => {
  e.preventDefault()
  e.stopPropagation()
}, false)

window.addEventListener('dragleave', (e) => {
  // 只有真正离开窗口才触发（relatedTarget 为 null）
  if (!e.relatedTarget) {
    window.dispatchEvent(new CustomEvent('electron-drag-leave'))
  }
}, false)

window.addEventListener('drop', (e) => {
  e.preventDefault()
  e.stopPropagation()
  const files = Array.from(e.dataTransfer?.files ?? [])
  if (files.length > 0) {
    window.dispatchEvent(new CustomEvent('electron-file-drop', { detail: { files } }))
  }
}, false)
