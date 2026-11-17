<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import {
  supabase, formatFileSize, formatDuration,
  getCurrentUser, uploadPrivateAudio,
  type Project, type Template,
} from '../lib/supabase'
import {
  Upload,
  Mic,
  FileAudio,
  X,
  Play,
  Pause,
  Trash2,
  Loader2,
  ChevronDown,
  Tag as TagIcon,
  AlertCircle,
  Square,
  FileText,
} from 'lucide-vue-next'

const router = useRouter()
const route = useRoute()
const pendingAudioFile = ref<{ base64: string; name: string; size: number } | null>(null)
const audioFileLoaded = ref(false)

const mode = ref<'import' | 'record'>('import')
const projects = ref<Project[]>([])
const templates = ref<Template[]>([])
const selectedProject = ref<string>('')
const selectedTemplate = ref<string>('')
const title = ref('')
const notes = ref('')
const tags = ref<string[]>([])
const tagInput = ref('')
const language = ref('auto')
const speakerSeparation = ref(false)

const file = ref<File | null>(null)
const fileDuration = ref(0)
const dragOver = ref(false)
const fileError = ref('')
const fileInput = ref<HTMLInputElement | null>(null)

const isRecording = ref(false)
const recordingTime = ref(0)
const mediaRecorder = ref<MediaRecorder | null>(null)
const audioChunks = ref<Blob[]>([])
const audioStream = ref<MediaStream | null>(null)
const audioUrl = ref('')
const recordingTimer = ref<number | null>(null)
const analyser = ref<AnalyserNode | null>(null)
const audioContext = ref<AudioContext | null>(null)
const canvasRef = ref<HTMLCanvasElement | null>(null)
const animationId = ref<number | null>(null)
const previewAudio = ref<HTMLAudioElement | null>(null)
const isPlaying = ref(false)

const MAX_FILE_SIZE = 500 * 1024 * 1024
const ACCEPTED_FORMATS = ['mp3', 'm4a', 'wav', 'webm', 'ogg', 'flac', 'aac', 'wma']

const selectedTemplateData = computed(() => templates.value.find(t => t.id === selectedTemplate.value) || null)

const hasAudio = computed(() => !!file.value || !!audioUrl.value)
const audioFileName = computed(() => file.value?.name || (audioUrl.value ? '录音文件.webm' : ''))
const audioFileSize = computed(() => file.value?.size || (audioChunks.value.length ? audioChunks.value.reduce((a, b) => a + b.size, 0) : 0))

watch(() => route.query, (q) => {
  if (q.mode === 'record') mode.value = 'record'
  if (q.template) {
    selectedTemplate.value = q.template as string
    if (q.tpl_name && !title.value) {
      const d = new Date()
      const dateStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
      title.value = `${q.tpl_name}-${dateStr}`
    }
  }
}, { immediate: true })


// ============ 【新增】从 sessionStorage 读取待导入文件 ============
function loadPendingAudio() {
  try {
    const base64 = sessionStorage.getItem('pendingAudioFile')
    const name = sessionStorage.getItem('pendingAudioFileName')
    const size = sessionStorage.getItem('pendingAudioFileSize')
    
    if (base64 && name && size) {
      pendingAudioFile.value = { base64, name, size: parseInt(size) }
      
      // 自动填充标题（去掉扩展名）
      if (!title.value) {
        const titleWithoutExt = name.replace(/\.[^.]+$/, '')
        title.value = titleWithoutExt
      }
      
      audioFileLoaded.value = true
      
      // 将 Base64 转为 File 对象
      convertBase64ToFile(base64, name)
    }
  } catch (error) {
    console.error('读取待导入文件失败:', error)
  }
}

function convertBase64ToFile(base64: string, fileName: string) {
  try {
    const match = base64.match(/^data:([^;]+);base64,(.+)$/)
    if (!match) return
    
    const mimeType = match[1]
    const base64Data = match[2]
    const binaryString = atob(base64Data)
    const bytes = new Uint8Array(binaryString.length)
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i)
    }
    const blob = new Blob([bytes], { type: mimeType })
    const fileObj = new File([blob], fileName, { type: mimeType })
    
    // ============ 【关键修复】赋值 ============
    file.value = fileObj
    console.log('✅ file.value 已赋值:', file.value?.name, '大小:', file.value?.size)
    
    // ============ 【新增】读取文件时长 ============
    const audio = new Audio()
    audio.preload = 'metadata'
    audio.src = URL.createObjectURL(fileObj)
    audio.onloadedmetadata = () => {
      fileDuration.value = audio.duration || 0
      console.log('🎵 文件时长:', fileDuration.value)
      // ============ 【新增】时长获取后再次检查 ============
      console.log('📊 hasAudio 最终值:', hasAudio.value)
    }
    audio.onerror = () => {
      console.error('❌ 音频加载失败:', audio.error)
    }
    
    mode.value = 'import'
    console.log('📋 模式切换到: import')
    
    // ============ 【新增】强制触发响应式更新 ============
    // 触发计算属性重新计算
    nextTick(() => {
      console.log('📊 nextTick 后 hasAudio:', hasAudio.value)
      console.log('📊 file.value:', file.value)
    })
    
  } catch (error) {
    console.error('❌ 转换文件失败:', error)
  }
}

// ============ 【新增】清除待导入文件 ============
function clearPendingAudio() {
  sessionStorage.removeItem('pendingAudioFile')
  sessionStorage.removeItem('pendingAudioFileName')
  sessionStorage.removeItem('pendingAudioFileSize')
  pendingAudioFile.value = null
  audioFileLoaded.value = false
}


async function loadData() {
  const [projRes, tplRes] = await Promise.all([
    supabase.from('projects').select('*').order('name'),
    supabase.from('templates').select('*').order('name'),
  ])
  projects.value = projRes.data || []
  templates.value = tplRes.data || []
}

function onDrop(e: DragEvent) {
  e.preventDefault()
  dragOver.value = false
  const f = e.dataTransfer?.files?.[0]
  if (f) handleFile(f)
}

function onFileSelected(e: Event) {
  const input = e.target as HTMLInputElement
  if (input.files?.[0]) handleFile(input.files[0])
}

function handleFile(f: File) {
  fileError.value = ''
  const ext = f.name.split('.').pop()?.toLowerCase() || ''
  if (!ACCEPTED_FORMATS.includes(ext)) {
    fileError.value = `不支持的格式: .${ext}，请上传 ${ACCEPTED_FORMATS.join(', ')} 格式的文件`
    return
  }
  if (f.size > MAX_FILE_SIZE) {
    fileError.value = `文件过大 (${formatFileSize(f.size)})，最大支持 500MB`
    return
  }
  file.value = f
  if (!title.value) title.value = f.name.replace(/\.[^.]+$/, '')

  const audio = new Audio()
  audio.preload = 'metadata'
  audio.src = URL.createObjectURL(f)
  audio.onloadedmetadata = () => {
    fileDuration.value = audio.duration || 0
  }
}

function removeFile() {
  file.value = null
  fileDuration.value = 0
  fileError.value = ''
  if (fileInput.value) fileInput.value.value = ''
}

function addTag() {
  const t = tagInput.value.trim()
  if (t && !tags.value.includes(t)) {
    tags.value.push(t)
    tagInput.value = ''
  }
}

function removeTag(t: string) {
  tags.value = tags.value.filter(x => x !== t)
}

async function startRecording() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    audioStream.value = stream
    audioChunks.value = []

    const recorder = new MediaRecorder(stream)
    mediaRecorder.value = recorder
    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) audioChunks.value.push(e.data)
    }
    recorder.onstop = () => {
      const blob = new Blob(audioChunks.value, { type: 'audio/webm' })
      audioUrl.value = URL.createObjectURL(blob)
      fileDuration.value = recordingTime.value
      const f = new File([blob], `录音_${Date.now()}.webm`, { type: 'audio/webm' })
      file.value = f
      if (!title.value) title.value = `录音任务 ${new Date().toLocaleString('zh-CN')}`
    }

    recorder.start()
    isRecording.value = true
    recordingTime.value = 0
    recordingTimer.value = window.setInterval(() => {
      recordingTime.value++
    }, 1000)

    audioContext.value = new AudioContext()
    const source = audioContext.value.createMediaStreamSource(stream)
    analyser.value = audioContext.value.createAnalyser()
    analyser.value.fftSize = 256
    source.connect(analyser.value)
    drawWaveform()
  } catch (err) {
    fileError.value = '无法访问麦克风，请检查浏览器权限设置'
  }
}

function drawWaveform() {
  if (!canvasRef.value || !analyser.value) return
  const canvas = canvasRef.value
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  const bufferLength = analyser.value.frequencyBinCount
  const dataArray = new Uint8Array(bufferLength)

  const draw = () => {
    if (!isRecording.value) return
    animationId.value = requestAnimationFrame(draw)
    analyser.value!.getByteFrequencyData(dataArray)

    ctx.clearRect(0, 0, canvas.width, canvas.height)
    const barWidth = canvas.width / bufferLength * 2.5
    let x = 0
    for (let i = 0; i < bufferLength; i++) {
      const barHeight = (dataArray[i] / 255) * canvas.height
      const gradient = ctx.createLinearGradient(0, canvas.height, 0, canvas.height - barHeight)
      gradient.addColorStop(0, '#3b82f6')
      gradient.addColorStop(1, '#06b6d4')
      ctx.fillStyle = gradient
      ctx.fillRect(x, canvas.height - barHeight, barWidth - 1, barHeight)
      x += barWidth
    }
  }
  draw()
}

function stopRecording() {
  if (mediaRecorder.value && mediaRecorder.value.state !== 'inactive') {
    mediaRecorder.value.stop()
  }
  audioStream.value?.getTracks().forEach(t => t.stop())
  isRecording.value = false
  if (recordingTimer.value) clearInterval(recordingTimer.value)
  if (animationId.value) cancelAnimationFrame(animationId.value)
  audioContext.value?.close()
}

function togglePlay() {
  if (!previewAudio.value) {
    previewAudio.value = new Audio(audioUrl.value || (file.value ? URL.createObjectURL(file.value) : ''))
  }
  if (isPlaying.value) {
    previewAudio.value.pause()
    isPlaying.value = false
  } else {
    previewAudio.value.play()
    isPlaying.value = true
    previewAudio.value.onended = () => { isPlaying.value = false }
  }
}

function reRecord() {
  if (audioUrl.value) URL.revokeObjectURL(audioUrl.value)
  audioUrl.value = ''
  file.value = null
  audioChunks.value = []
  recordingTime.value = 0
  fileDuration.value = 0
  isPlaying.value = false
  previewAudio.value = null
}

const creating = ref(false)


// ============ 修复 startProcessing ============
async function startProcessing() {
  if (!hasAudio.value) {
    fileError.value = '请先导入音频文件或录制音频'
    return
  }
  creating.value = true
  try {
    const currentUser = await getCurrentUser()
    if (!currentUser) {
      fileError.value = '登录状态已失效，请重新登录'
      creating.value = false
      router.push('/login')
      return
    }

    let audioStoragePath: string | null = null
    if (file.value) {
      audioStoragePath = await uploadPrivateAudio(currentUser.id, file.value)
    }

    const { data, error } = await supabase
      .from('tasks')
      .insert({
        user_id: currentUser.id,
        title: title.value || audioFileName.value || '未命名任务',
        project_id: selectedProject.value || null,
        template_id: selectedTemplate.value || null,
        audio_file_name: audioFileName.value,
        audio_file_size: audioFileSize.value,
        audio_duration: fileDuration.value || recordingTime.value,
        audio_storage_path: audioStoragePath,
        language: language.value,
        speaker_separation: speakerSeparation.value,
        notes: notes.value || null,
        status: 'queued',
      })
      .select()
      .single()

    if (error) throw error

    if (tags.value.length > 0 && data) {
      for (const tagName of tags.value) {
        const { data: existing } = await supabase
          .from('tags')
          .select('id')
          .eq('user_id', currentUser.id)
          .eq('name', tagName)
          .maybeSingle()
        let tagId = existing?.id
        if (!tagId) {
          const { data: newTag } = await supabase
            .from('tags')
            .insert({ user_id: currentUser.id, name: tagName })
            .select()
            .single()
          tagId = newTag?.id
        }
        if (tagId) {
          await supabase.from('task_tags').insert({ task_id: data.id, tag_id: tagId })
        }
      }
    }

    // ============ 【修复】清除缓存，重置状态，跳转一次 ============
    clearPendingAudio()
    creating.value = false
    router.push(`/tasks/${data.id}/process`)
    
  } catch (err: any) {
    fileError.value = err?.message || '创建任务失败，请重试'
    creating.value = false
  }
}

onMounted(() => {
  console.log('📄 新建页面已加载')
  loadPendingAudio()
  loadData()
})
</script>

<template>
  <div class="new-task">
    <div class="page-header">
      <h1>新建录音任务</h1>
      <p>导入音频文件或实时录音，AI 将自动转写并生成纪要</p>
    </div>
    <div v-if="audioFileLoaded && pendingAudioFile" class="file-loaded-banner">
      <div class="banner-content">
        <span class="banner-icon">📁</span>
        <span class="banner-text">
          已导入音频：<strong>{{ pendingAudioFile.name }}</strong>
          （{{ (pendingAudioFile.size / 1024 / 1024).toFixed(2) }} MB）
        </span>
        <button class="banner-remove" @click="clearPendingAudio">✕</button>
      </div>
    </div>
    <div class="two-column">
      <!-- Left: Mode selection & basic info -->
      <div class="left-panel">
        <div class="mode-tabs">
          <button
            class="mode-tab"
            :class="{ active: mode === 'import' }"
            @click="mode = 'import'"
          >
            <Upload :size="18" />
            导入音频文件
          </button>
          <button
            class="mode-tab"
            :class="{ active: mode === 'record' }"
            @click="mode = 'record'"
          >
            <Mic :size="18" />
            实时录音
          </button>
        </div>

        <!-- Import mode -->
        <div v-if="mode === 'import'" class="dropzone-container">
          <div
            class="dropzone"
            :class="{ active: dragOver, has: hasAudio }"
            @dragover.prevent="dragOver = true"
            @dragleave.prevent="dragOver = false"
            @drop="onDrop"
            @click="!hasAudio && fileInput?.click()"
          >
            <input ref="fileInput" type="file" accept="audio/*" style="display:none" @change="onFileSelected" />
            <template v-if="!hasAudio">
              <div class="dropzone-icon">
                <Upload :size="32" />
              </div>
              <p class="dropzone-text">拖拽音频文件到此区域</p>
              <p class="dropzone-hint">支持 mp3 / m4a / wav / webm / ogg / flac / aac</p>
            </template>
            <template v-else>
              <div class="file-preview">
                <FileAudio :size="28" class="file-icon" />
                <div class="file-info">
                  <span class="file-name">{{ audioFileName }}</span>
                  <span class="file-meta">{{ formatFileSize(audioFileSize) }} · {{ formatDuration(fileDuration) }}</span>
                </div>
                <button class="remove-btn" @click.stop="removeFile">
                  <X :size="16" />
                </button>
              </div>
            </template>
          </div>
          <div v-if="fileError" class="error-banner">
            <AlertCircle :size="16" />
            {{ fileError }}
          </div>
        </div>

        <!-- Record mode -->
        <div v-else class="record-area">
          <div v-if="!isRecording && !hasAudio" class="record-idle">
            <div class="record-btn-large" @click="startRecording">
              <Mic :size="36" />
            </div>
            <p class="record-hint">点击开始录音</p>
          </div>

          <div v-if="isRecording" class="record-active">
            <canvas ref="canvasRef" class="waveform-canvas" width="400" height="120" />
            <div class="record-timer">
              <span class="recording-dot" />
              {{ formatDuration(recordingTime) }}
            </div>
            <button class="stop-btn" @click="stopRecording">
              <Square :size="18" />
              停止录音
            </button>
          </div>

          <div v-if="hasAudio && !isRecording" class="record-preview">
            <div class="file-preview">
              <FileAudio :size="28" class="file-icon" />
              <div class="file-info">
                <span class="file-name">{{ audioFileName }}</span>
                <span class="file-meta">{{ formatFileSize(audioFileSize) }} · {{ formatDuration(fileDuration) }}</span>
              </div>
            </div>
            <div class="preview-controls">
              <button class="play-btn" @click="togglePlay">
                <component :is="isPlaying ? Pause : Play" :size="18" />
                {{ isPlaying ? '暂停' : '试听' }}
              </button>
              <button class="re-record-btn" @click="reRecord">
                <Trash2 :size="16" />
                重新录制
              </button>
            </div>
          </div>
        </div>

        <!-- Basic info -->
        <div class="divider" />
        <div class="form-section">
          <label class="form-label">任务标题</label>
          <input v-model="title" type="text" class="form-input" placeholder="如不填，将自动使用文件名或录音时间" />

          <label class="form-label">项目分类</label>
          <div class="select-wrapper">
            <select v-model="selectedProject" class="form-select">
              <option value="">无分类</option>
              <option v-for="p in projects" :key="p.id" :value="p.id">{{ p.name }}</option>
            </select>
            <ChevronDown :size="16" class="select-arrow" />
          </div>

          <label class="form-label">标签</label>
          <div class="tag-input-area">
            <div class="tag-list">
              <span v-for="t in tags" :key="t" class="tag-chip">
                {{ t }}
                <button class="tag-remove" @click="removeTag(t)"><X :size="12" /></button>
              </span>
            </div>
            <div class="tag-input-row">
              <TagIcon :size="15" class="tag-icon" />
              <input
                v-model="tagInput"
                type="text"
                class="tag-input"
                placeholder="输入标签后回车添加"
                @keydown.enter.prevent="addTag"
              />
            </div>
          </div>

          <label class="form-label">备注</label>
          <textarea v-model="notes" class="form-textarea" rows="3" placeholder="可选，添加任务备注" />
        </div>
      </div>

      <!-- Right: Settings & preview -->
      <div class="right-panel">
        <h3 class="panel-title">录音设置</h3>

        <div v-if="hasAudio" class="audio-info-card">
          <div class="info-row">
            <span class="info-label">文件名</span>
            <span class="info-value">{{ audioFileName }}</span>
          </div>
          <div class="info-row">
            <span class="info-label">文件大小</span>
            <span class="info-value">{{ formatFileSize(audioFileSize) }}</span>
          </div>
          <div class="info-row">
            <span class="info-label">时长</span>
            <span class="info-value">{{ formatDuration(fileDuration) }}</span>
          </div>
        </div>

        <div v-else class="no-audio-hint">
          <FileAudio :size="32" />
          <p>请先导入音频或开始录音</p>
        </div>

        <div class="divider" />

        <label class="form-label">识别语言</label>
        <div class="select-wrapper">
          <select v-model="language" class="form-select">
            <option value="auto">自动检测</option>
            <option value="zh">中文</option>
            <option value="en">英语</option>
            <option value="ja">日语</option>
          </select>
          <ChevronDown :size="16" class="select-arrow" />
        </div>

        <label class="form-label">说话人分离</label>
        <div class="toggle-row">
          <button
            class="toggle-btn"
            :class="{ active: speakerSeparation }"
            @click="speakerSeparation = true"
          >开启</button>
          <button
            class="toggle-btn"
            :class="{ active: !speakerSeparation }"
            @click="speakerSeparation = false"
          >关闭</button>
        </div>

        <label class="form-label">纪要模板</label>
        <div class="select-wrapper">
          <select v-model="selectedTemplate" class="form-select">
            <option value="">不使用模板</option>
            <option v-for="t in templates" :key="t.id" :value="t.id">{{ t.name }}</option>
          </select>
          <ChevronDown :size="16" class="select-arrow" />
        </div>

        <div v-if="selectedTemplateData" class="template-prompt-preview">
          <div class="prompt-header">
            <FileText :size="14" />
            <span>{{ selectedTemplateData.name }} · 提示词</span>
          </div>
          <p class="prompt-text">{{ selectedTemplateData.prompt }}</p>
        </div>

        <div class="divider" />

        <div class="action-row">
          <button class="cancel-btn" @click="router.push('/')">取消</button>
          <button class="submit-btn" :disabled="!hasAudio || creating" @click="startProcessing">
            <Loader2 v-if="creating" :size="18" class="spin" />
            开始处理
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.new-task {
  padding: 32px 40px;
  max-width: 1200px;
  margin: 0 auto;
}

.page-header {
  margin-bottom: 28px;
}

.page-header h1 {
  font-size: 24px;
  font-weight: 700;
  margin-bottom: 6px;
}

.page-header p {
  font-size: 14px;
  color: var(--color-text-secondary);
}

.two-column {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
}

.left-panel, .right-panel {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: 24px;
}

.mode-tabs {
  display: flex;
  gap: 8px;
  margin-bottom: 20px;
  background: var(--color-gray-100);
  border-radius: var(--radius-md);
  padding: 4px;
}

.mode-tab {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 10px;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 14px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.mode-tab.active {
  background: var(--color-surface);
  color: var(--color-primary-600);
  box-shadow: var(--shadow-sm);
}

.dropzone {
  border: 2px dashed var(--color-border);
  border-radius: var(--radius-md);
  padding: 48px 24px;
  text-align: center;
  cursor: pointer;
  transition: all 0.2s ease;
  min-height: 180px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
}

.dropzone.active {
  border-color: var(--color-primary-400);
  background: var(--color-primary-50);
}

.dropzone.has {
  border-style: solid;
  cursor: default;
  padding: 20px;
}

.dropzone-icon {
  color: var(--color-primary-400);
}

.dropzone-text {
  font-size: 15px;
  font-weight: 500;
  color: var(--color-text);
}

.dropzone-hint {
  font-size: 13px;
  color: var(--color-text-muted);
}

.file-preview {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
}

.file-icon {
  color: var(--color-primary-500);
  flex-shrink: 0;
}

.file-info {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.file-name {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.file-meta {
  font-size: 12px;
  color: var(--color-text-muted);
}

.remove-btn {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: var(--color-gray-100);
  color: var(--color-text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: all 0.2s ease;
}

.remove-btn:hover {
  background: var(--color-error-50);
  color: var(--color-error-500);
}

.error-banner {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  margin-top: 12px;
  background: var(--color-error-50);
  border: 1px solid var(--color-error-100);
  border-radius: var(--radius-sm);
  color: var(--color-error-600);
  font-size: 13px;
}

.record-area {
  min-height: 180px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
}

.record-idle {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;
}

.record-btn-large {
  width: 80px;
  height: 80px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-accent-500));
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 16px rgba(59, 130, 246, 0.3);
  transition: all 0.2s ease;
}

.record-btn-large:hover {
  transform: scale(1.05);
  box-shadow: 0 6px 20px rgba(59, 130, 246, 0.4);
}

.record-hint {
  font-size: 14px;
  color: var(--color-text-secondary);
}

.record-active {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;
  width: 100%;
}

.waveform-canvas {
  width: 100%;
  max-width: 400px;
  height: 120px;
  border-radius: var(--radius-md);
  background: var(--color-primary-50);
}

.record-timer {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 24px;
  font-weight: 700;
  font-family: 'SF Mono', monospace;
  color: var(--color-text);
}

.recording-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--color-error-500);
  animation: pulse 1s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.3; }
}

.stop-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 10px 20px;
  border-radius: var(--radius-md);
  background: var(--color-error-500);
  color: white;
  font-size: 14px;
  font-weight: 600;
  transition: all 0.2s ease;
}

.stop-btn:hover {
  background: var(--color-error-600);
}

.record-preview {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.preview-controls {
  display: flex;
  gap: 8px;
}

.play-btn, .re-record-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 16px;
  border-radius: var(--radius-sm);
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.play-btn {
  background: var(--color-primary-50);
  color: var(--color-primary-600);
}

.play-btn:hover {
  background: var(--color-primary-100);
}

.re-record-btn {
  background: var(--color-gray-100);
  color: var(--color-text-secondary);
}

.re-record-btn:hover {
  background: var(--color-error-50);
  color: var(--color-error-500);
}

.divider {
  height: 1px;
  background: var(--color-border);
  margin: 20px 0;
}

.form-section {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-label {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
  margin-top: 8px;
}

.form-input, .form-select, .form-textarea {
  width: 100%;
  padding: 10px 14px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  color: var(--color-text);
  font-size: 14px;
  transition: border-color 0.2s ease;
}

.form-input:focus, .form-select:focus, .form-textarea:focus {
  outline: none;
  border-color: var(--color-primary-400);
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

.form-textarea {
  resize: vertical;
}

.select-wrapper {
  position: relative;
}

.select-arrow {
  position: absolute;
  right: 12px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--color-text-muted);
  pointer-events: none;
}

.form-select {
  appearance: none;
  padding-right: 36px;
  cursor: pointer;
}

.tag-input-area {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  padding: 8px;
}

.tag-list {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 6px;
}

.tag-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  background: var(--color-primary-50);
  color: var(--color-primary-600);
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;
}

.tag-remove {
  background: none;
  color: var(--color-primary-400);
  display: flex;
  align-items: center;
  padding: 0;
}

.tag-remove:hover {
  color: var(--color-primary-600);
}

.tag-input-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.tag-icon {
  color: var(--color-text-muted);
  flex-shrink: 0;
}

.tag-input {
  flex: 1;
  border: none;
  outline: none;
  background: transparent;
  font-size: 13px;
  color: var(--color-text);
}

.panel-title {
  font-size: 16px;
  font-weight: 600;
  margin-bottom: 16px;
}

.audio-info-card {
  background: var(--color-primary-50);
  border: 1px solid var(--color-primary-100);
  border-radius: var(--radius-md);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.info-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.info-label {
  font-size: 13px;
  color: var(--color-text-secondary);
}

.info-value {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text);
  max-width: 60%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.no-audio-hint {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 32px;
  color: var(--color-text-muted);
  font-size: 14px;
}

.toggle-row {
  display: flex;
  gap: 8px;
}

.toggle-btn {
  flex: 1;
  padding: 8px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.toggle-btn.active {
  background: var(--color-primary-500);
  color: white;
  border-color: var(--color-primary-500);
}

.template-prompt-preview {
  margin-top: 8px;
  padding: 12px 14px;
  background: var(--color-primary-50);
  border: 1px solid var(--color-primary-100);
  border-radius: var(--radius-sm);
}

.prompt-header {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 600;
  color: var(--color-primary-600);
  margin-bottom: 6px;
}

.prompt-text {
  font-size: 13px;
  color: var(--color-text-secondary);
  line-height: 1.5;
}

.action-row {
  display: flex;
  gap: 12px;
  justify-content: flex-end;
}

.cancel-btn {
  padding: 10px 20px;
  border-radius: var(--radius-md);
  background: var(--color-gray-100);
  color: var(--color-text-secondary);
  font-size: 14px;
  font-weight: 600;
  transition: all 0.2s ease;
}

.cancel-btn:hover {
  background: var(--color-gray-200);
}

.submit-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 24px;
  border-radius: var(--radius-md);
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600));
  color: white;
  font-size: 14px;
  font-weight: 600;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
  transition: all 0.2s ease;
}

.submit-btn:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
}

/* ============ 【新增】文件加载提示样式 ============ */
.file-loaded-banner {
  background: var(--color-success-50);
  border: 1px solid var(--color-success-200);
  border-radius: var(--radius-md);
  padding: 12px 16px;
  margin-bottom: 16px;
}

.banner-content {
  display: flex;
  align-items: center;
  gap: 10px;
}

.banner-icon {
  font-size: 20px;
}

.banner-text {
  flex: 1;
  font-size: 14px;
  color: var(--color-text);
}

.banner-text strong {
  color: var(--color-text);
}

.banner-remove {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.05);
  color: var(--color-text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.banner-remove:hover {
  background: var(--color-error-50);
  color: var(--color-error-500);
}
.submit-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.spin {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

@media (max-width: 900px) {
  .two-column {
    grid-template-columns: 1fr;
  }
  .new-task {
    padding: 20px 16px;
  }
}
</style>
