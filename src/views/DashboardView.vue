<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase, formatDateTime, formatDuration, type Task, type Template, type Project } from '../lib/supabase'
import StatusBadge from '../components/StatusBadge.vue'
import {
  PlusCircle,
  Upload,
  Mic,
  FileText,
  MessageSquare,
  RefreshCw,
  Clock,
  Archive,
  ListTodo,
  ArrowRight,
  Cpu,
  Brain,
  CircleCheck,
} from 'lucide-vue-next'

// ============ 【新增】导入待办汇总组件 ============
import TodoSummary from '../components/TodoSummary.vue'

const router = useRouter()
const tasks = ref<Task[]>([])
const templates = ref<Template[]>([])
const projects = ref<Project[]>([])
const loading = ref(true)
const fileInput = ref<HTMLInputElement | null>(null)
const selectedFile = ref<File | null>(null)

const today = new Date()
const greeting = computed(() => {
  const h = today.getHours()
  if (h < 6) return '夜深了'
  if (h < 12) return '早上好'
  if (h < 14) return '中午好'
  if (h < 18) return '下午好'
  return '晚上好'
})

const dateStr = computed(() => {
  const days = ['日', '一', '二', '三', '四', '五', '六']
  return `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日 星期${days[today.getDay()]}`
})

const todayCount = computed(() => {
  const todayStart = new Date()
  todayStart.setHours(0, 0, 0, 0)
  return tasks.value.filter(t => new Date(t.created_at) >= todayStart).length
})

const pendingCount = computed(() =>
  tasks.value.filter(t => ['queued', 'uploading', 'transcribing', 'segmenting', 'summarizing'].includes(t.status)).length
)

const completedCount = computed(() => tasks.value.filter(t => t.status === 'completed').length)

const recentTasks = computed(() =>
  [...tasks.value]
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .slice(0, 4)
)

const templateIcons: Record<string, any> = {
  'file-text': FileText,
  'message-square': MessageSquare,
  'refresh-cw': RefreshCw,
}

async function loadData() {
  loading.value = true
  const [tasksRes, templatesRes, projectsRes] = await Promise.all([
    supabase.from('tasks').select('*, project:projects(*), template:templates(*), task_tags(tag:tags(*))').order('created_at', { ascending: false }),
    supabase.from('templates').select('*').order('created_at'),
    supabase.from('projects').select('*').order('created_at'),
  ])
  tasks.value = tasksRes.data || []
  templates.value = templatesRes.data || []
  projects.value = projectsRes.data || []
  loading.value = false
}

function triggerImport() {
  fileInput.value?.click()
}

// ===== 【修改】文件选择处理 =====
async function onFileSelected(e: Event) {
  const input = e.target as HTMLInputElement
  if (!input.files?.length) return
  const file = input.files[0]
  
  // 方法1：使用 sessionStorage 存储文件（推荐）
  try {
    // 将文件转换为 Base64 存储（适用于小文件，< 5MB）
    const reader = new FileReader()
    reader.onload = () => {
      const base64 = reader.result as string
      sessionStorage.setItem('pendingAudioFile', base64)
      sessionStorage.setItem('pendingAudioFileName', file.name)
      sessionStorage.setItem('pendingAudioFileSize', file.size.toString())
      router.push('/new')
    }
    reader.readAsDataURL(file)
  } catch (error) {
    console.error('读取文件失败:', error)
    // 降级方案：只传递文件名
    router.push({ 
      path: '/new', 
      query: { 
        file: file.name, 
        size: file.size.toString() 
      } 
    })
  }
  
  // 重置 input，允许重复选择同一文件
  input.value = ''
}

// ===== 【新增】从 sessionStorage 获取待导入文件 =====
function getPendingFile(): { base64: string; name: string; size: number } | null {
  const base64 = sessionStorage.getItem('pendingAudioFile')
  const name = sessionStorage.getItem('pendingAudioFileName')
  const size = sessionStorage.getItem('pendingAudioFileSize')
  
  if (base64 && name && size) {
    return { base64, name, size: parseInt(size) }
  }
  return null
}

// ===== 【新增】清除待导入文件缓存 =====
function clearPendingFile() {
  sessionStorage.removeItem('pendingAudioFile')
  sessionStorage.removeItem('pendingAudioFileName')
  sessionStorage.removeItem('pendingAudioFileSize')
}



function quickStartInterview() {
  router.push({ path: '/new', query: { mode: 'record' } })
}

function useTemplate(template: Template) {
  router.push({ path: '/new', query: { template: template.id, tpl_name: template.name } })
}

onMounted(loadData)
</script>

<template>
  <div class="dashboard">
    <input ref="fileInput" type="file" accept="audio/*" style="display:none" @change="onFileSelected" />

    <!-- Greeting -->
    <div class="greeting-bar">
      <div class="greeting-left">
        <h1>{{ greeting }}，欢迎使用语音纪要</h1>
        <p class="date-text">{{ dateStr }}</p>
      </div>
      <div class="model-status">
        <div class="model-item">
          <Cpu :size="16" />
          <span class="model-label">ASR</span>
          <span class="model-name">SenseVoiceSmall</span>
          <CircleCheck :size="14" class="ready" />
        </div>
        <div class="model-item">
          <Brain :size="16" />
          <span class="model-label">LLM</span>
          <span class="model-name">Qwen3-8B</span>
          <CircleCheck :size="14" class="ready" />
        </div>
      </div>
    </div>

    <!-- Action buttons -->
    <div class="action-row">
      <button class="action-btn primary" @click="router.push('/new')">
        <PlusCircle :size="20" />
        新建录音任务
      </button>
      <button class="action-btn" @click="triggerImport">
        <Upload :size="20" />
        导入录音文件
      </button>
      <button class="action-btn" @click="quickStartInterview">
        <Mic :size="20" />
        快速开始访谈
      </button>
    </div>

    <!-- Stats cards -->
    <div class="stats-row">
      <div class="stat-card">
        <div class="stat-icon today">
          <Clock :size="22" />
        </div>
        <div class="stat-info">
          <span class="stat-value">{{ todayCount }}</span>
          <span class="stat-label">今日任务数</span>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon pending">
          <ListTodo :size="22" />
        </div>
        <div class="stat-info">
          <span class="stat-value">{{ pendingCount }}</span>
          <span class="stat-label">待处理 / 处理中</span>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon completed">
          <Archive :size="22" />
        </div>
        <div class="stat-info">
          <span class="stat-value">{{ completedCount }}</span>
          <span class="stat-label">已归档任务</span>
        </div>
      </div>
    </div>
    <TodoSummary />

    <!-- Recent tasks -->
    <div class="section">
      <div class="section-header">
        <h2>最近任务</h2>
        <button class="see-all" @click="router.push('/tasks')">
          查看全部
          <ArrowRight :size="16" />
        </button>
      </div>

      <div v-if="loading" class="loading-state">
        <div class="skeleton-card" v-for="i in 3" :key="i" />
      </div>

      <div v-else-if="recentTasks.length === 0" class="empty-state">
        <FileText :size="40" class="empty-icon" />
        <p>还没有任务，点击上方按钮创建一个吧</p>
      </div>

      <div v-else class="task-grid">
        <div
          v-for="task in recentTasks"
          :key="task.id"
          class="task-card"
          @click="router.push(`/tasks/${task.id}`)"
        >
          <div class="task-card-top">
            <h3 class="task-title">{{ task.title }}</h3>
            <StatusBadge :status="task.status" />
          </div>
          <p class="task-summary">{{ task.summary_preview || '暂无摘要预览' }}</p>
          <div class="task-card-footer">
            <span class="task-meta">
              <Clock :size="13" />
              {{ formatDateTime(task.created_at) }}
            </span>
            <span v-if="task.audio_duration > 0" class="task-meta">
              {{ formatDuration(task.audio_duration) }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <!-- Quick templates -->
    <div class="section">
      <div class="section-header">
        <h2>快捷模板</h2>
      </div>
      <div class="template-row">
        <button
          v-for="tpl in templates"
          :key="tpl.id"
          class="template-card"
          @click="useTemplate(tpl)"
        >
          <div class="template-icon">
            <component :is="templateIcons[tpl.icon] || FileText" :size="22" />
          </div>
          <div class="template-text">
            <span class="template-name">{{ tpl.name }}</span>
            <span class="template-desc">{{ tpl.description || tpl.prompt.slice(0, 30) + '...' }}</span>
          </div>
        </button>
        <button class="template-card custom" @click="router.push('/new')">
          <div class="template-icon">
            <PlusCircle :size="22" />
          </div>
          <span class="template-name">自定义...</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.dashboard {
  padding: 32px 40px;
  max-width: 1200px;
  margin: 0 auto;
}

.greeting-bar {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 28px;
  flex-wrap: wrap;
  gap: 16px;
}

.greeting-left h1 {
  font-size: 26px;
  font-weight: 700;
  color: var(--color-text);
  margin-bottom: 6px;
}

.date-text {
  font-size: 14px;
  color: var(--color-text-secondary);
}

.model-status {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.model-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  font-size: 13px;
  color: var(--color-text-secondary);
}

.model-label {
  font-weight: 600;
  color: var(--color-text);
}

.model-name {
  font-family: 'SF Mono', 'Fira Code', monospace;
  font-size: 12px;
}

.ready {
  color: var(--color-success-500);
}

.action-row {
  display: flex;
  gap: 12px;
  margin-bottom: 24px;
  flex-wrap: wrap;
}

.action-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 20px;
  border-radius: var(--radius-md);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  color: var(--color-text);
  font-size: 14px;
  font-weight: 600;
  transition: all 0.2s ease;
}

.action-btn:hover {
  border-color: var(--color-primary-300);
  background: var(--color-primary-50);
  transform: translateY(-1px);
  box-shadow: var(--shadow-md);
}

.action-btn.primary {
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600));
  color: white;
  border: none;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
}

.action-btn.primary:hover {
  box-shadow: 0 4px 16px rgba(59, 130, 246, 0.4);
}

.stats-row {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
  margin-bottom: 32px;
}

.stat-card {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 20px 24px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  transition: all 0.2s ease;
}

.stat-card:hover {
  box-shadow: var(--shadow-md);
  transform: translateY(-2px);
}

.stat-icon {
  width: 48px;
  height: 48px;
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.stat-icon.today {
  background: var(--color-primary-50);
  color: var(--color-primary-600);
}

.stat-icon.pending {
  background: var(--color-warning-50);
  color: var(--color-warning-500);
}

.stat-icon.completed {
  background: var(--color-success-50);
  color: var(--color-success-600);
}

.stat-info {
  display: flex;
  flex-direction: column;
}

.stat-value {
  font-size: 28px;
  font-weight: 700;
  color: var(--color-text);
  line-height: 1.2;
}

.stat-label {
  font-size: 13px;
  color: var(--color-text-muted);
}

.section {
  margin-bottom: 32px;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}

.section-header h2 {
  font-size: 18px;
  font-weight: 600;
}

.see-all {
  display: flex;
  align-items: center;
  gap: 4px;
  background: none;
  color: var(--color-primary-600);
  font-size: 13px;
  font-weight: 500;
  padding: 4px 8px;
  border-radius: var(--radius-sm);
  transition: opacity 0.2s ease;
}

.see-all:hover {
  opacity: 0.7;
}

.loading-state {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
}

.skeleton-card {
  height: 140px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  animation: shimmer 1.5s ease-in-out infinite;
}

@keyframes shimmer {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 48px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  color: var(--color-text-muted);
}

.empty-icon {
  color: var(--color-gray-300);
}

.task-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
}

.task-card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: 20px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.task-card:hover {
  box-shadow: var(--shadow-lg);
  transform: translateY(-3px);
  border-color: var(--color-primary-200);
}

.task-card-top {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 8px;
  margin-bottom: 10px;
}

.task-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.task-summary {
  font-size: 13px;
  color: var(--color-text-secondary);
  line-height: 1.5;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  margin-bottom: 12px;
  min-height: 39px;
}

.task-card-footer {
  display: flex;
  align-items: center;
  gap: 12px;
}

.task-meta {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: var(--color-text-muted);
}

.template-row {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.template-card {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 20px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  color: var(--color-text);
  font-size: 14px;
  font-weight: 500;
  transition: all 0.2s ease;
  text-align: left;
  min-width: 200px;
  flex-direction: column;
  align-items: flex-start;
  gap: 6px;
}

.template-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.template-desc {
  font-size: 12px;
  font-weight: 400;
  color: var(--color-text-muted);
  line-height: 1.4;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.template-card:hover {
  border-color: var(--color-primary-300);
  background: var(--color-primary-50);
  transform: translateY(-1px);
  box-shadow: var(--shadow-sm);
}

.template-card.custom {
  border-style: dashed;
  color: var(--color-text-muted);
}

.template-icon {
  width: 36px;
  height: 36px;
  border-radius: var(--radius-sm);
  background: var(--color-primary-50);
  color: var(--color-primary-600);
  display: flex;
  align-items: center;
  justify-content: center;
}

.template-card.custom .template-icon {
  background: var(--color-gray-100);
  color: var(--color-gray-500);
}

@media (max-width: 1024px) {
  .stats-row {
    grid-template-columns: 1fr;
  }
  .task-grid, .loading-state {
    grid-template-columns: 1fr 1fr;
  }
}

@media (max-width: 768px) {
  .dashboard {
    padding: 20px 16px;
  }
  .stats-row, .task-grid, .loading-state {
    grid-template-columns: 1fr;
  }
  .greeting-left h1 {
    font-size: 20px;
  }
}
</style>
