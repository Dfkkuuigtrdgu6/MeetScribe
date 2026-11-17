<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import {
  supabase, formatTime, formatDuration, getPrivateAudioUrl,
  type Task, type TranscriptSegment, type Minutes, type TodoItem, type KeyPoint, type Decision,
} from '../lib/supabase'
import StatusBadge from '../components/StatusBadge.vue'
import {
  ArrowLeft,
  Play,
  Pause,
  Rewind,
  FastForward,
  Volume2,
  Download,
  RotateCcw,
  Edit3,
  Save,
  X,
  Plus,
  Trash2,
  Search,
  Copy,
  ChevronDown,
  FileText,
  CheckSquare,
  Square,
  Calendar,
  User,
} from 'lucide-vue-next'

const props = defineProps<{ id: string }>()
const router = useRouter()

const task = ref<Task | null>(null)
const segments = ref<TranscriptSegment[]>([])
const minutes = ref<Minutes | null>(null)
const loading = ref(true)
const editMode = ref(false)
const saving = ref(false)

// Audio
const audioEl = ref<HTMLAudioElement | null>(null)
const audioUrl = ref('')
const isPlaying = ref(false)
const currentTime = ref(0)
const duration = ref(0)
const playbackRate = ref(1)
const volume = ref(1)
const canvasRef = ref<HTMLCanvasElement | null>(null)
const waveformDrawn = ref(false)

// Transcript
const activeSegmentId = ref<string | null>(null)
const editingSegmentId = ref<string | null>(null)
const editingText = ref('')
const searchInTranscript = ref('')
const showSearch = ref(false)

// Minutes tabs
const activeTab = ref<'summary' | 'points' | 'todos' | 'decisions'>('summary')

// Editable minutes fields
const editSummary = ref('')
const editKeyPoints = ref<KeyPoint[]>([])
const editTodos = ref<TodoItem[]>([])
const editDecisions = ref<Decision[]>([])

const speakerColors = ['#3b82f6', '#22c55e', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4']
const speakerNames = ref<string[]>([])

const filteredSegments = computed(() => {
  if (!searchInTranscript.value) return segments.value
  const q = searchInTranscript.value.toLowerCase()
  return segments.value.filter(s => s.text.toLowerCase().includes(q))
})

function getSpeakerColor(speaker: string | null, index: number): string {
  if (!speaker) return '#6b7280'
  return speakerColors[index % speakerColors.length]
}

// ===== 【新增】切换单个待办状态 =====
const toggleTodoStatus = async (todo: any) => {
  if (!minutes.value) return
  
  try {
    // 切换本地状态
    todo.done = !todo.done
    
    // 更新数据库
    const updatedTodos = minutes.value.todos.map((t: any) => {
      if (t.id === todo.id) {
        return { ...t, done: todo.done }
      }
      return t
    })
    
    const { error } = await supabase
      .from('minutes')
      .update({ todos: updatedTodos })
      .eq('id', minutes.value.id)
    
    if (error) throw error
    
    // 更新本地 minutes 对象
    minutes.value.todos = updatedTodos
    
  } catch (error) {
    console.error('更新待办状态失败:', error)
    // 回滚
    todo.done = !todo.done
  }
}

async function loadData() {
  loading.value = true
  const [taskRes, segRes, minRes] = await Promise.all([
    supabase.from('tasks').select('*, project:projects(*), template:templates(*)').eq('id', props.id).single(),
    supabase.from('transcript_segments').select('*').eq('task_id', props.id).order('start_time', { ascending: true }),
    supabase.from('minutes').select('*').eq('task_id', props.id).order('created_at', { ascending: false }).maybeSingle(),
  ])
  task.value = taskRes.data
  segments.value = segRes.data || []
  minutes.value = minRes.data

  if (segments.value.length > 0) {
    const speakers = new Set<string>()
    segments.value.forEach(s => { if (s.speaker) speakers.add(s.speaker) })
    speakerNames.value = Array.from(speakers)
  }

  if (task.value?.audio_storage_path) {
    audioUrl.value = (await getPrivateAudioUrl(task.value.audio_storage_path)) || ''
  } else if (task.value?.audio_url) {
    // 兼容历史数据
    audioUrl.value = task.value.audio_url
  }

  initEditFields()
  loading.value = false
  await nextTick()
  drawWaveform()
}

function initEditFields() {
  editSummary.value = minutes.value?.summary || ''
  editKeyPoints.value = minutes.value ? [...minutes.value.key_points] : []
  editTodos.value = minutes.value ? [...minutes.value.todos] : []
  editDecisions.value = minutes.value ? [...minutes.value.decisions] : []
}

function drawWaveform() {
  if (!canvasRef.value || waveformDrawn.value) return
  const canvas = canvasRef.value
  const ctx = canvas.getContext('2d')
  if (!ctx) return

  canvas.width = canvas.offsetWidth * 2
  canvas.height = 60 * 2
  ctx.scale(2, 2)

  const w = canvas.offsetWidth
  const h = 60
  const barCount = 80
  const barWidth = w / barCount - 1

  ctx.clearRect(0, 0, w, h)
  for (let i = 0; i < barCount; i++) {
    const seed = (i * 9301 + 49297) % 233280
    const rand = seed / 233280
    const barHeight = 6 + rand * (h - 12)
    const x = i * (w / barCount)
    const y = (h - barHeight) / 2
    ctx.fillStyle = '#bfdbfe'
    ctx.fillRect(x, y, barWidth, barHeight)
  }
  waveformDrawn.value = true
}

function updateProgress() {
  if (!audioEl.value) return
  currentTime.value = audioEl.value.currentTime
  const active = segments.value.find(s => s.start_time <= currentTime.value && s.end_time >= currentTime.value)
  if (active && active.id !== activeSegmentId.value) {
    activeSegmentId.value = active.id
    scrollToSegment(active.id)
  }
  drawWaveformProgress()
}

function drawWaveformProgress() {
  if (!canvasRef.value) return
  const canvas = canvasRef.value
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  const w = canvas.offsetWidth
  const h = 60
  const barCount = 80
  const barWidth = w / barCount - 1
  const progress = duration.value > 0 ? currentTime.value / duration.value : 0

  ctx.clearRect(0, 0, w, h)
  for (let i = 0; i < barCount; i++) {
    const seed = (i * 9301 + 49297) % 233280
    const rand = seed / 233280
    const barHeight = 6 + rand * (h - 12)
    const x = i * (w / barCount)
    const y = (h - barHeight) / 2
    const barProgress = i / barCount
    ctx.fillStyle = barProgress <= progress ? '#3b82f6' : '#bfdbfe'
    ctx.fillRect(x, y, barWidth, barHeight)
  }
}

function togglePlay() {
  if (!audioEl.value) return
  if (isPlaying.value) {
    audioEl.value.pause()
    isPlaying.value = false
  } else {
    audioEl.value.play()
    isPlaying.value = true
  }
}

function seek(seconds: number) {
  if (!audioEl.value) return
  audioEl.value.currentTime = Math.max(0, Math.min(duration.value, audioEl.value.currentTime + seconds))
}

function setPlaybackRate(rate: number) {
  playbackRate.value = rate
  if (audioEl.value) audioEl.value.playbackRate = rate
}

function setVolume(v: number) {
  volume.value = v
  if (audioEl.value) audioEl.value.volume = v
}

function onLoadedMetadata() {
  if (audioEl.value) duration.value = audioEl.value.duration || task.value?.audio_duration || 0
}

function seekToTime(time: number) {
  if (!audioEl.value) return
  audioEl.value.currentTime = time
  if (!isPlaying.value) {
    audioEl.value.play()
    isPlaying.value = true
  }
}

function seekToPosition(e: MouseEvent) {
  if (!canvasRef.value || !audioEl.value) return
  const rect = canvasRef.value.getBoundingClientRect()
  const ratio = (e.clientX - rect.left) / rect.width
  audioEl.value.currentTime = ratio * duration.value
}

function scrollToSegment(id: string) {
  nextTick(() => {
    const el = document.querySelector(`[data-seg-id="${id}"]`)
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' })
  })
}

function startEditSegment(seg: TranscriptSegment) {
  if (!editMode.value) return
  editingSegmentId.value = seg.id
  editingText.value = seg.text
}

async function saveSegment() {
  if (!editingSegmentId.value) return
  await supabase.from('transcript_segments').update({ text: editingText.value }).eq('id', editingSegmentId.value)
  const seg = segments.value.find(s => s.id === editingSegmentId.value)
  if (seg) seg.text = editingText.value
  editingSegmentId.value = null
}

function cancelEditSegment() {
  editingSegmentId.value = null
}

async function copyAllText() {
  const text = segments.value.map(s => {
    const time = formatTime(s.start_time)
    const speaker = s.speaker ? `[${s.speaker}] ` : ''
    return `${time} ${speaker}${s.text}`
  }).join('\n')
  await navigator.clipboard.writeText(text)
}

// Minutes editing
function addKeyPoint() {
  editKeyPoints.value.push({ id: Date.now().toString(), text: '' })
}

function removeKeyPoint(id: string) {
  editKeyPoints.value = editKeyPoints.value.filter(p => p.id !== id)
}

function addTodo() {
  editTodos.value.push({ id: Date.now().toString(), text: '', assignee: '', due_date: '', done: false })
}

function removeTodo(id: string) {
  editTodos.value = editTodos.value.filter(t => t.id !== id)
}

function addDecision() {
  editDecisions.value.push({ id: Date.now().toString(), text: '' })
}

function removeDecision(id: string) {
  editDecisions.value = editDecisions.value.filter(d => d.id !== id)
}

async function saveAll() {
  saving.value = true
  if (minutes.value) {
    await supabase.from('minutes').update({
      summary: editSummary.value,
      key_points: editKeyPoints.value,
      todos: editTodos.value,
      decisions: editDecisions.value,
    }).eq('id', minutes.value.id)
    minutes.value.summary = editSummary.value
    minutes.value.key_points = editKeyPoints.value
    minutes.value.todos = editTodos.value
    minutes.value.decisions = editDecisions.value
  }
  editMode.value = false
  saving.value = false
}

function cancelEdit() {
  initEditFields()
  editMode.value = false
}

function exportContent(format: 'markdown' | 'txt') {
  const m = minutes.value
  let content = `# ${task.value?.title || ''}\n\n`
  content += `> 创建时间: ${new Date(task.value?.created_at || '').toLocaleString('zh-CN')}\n`
  content += `> 时长: ${formatDuration(task.value?.audio_duration || 0)}\n\n`

  if (m?.summary) content += `## 会议摘要\n\n${m.summary}\n\n`
  if (m?.key_points?.length) {
    content += `## 关键要点\n\n`
    m.key_points.forEach(p => { content += `- ${p.text}\n` })
    content += '\n'
  }
  if (m?.todos?.length) {
    content += `## 待办事项\n\n`
    m.todos.forEach(t => {
      content += `- [${t.done ? 'x' : ' '}] ${t.text} (${t.assignee}${t.due_date ? ', ' + t.due_date : ''})\n`
    })
    content += '\n'
  }
  if (m?.decisions?.length) {
    content += `## 决议结论\n\n`
    m.decisions.forEach(d => { content += `- ${d.text}\n` })
    content += '\n'
  }
  if (segments.value.length > 0) {
    content += `## 转写全文\n\n`
    segments.value.forEach(s => {
      content += `${formatTime(s.start_time)} ${s.speaker ? `[${s.speaker}] ` : ''}${s.text}\n`
    })
  }

  const blob = new Blob([content], { type: format === 'markdown' ? 'text/markdown' : 'text/plain' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${task.value?.title || 'export'}.${format === 'markdown' ? 'md' : 'txt'}`
  a.click()
  URL.revokeObjectURL(url)
}

const showExportMenu = ref(false)

async function reprocess() {
  if (!task.value) return
  await supabase.from('tasks').update({ status: 'queued', progress: 0, error_message: null, updated_at: new Date().toISOString() }).eq('id', props.id)
  router.push(`/tasks/${props.id}/process`)
}

onMounted(loadData)
onUnmounted(() => {
  if (audioEl.value) audioEl.value.pause()
})
</script>

<template>
  <div class="detail-page">
    <!-- Toolbar -->
    <div class="toolbar">
      <div class="toolbar-left">
        <button class="tool-btn" @click="router.push('/tasks')">
          <ArrowLeft :size="18" />
          返回
        </button>
        <div class="toolbar-title">
          <h1 v-if="task">{{ task.title }}</h1>
          <div v-if="task" class="toolbar-meta">
            <StatusBadge :status="task.status" />
            <span v-if="task.project" class="meta-project">{{ task.project.name }}</span>
            <span class="meta-duration">{{ formatDuration(task.audio_duration) }}</span>
          </div>
        </div>
      </div>
      <div class="toolbar-right">
        <button v-if="!editMode" class="tool-btn" @click="editMode = true">
          <Edit3 :size="16" />
          编辑
        </button>
        <template v-else>
          <button class="tool-btn cancel" @click="cancelEdit">
            <X :size="16" />
            取消
          </button>
          <button class="tool-btn primary" :disabled="saving" @click="saveAll">
            <Save :size="16" />
            {{ saving ? '保存中...' : '保存' }}
          </button>
        </template>

        <div class="export-wrapper">
          <button class="tool-btn" @click="showExportMenu = !showExportMenu">
            <Download :size="16" />
            导出
            <ChevronDown :size="14" />
          </button>
          <div v-if="showExportMenu" class="export-menu">
            <button @click="exportContent('markdown'); showExportMenu = false">Markdown (.md)</button>
            <button @click="exportContent('txt'); showExportMenu = false">纯文本 (.txt)</button>
          </div>
        </div>

        <button class="tool-btn" @click="reprocess">
          <RotateCcw :size="16" />
          重新处理
        </button>
      </div>
    </div>

    <div v-if="loading" class="loading">
      <div class="skeleton-block" v-for="i in 3" :key="i" />
    </div>

    <div v-else class="three-column">
      <!-- Left: Audio Player -->
      <div class="audio-panel">
        <h3 class="panel-title">音频播放</h3>

        <div class="waveform-container" @click="seekToPosition">
          <canvas ref="canvasRef" class="waveform" />
        </div>

        <div class="time-display">
          <span>{{ formatTime(currentTime) }}</span>
          <span>{{ formatTime(duration) }}</span>
        </div>

        <div class="player-controls">
          <button class="ctrl-btn" @click="seek(-10)">
            <Rewind :size="18" />
          </button>
          <button class="ctrl-btn play" @click="togglePlay">
            <component :is="isPlaying ? Pause : Play" :size="22" />
          </button>
          <button class="ctrl-btn" @click="seek(10)">
            <FastForward :size="18" />
          </button>
        </div>

        <div class="speed-controls">
          <span class="ctrl-label">倍速</span>
          <div class="speed-btns">
            <button
              v-for="rate in [0.5, 0.75, 1, 1.25, 1.5, 2]"
              :key="rate"
              class="speed-btn"
              :class="{ active: playbackRate === rate }"
              @click="setPlaybackRate(rate)"
            >{{ rate }}x</button>
          </div>
        </div>

        <div class="volume-controls">
          <Volume2 :size="16" class="ctrl-label" />
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            :value="volume"
            class="volume-slider"
            @input="setVolume(parseFloat(($event.target as HTMLInputElement).value))"
          />
        </div>

        <div v-if="speakerNames.length > 0" class="speaker-legend">
          <h4>说话人</h4>
          <div class="legend-items">
            <button
              v-for="(name, i) in speakerNames"
              :key="name"
              class="legend-item"
              @click="seekToTime(segments.find(s => s.speaker === name)?.start_time || 0)"
            >
              <span class="legend-dot" :style="{ background: getSpeakerColor(name, i) }" />
              {{ name }}
            </button>
          </div>
        </div>

        <audio
          v-if="audioUrl"
          ref="audioEl"
          :src="audioUrl"
          @timeupdate="updateProgress"
          @loadedmetadata="onLoadedMetadata"
          @ended="isPlaying = false"
        />
      </div>

      <!-- Center: Transcript -->
      <div class="transcript-panel">
        <div class="panel-header">
          <h3 class="panel-title">转写文本</h3>
          <div class="transcript-actions">
            <button class="mini-btn" @click="showSearch = !showSearch">
              <Search :size="14" />
            </button>
            <button class="mini-btn" @click="copyAllText">
              <Copy :size="14" />
            </button>
          </div>
        </div>

        <div v-if="showSearch" class="search-bar">
          <Search :size="14" class="search-icon" />
          <input v-model="searchInTranscript" type="text" placeholder="在转写中搜索..." />
          <button class="mini-btn" @click="searchInTranscript = ''">
            <X :size="14" />
          </button>
        </div>

        <div class="transcript-list">
          <div v-if="filteredSegments.length === 0" class="empty-transcript">
            <FileText :size="32" />
            <p>暂无转写内容</p>
          </div>
          <div
            v-for="seg in filteredSegments"
            :key="seg.id"
            :data-seg-id="seg.id"
            class="segment"
            :class="{ active: activeSegmentId === seg.id, editing: editingSegmentId === seg.id }"
            @click="seekToTime(seg.start_time)"
            @dblclick="startEditSegment(seg)"
          >
            <div class="seg-header">
              <span class="seg-time">{{ formatTime(seg.start_time) }}</span>
              <span
                v-if="seg.speaker"
                class="seg-speaker"
                :style="{ background: getSpeakerColor(seg.speaker, seg.speaker_index) + '20', color: getSpeakerColor(seg.speaker, seg.speaker_index) }"
              >{{ seg.speaker }}</span>
            </div>
            <div v-if="editingSegmentId === seg.id" class="seg-edit" @click.stop>
              <textarea v-model="editingText" class="seg-edit-input" rows="3" />
              <div class="seg-edit-actions">
                <button class="mini-btn primary" @click.stop="saveSegment">保存</button>
                <button class="mini-btn" @click.stop="cancelEditSegment">取消</button>
              </div>
            </div>
            <p v-else class="seg-text" v-html="searchInTranscript ? seg.text.replace(new RegExp(searchInTranscript, 'gi'), m => `<mark>${m}</mark>`) : seg.text" />
          </div>
        </div>
      </div>

      <!-- Right: Minutes -->
      <div class="minutes-panel">
        <h3 class="panel-title">纪要</h3>

        <div class="tab-bar">
          <button class="tab-btn" :class="{ active: activeTab === 'summary' }" @click="activeTab = 'summary'">摘要</button>
          <button class="tab-btn" :class="{ active: activeTab === 'points' }" @click="activeTab = 'points'">要点</button>
          <button class="tab-btn" :class="{ active: activeTab === 'todos' }" @click="activeTab = 'todos'">待办</button>
          <button class="tab-btn" :class="{ active: activeTab === 'decisions' }" @click="activeTab = 'decisions'">决议</button>
        </div>

        <div class="tab-content">
          <!-- Summary -->
          <div v-if="activeTab === 'summary'" class="tab-pane">
            <textarea
              v-if="editMode"
              v-model="editSummary"
              class="edit-textarea"
              rows="10"
              placeholder="输入会议摘要..."
            />
            <p v-else class="summary-text">{{ minutes?.summary || '暂无摘要' }}</p>
          </div>

          <!-- Key Points -->
          <div v-if="activeTab === 'points'" class="tab-pane">
            <div v-if="editMode" class="edit-list">
              <div v-for="(point, i) in editKeyPoints" :key="point.id" class="edit-list-item">
                <span class="list-bullet">{{ i + 1 }}.</span>
                <input v-model="point.text" type="text" class="edit-input" placeholder="输入要点" />
                <button class="list-remove" @click="removeKeyPoint(point.id)"><Trash2 :size="14" /></button>
              </div>
              <button class="add-btn" @click="addKeyPoint">
                <Plus :size="14" />
                添加要点
              </button>
            </div>
            <div v-else class="point-list">
              <div v-if="!minutes?.key_points?.length" class="empty-mini">暂无要点</div>
              <div v-for="point in minutes?.key_points" :key="point.id" class="point-item">
                <span class="point-dot" />
                <span>{{ point.text }}</span>
              </div>
            </div>
          </div>

          <!-- Todos -->
          <div v-if="activeTab === 'todos'" class="tab-pane">
            <div v-if="editMode" class="edit-list">
              <div v-for="todo in editTodos" :key="todo.id" class="todo-edit-item">
                <button class="todo-check" @click="todo.done = !todo.done">
                  <component :is="todo.done ? CheckSquare : Square" :size="16" />
                </button>
                <input v-model="todo.text" type="text" class="edit-input" placeholder="任务描述" />
                <input v-model="todo.assignee" type="text" class="edit-input small" placeholder="负责人" />
                <input v-model="todo.due_date" type="text" class="edit-input small" placeholder="截止日期" />
                <button class="list-remove" @click="removeTodo(todo.id)"><Trash2 :size="14" /></button>
              </div>
              <button class="add-btn" @click="addTodo">
                <Plus :size="14" />
                添加待办
              </button>
            </div>
            <div v-else class="todo-list">
              <div v-if="!minutes?.todos?.length" class="empty-mini">暂无待办事项</div>
              <div v-for="todo in minutes?.todos" :key="todo.id" class="todo-item" :class="{ done: todo.done }">
                <div class="todo-content">
                  <span class="todo-text">{{ todo.text }}</span>
                  <div class="todo-meta">
                  <span v-if="todo.assignee" class="todo-assignee">
                  <User :size="11" />
                  {{ todo.assignee }}
                  </span>
                  <span v-if="todo.due_date" class="todo-due">
                   <Calendar :size="11" />
                       {{ todo.due_date }}
                   </span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Decisions -->
          <div v-if="activeTab === 'decisions'" class="tab-pane">
            <div v-if="editMode" class="edit-list">
              <div v-for="dec in editDecisions" :key="dec.id" class="edit-list-item">
                <span class="list-bullet">-</span>
                <input v-model="dec.text" type="text" class="edit-input" placeholder="输入决议" />
                <button class="list-remove" @click="removeDecision(dec.id)"><Trash2 :size="14" /></button>
              </div>
              <button class="add-btn" @click="addDecision">
                <Plus :size="14" />
                添加决议
              </button>
            </div>
            <div v-else class="decision-list">
              <div v-if="!minutes?.decisions?.length" class="empty-mini">暂无决议</div>
              <div v-for="dec in minutes?.decisions" :key="dec.id" class="decision-item">
                <span class="decision-dot" />
                <span>{{ dec.text }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.detail-page {
  padding: 0 32px 32px;
  max-width: 1400px;
  margin: 0 auto;
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 0;
  gap: 16px;
  flex-wrap: wrap;
  position: sticky;
  top: 0;
  background: var(--color-bg);
  z-index: 50;
}

.toolbar-left {
  display: flex;
  align-items: center;
  gap: 16px;
}

.tool-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.tool-btn:hover {
  border-color: var(--color-primary-300);
  color: var(--color-primary-600);
  background: var(--color-primary-50);
}

.tool-btn.primary {
  background: var(--color-primary-500);
  color: white;
  border: none;
}

.tool-btn.primary:hover {
  background: var(--color-primary-600);
}

.tool-btn.cancel:hover {
  border-color: var(--color-error-300);
  color: var(--color-error-500);
  background: var(--color-error-50);
}

.toolbar-title h1 {
  font-size: 18px;
  font-weight: 700;
  margin-bottom: 4px;
}

.toolbar-meta {
  display: flex;
  align-items: center;
  gap: 10px;
}

.meta-project {
  font-size: 12px;
  color: var(--color-text-secondary);
}

.meta-duration {
  font-size: 12px;
  color: var(--color-text-muted);
}

.toolbar-right {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.export-wrapper {
  position: relative;
}

.export-menu {
  position: absolute;
  top: 100%;
  right: 0;
  margin-top: 4px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-lg);
  z-index: 100;
  overflow: hidden;
}

.export-menu button {
  display: block;
  width: 100%;
  padding: 10px 16px;
  background: none;
  color: var(--color-text);
  font-size: 13px;
  text-align: left;
  transition: background 0.15s ease;
}

.export-menu button:hover {
  background: var(--color-primary-50);
}

.loading {
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 24px;
}

.skeleton-block {
  height: 200px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  animation: shimmer 1.5s ease-in-out infinite;
}

@keyframes shimmer {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.three-column {
  display: grid;
  grid-template-columns: 280px 1fr 340px;
  gap: 20px;
  align-items: start;
}

.audio-panel, .transcript-panel, .minutes-panel {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: 20px;
}

.audio-panel {
  position: sticky;
  top: 70px;
}

.panel-title {
  font-size: 15px;
  font-weight: 600;
  margin-bottom: 16px;
}

.waveform-container {
  cursor: pointer;
  margin-bottom: 8px;
}

.waveform {
  width: 100%;
  height: 60px;
  display: block;
}

.time-display {
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  font-family: monospace;
  color: var(--color-text-muted);
  margin-bottom: 12px;
}

.player-controls {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 16px;
  margin-bottom: 16px;
}

.ctrl-btn {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: var(--color-gray-100);
  color: var(--color-text);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.ctrl-btn:hover {
  background: var(--color-primary-100);
  color: var(--color-primary-600);
}

.ctrl-btn.play {
  width: 48px;
  height: 48px;
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600));
  color: white;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
}

.ctrl-btn.play:hover {
  transform: scale(1.05);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
}

.speed-controls, .volume-controls {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}

.ctrl-label {
  font-size: 12px;
  color: var(--color-text-muted);
  flex-shrink: 0;
}

.speed-btns {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}

.speed-btn {
  padding: 3px 8px;
  border-radius: var(--radius-sm);
  background: var(--color-gray-100);
  color: var(--color-text-secondary);
  font-size: 11px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.speed-btn:hover {
  background: var(--color-primary-50);
  color: var(--color-primary-600);
}

.speed-btn.active {
  background: var(--color-primary-500);
  color: white;
}

.volume-slider {
  flex: 1;
  -webkit-appearance: none;
  height: 4px;
  background: var(--color-gray-200);
  border-radius: 2px;
  outline: none;
}

.volume-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--color-primary-500);
  cursor: pointer;
}

.speaker-legend {
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid var(--color-border);
}

.speaker-legend h4 {
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 10px;
}

.legend-items {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  border-radius: 12px;
  background: var(--color-gray-100);
  font-size: 12px;
  color: var(--color-text);
  transition: all 0.2s ease;
}

.legend-item:hover {
  background: var(--color-primary-50);
}

.legend-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}

.transcript-actions {
  display: flex;
  gap: 4px;
}

.mini-btn {
  width: 28px;
  height: 28px;
  border-radius: var(--radius-sm);
  background: var(--color-gray-100);
  color: var(--color-text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.mini-btn:hover {
  background: var(--color-primary-50);
  color: var(--color-primary-600);
}

.mini-btn.primary {
  background: var(--color-primary-500);
  color: white;
}

.search-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: var(--color-primary-50);
  border: 1px solid var(--color-primary-100);
  border-radius: var(--radius-sm);
  margin-bottom: 12px;
}

.search-bar input {
  flex: 1;
  border: none;
  background: transparent;
  outline: none;
  font-size: 13px;
  color: var(--color-text);
}

.search-icon {
  color: var(--color-text-muted);
}

.transcript-list {
  max-height: calc(100vh - 200px);
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.empty-transcript {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 48px;
  color: var(--color-text-muted);
}

.segment {
  padding: 12px;
  border-radius: var(--radius-md);
  cursor: pointer;
  transition: all 0.2s ease;
  border: 1px solid transparent;
}

.segment:hover {
  background: var(--color-surface-alt);
}

.segment.active {
  background: var(--color-primary-50);
  border-color: var(--color-primary-200);
}

.seg-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
}

.seg-time {
  font-size: 12px;
  font-family: monospace;
  color: var(--color-text-muted);
}

.seg-speaker {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 10px;
}

.seg-text {
  font-size: 14px;
  line-height: 1.6;
  color: var(--color-text);
}

.seg-text :deep(mark) {
  background: #fef08a;
  border-radius: 2px;
  padding: 1px 2px;
}

.seg-edit {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.seg-edit-input {
  width: 100%;
  padding: 8px;
  border: 1px solid var(--color-primary-300);
  border-radius: var(--radius-sm);
  font-size: 14px;
  color: var(--color-text);
  resize: vertical;
  outline: none;
}

.seg-edit-actions {
  display: flex;
  gap: 6px;
}

/* Minutes */
.tab-bar {
  display: flex;
  gap: 2px;
  background: var(--color-gray-100);
  border-radius: var(--radius-sm);
  padding: 3px;
  margin-bottom: 16px;
}

.tab-btn {
  flex: 1;
  padding: 6px 8px;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.tab-btn.active {
  background: var(--color-surface);
  color: var(--color-primary-600);
  box-shadow: var(--shadow-sm);
}

.tab-content {
  max-height: calc(100vh - 250px);
  overflow-y: auto;
}

.summary-text {
  font-size: 14px;
  line-height: 1.7;
  color: var(--color-text);
}

.edit-textarea {
  width: 100%;
  padding: 12px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-size: 14px;
  line-height: 1.7;
  color: var(--color-text);
  resize: vertical;
  outline: none;
  transition: border-color 0.2s ease;
}

.edit-textarea:focus {
  border-color: var(--color-primary-400);
}

.point-list, .todo-list, .decision-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.point-item, .decision-item {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  font-size: 14px;
  line-height: 1.5;
  color: var(--color-text);
}

.point-dot, .decision-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  margin-top: 8px;
  flex-shrink: 0;
}

.point-dot { background: var(--color-primary-500); }
.decision-dot { background: var(--color-success-500); }

.todo-item {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 10px;
  border-radius: var(--radius-md);
  background: var(--color-surface-alt);
  transition: all 0.2s ease;
}

.todo-item.done {
  opacity: 0.5;
}

.todo-item.done .todo-text {
  text-decoration: line-through;
}

.todo-check-icon {
  color: var(--color-text-muted);
  flex-shrink: 0;
  margin-top: 2px;
}

.todo-item.done .todo-check-icon {
  color: var(--color-success-500);
}

.todo-content {
  flex: 1;
}

.todo-text {
  font-size: 14px;
  color: var(--color-text);
  line-height: 1.4;
}

.todo-meta {
  display: flex;
  gap: 10px;
  margin-top: 4px;
}

.todo-assignee, .todo-due {
  display: flex;
  align-items: center;
  gap: 3px;
  font-size: 11px;
  color: var(--color-text-muted);
}

.empty-mini {
  text-align: center;
  padding: 32px;
  font-size: 14px;
  color: var(--color-text-muted);
}

.edit-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.edit-list-item {
  display: flex;
  align-items: center;
  gap: 8px;
}

.list-bullet {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text-muted);
  flex-shrink: 0;
}

.edit-input {
  flex: 1;
  padding: 6px 10px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-size: 13px;
  color: var(--color-text);
  outline: none;
  transition: border-color 0.2s ease;
}

.edit-input:focus {
  border-color: var(--color-primary-400);
}

.edit-input.small {
  max-width: 100px;
  font-size: 12px;
}

.todo-edit-item {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.todo-check {
  background: none;
  color: var(--color-text-muted);
  display: flex;
  align-items: center;
}

.list-remove {
  width: 26px;
  height: 26px;
  border-radius: var(--radius-sm);
  background: var(--color-error-50);
  color: var(--color-error-500);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: all 0.2s ease;
}

.list-remove:hover {
  background: var(--color-error-100);
}

.add-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 12px;
  border-radius: var(--radius-sm);
  background: var(--color-primary-50);
  color: var(--color-primary-600);
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
  align-self: flex-start;
}

.add-btn:hover {
  background: var(--color-primary-100);
}

/* ===== 【新增】详情页圆点样式 ===== */
.todo-item {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 10px;
  border-radius: var(--radius-md);
  background: var(--color-surface-alt);
  transition: all 0.2s ease;
}

/* 已完成 - 降低透明度 */
.todo-item.done {
  opacity: 0.5;
}

.todo-item.done .todo-text {
  text-decoration: line-through;
  color: var(--color-text-muted);
}

.todo-check-icon {
  flex-shrink: 0;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  margin-top: 2px;
}

.todo-check-icon .status-circle {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  border: 2px solid var(--color-text-muted);
  display: inline-block;
  transition: all 0.2s ease;
  position: relative;
}

.todo-check-icon .status-circle:hover {
  border-color: var(--color-primary-500);
  transform: scale(1.1);
}

.todo-check-icon .status-circle.checked {
  background: var(--color-success-500);
  border-color: var(--color-success-500);
}

.todo-check-icon .status-circle.checked::after {
  content: '✓';
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  color: white;
  font-size: 11px;
  font-weight: 700;
}

.todo-content {
  flex: 1;
}

.todo-text {
  font-size: 14px;
  color: var(--color-text);
  line-height: 1.4;
}

.todo-meta {
  display: flex;
  gap: 10px;
  margin-top: 4px;
}

.todo-assignee,
.todo-due {
  display: flex;
  align-items: center;
  gap: 3px;
  font-size: 11px;
  color: var(--color-text-muted);
}

@media (max-width: 1200px) {
  .three-column {
    grid-template-columns: 1fr;
  }
  .audio-panel {
    position: relative;
    top: 0;
  }
}

@media (max-width: 768px) {
  .detail-page {
    padding: 0 16px 16px;
  }
  .toolbar {
    padding: 12px 0;
  }
}
</style>
