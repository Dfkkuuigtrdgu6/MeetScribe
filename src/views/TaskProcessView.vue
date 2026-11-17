<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase, type Task, type TranscriptSegment, type TaskStatus } from '../lib/supabase'
import StatusBadge from '../components/StatusBadge.vue'
import {
  CheckCircle2,
  Loader2,
  Upload,
  AudioLines,
  Users,
  FileText,
  ArrowLeft,
  AlertCircle,
  RotateCcw,
  XCircle,
} from 'lucide-vue-next'

const props = defineProps<{ id: string }>()
const router = useRouter()

// ===== 响应式变量 =====
const task = ref<Task | null>(null)
const segments = ref<TranscriptSegment[]>([])
const loading = ref(true)
const canceling = ref(false)

// 【新增】进度相关的响应式变量
const progress = ref(0)
const statusText = ref('准备开始...')
const errorMessage = ref('')
const isError = ref(false)

// 【新增】防止重复触发 summarize
const summarizeTriggered = ref(false)

// 【新增】轮询定时器
let pollTimer: number | null = null

const steps = [
  { key: 'transcribing', label: '语音识别', icon: AudioLines },
  { key: 'summarizing', label: '纪要提炼', icon: FileText },
]

const stepStatuses = computed(() => {
  if (!task.value) return []
  const currentStatus = task.value.status
  const statusOrder: TaskStatus[] = ['queued', 'transcribing', 'summarizing', 'completed']
  const currentIdx = statusOrder.indexOf(currentStatus)

  return steps.map((step) => {
    const stepStatusIdx = statusOrder.indexOf(step.key as TaskStatus)
    if (currentStatus === 'failed') {
      return { ...step, state: stepStatusIdx < currentIdx ? 'done' : stepStatusIdx === currentIdx ? 'failed' : 'pending', progress: 0 }
    }
    if (currentStatus === 'completed') return { ...step, state: 'done', progress: 100 }
    if (stepStatusIdx < currentIdx) return { ...step, state: 'done', progress: 100 }
    if (stepStatusIdx === currentIdx) return { ...step, state: 'active', progress: task.value?.progress || 0 }
    return { ...step, state: 'pending', progress: 0 }
  })
})

const isProcessing = computed(() => {
  if (!task.value) return false
  return ['uploading', 'transcribing', 'segmenting', 'summarizing'].includes(task.value.status)
})

// ===== 加载任务 =====
async function loadTask() {
  const { data } = await supabase
    .from('tasks')
    .select('*, project:projects(*), template:templates(*)')
    .eq('id', props.id)
    .single()
  task.value = data
  loading.value = false

  if (data?.status === 'queued' || isProcessing.value) {
    startProcessing()
  }
  if (data?.status === 'completed') {
    loadSegments()
  }
}

// ===== 加载识别片段 =====
async function loadSegments() {
  const { data } = await supabase
    .from('transcript_segments')
    .select('*')
    .eq('task_id', props.id)
    .order('start_time', { ascending: true })
  segments.value = data || []
}

// ===== 【核心修改】启动处理 =====
const startProcessing = async () => {
  // 使用 props.id 而不是 taskId
  const taskId = props.id
  
  try {
    // 重置状态
    summarizeTriggered.value = false
    progress.value = 10
    statusText.value = '正在触发语音识别...'
    
    // 触发 transcribe Edge Function（fire and forget）
    const { error } = await supabase.functions.invoke('transcribe', { 
      body: { task_id: taskId } 
    })
    
    if (error) {
      console.error('transcribe 触发失败:', error)
      errorMessage.value = '触发语音识别失败: ' + error.message
      isError.value = true
      return
    }
    
    console.log('transcribe 已触发，开始轮询状态...')
    // 开始轮询
    pollStatus()
  } catch (error) {
    console.error('启动处理失败:', error)
    errorMessage.value = '启动处理失败: ' + (error as Error).message
    isError.value = true
  }
}

// ===== 【核心修改】轮询状态 =====
const pollStatus = async () => {
  const taskId = props.id
  
  try {
    // 查询任务状态
    const { data, error } = await supabase
      .from('tasks')
      .select('status, error_message, progress')
      .eq('id', taskId)
      .single()
    
    if (error) throw error
    
    // 更新任务对象
    if (task.value) {
      task.value.status = data.status
      task.value.progress = data.progress || 0
      task.value.error_message = data.error_message
    }
    
    // 根据状态处理
    if (data.status === 'transcribing') {
      progress.value = 30
      statusText.value = '正在识别语音...'
    } 
    else if (data.status === 'summarizing') {
      progress.value = 70
      statusText.value = '正在生成纪要...'
      
      // 检测到 summarizing 状态时，触发 summarize（只触发一次）
      if (!summarizeTriggered.value) {
        summarizeTriggered.value = true
        console.log('检测到 summarizing 状态，触发 summarize...')
        const { error: summarizeError } = await supabase.functions.invoke('summarize', { 
          body: { task_id: taskId } 
        })
        if (summarizeError) {
          console.error('summarize 触发失败:', summarizeError)
          errorMessage.value = '触发纪要生成失败: ' + summarizeError.message
          isError.value = true
        }
      }
    } 
    else if (data.status === 'completed') {
      progress.value = 100
      statusText.value = '处理完成！'
      // 加载识别片段
      await loadSegments()
      // 清除轮询
      if (pollTimer) {
        clearTimeout(pollTimer)
        pollTimer = null
      }
      // 跳转到详情页（或者让用户手动点击查看）
      // router.push(`/tasks/${taskId}`)
      return
    } 
    else if (data.status === 'failed') {
      errorMessage.value = data.error_message || '处理失败，请重试'
      isError.value = true
      if (pollTimer) {
        clearTimeout(pollTimer)
        pollTimer = null
      }
      return
    }
    
    // 继续轮询（如果未完成且未失败）
    if (!['completed', 'failed'].includes(data.status)) {
      pollTimer = setTimeout(pollStatus, 2000) as unknown as number
    }
  } catch (error) {
    console.error('轮询状态失败:', error)
    // 出错时继续轮询
    pollTimer = setTimeout(pollStatus, 3000) as unknown as number
  }
}

// ===== 取消任务 =====
async function cancelTask() {
  canceling.value = true
  try {
    await supabase
      .from('tasks')
      .update({ status: 'completed', updated_at: new Date().toISOString() })
      .eq('id', props.id)
    
    // 清除轮询
    if (pollTimer) {
      clearTimeout(pollTimer)
      pollTimer = null
    }
    
    router.push(`/tasks/${props.id}`)
  } catch (error) {
    console.error('取消任务失败:', error)
  } finally {
    canceling.value = false
  }
}

// ===== 重试任务 =====
async function retryTask() {
  isError.value = false
  errorMessage.value = ''
  summarizeTriggered.value = false
  
  await supabase
    .from('tasks')
    .update({ 
      status: 'queued', 
      progress: 0, 
      error_message: null, 
      updated_at: new Date().toISOString() 
    })
    .eq('id', props.id)
  
  if (task.value) {
    task.value.status = 'queued'
    task.value.progress = 0
    task.value.error_message = null
  }
  
  startProcessing()
}

// ===== 生命周期 =====
onMounted(loadTask)

onUnmounted(() => {
  // 清除轮询定时器
  if (pollTimer) {
    clearTimeout(pollTimer)
    pollTimer = null
  }
})
</script>

<template>
  <div class="process-page">
    <div class="page-header">
      <button class="back-btn" @click="router.push('/tasks')">
        <ArrowLeft :size="18" />
        返回
      </button>
      <div class="header-info">
        <h1 v-if="task">{{ task.title }}</h1>
        <div v-if="task" class="header-status">
          <StatusBadge :status="task.status" />
          <span v-if="isProcessing" class="processing-hint">处理中...</span>
        </div>
      </div>
    </div>

    <div v-if="loading" class="loading">
      <Loader2 :size="24" class="spin" />
    </div>

    <div v-else-if="task" class="two-column">
      <!-- Left: Steps -->
      <div class="steps-panel">
        <h2 class="panel-title">处理进度</h2>
        <div class="steps-list">
          <div
            v-for="(step, i) in stepStatuses"
            :key="step.key"
            class="step-item"
            :class="step.state"
          >
            <div class="step-icon">
              <CheckCircle2 v-if="step.state === 'done'" :size="22" />
              <Loader2 v-else-if="step.state === 'active'" :size="22" class="spin" />
              <AlertCircle v-else-if="step.state === 'failed'" :size="22" />
              <component v-else :is="step.icon" :size="22" />
            </div>
            <div class="step-content">
              <div class="step-header">
                <span class="step-number">{{ i + 1 }}</span>
                <span class="step-label">{{ step.label }}</span>
                <span class="step-state-text" :class="step.state">
                  <template v-if="step.state === 'done'">已完成</template>
                  <template v-else-if="step.state === 'active'">{{ step.progress }}%</template>
                  <template v-else-if="step.state === 'failed'">失败</template>
                  <template v-else>等待中</template>
                </span>
              </div>
              <div v-if="step.state === 'active'" class="progress-bar">
                <div class="progress-fill" :style="{ width: step.progress + '%' }" />
              </div>
            </div>
          </div>
        </div>

        <div v-if="task.status === 'failed'" class="error-section">
          <div class="error-info">
            <AlertCircle :size="20" />
            <div>
              <p class="error-title">处理失败</p>
              <p class="error-msg">{{ task.error_message || '处理过程中出现错误' }}</p>
            </div>
          </div>
          <button class="retry-btn" @click="retryTask">
            <RotateCcw :size="16" />
            重试
          </button>
        </div>

        <div v-if="isProcessing" class="cancel-section">
          <button class="cancel-btn" :disabled="canceling" @click="cancelTask">
            <XCircle :size="16" />
            {{ canceling ? '取消中...' : '取消处理' }}
          </button>
          <p class="cancel-hint">取消后将保留已生成的部分结果</p>
        </div>

        <div v-if="task.status === 'completed'" class="completed-section">
          <button class="view-btn" @click="router.push(`/tasks/${task.id}`)">
            查看详情
          </button>
        </div>
      </div>

      <!-- Right: Live output -->
      <div class="output-panel">
        <h2 class="panel-title">实时输出</h2>
        <div class="output-content">
          <div v-if="segments.length === 0" class="output-empty">
            <AudioLines :size="32" />
            <p>等待语音识别开始...</p>
          </div>
          <div v-else class="transcript-stream">
            <div v-for="seg in segments" :key="seg.id" class="stream-segment">
              <span class="seg-time">{{ String(Math.floor(seg.start_time / 60)).padStart(2, '0') }}:{{ String(Math.floor(seg.start_time % 60)).padStart(2, '0') }}</span>
              <span v-if="seg.speaker" class="seg-speaker" :class="'speaker-' + (seg.speaker_index % 3)">{{ seg.speaker }}</span>
              <span class="seg-text">{{ seg.text }}</span>
            </div>
            <div v-if="isProcessing" class="typing-indicator">
              <span class="dot" />
              <span class="dot" />
              <span class="dot" />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.process-page {
  padding: 32px 40px;
  max-width: 1200px;
  margin: 0 auto;
}

.page-header {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-bottom: 24px;
}

.back-btn {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 8px 12px;
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.back-btn:hover {
  border-color: var(--color-primary-300);
  color: var(--color-primary-600);
}

.header-info {
  flex: 1;
}

.header-info h1 {
  font-size: 20px;
  font-weight: 700;
  margin-bottom: 6px;
}

.header-status {
  display: flex;
  align-items: center;
  gap: 10px;
}

.processing-hint {
  font-size: 13px;
  color: var(--color-primary-600);
  font-weight: 500;
}

.loading {
  display: flex;
  justify-content: center;
  padding: 80px;
}

.spin {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.two-column {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
}

.steps-panel, .output-panel {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: 24px;
}

.panel-title {
  font-size: 16px;
  font-weight: 600;
  margin-bottom: 20px;
}

.steps-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.step-item {
  display: flex;
  gap: 14px;
  padding: 16px 12px;
  border-radius: var(--radius-md);
  transition: background 0.2s ease;
}

.step-item.active {
  background: var(--color-primary-50);
}

.step-item.done .step-icon {
  color: var(--color-success-500);
}

.step-item.active .step-icon {
  color: var(--color-primary-500);
}

.step-item.failed .step-icon {
  color: var(--color-error-500);
}

.step-item.pending .step-icon {
  color: var(--color-gray-300);
}

.step-icon {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
}

.step-content {
  flex: 1;
}

.step-header {
  display: flex;
  align-items: center;
  gap: 8px;
}

.step-number {
  font-size: 13px;
  font-weight: 700;
  color: var(--color-text-muted);
}

.step-label {
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text);
}

.step-state-text {
  margin-left: auto;
  font-size: 13px;
  font-weight: 500;
}

.step-state-text.done { color: var(--color-success-600); }
.step-state-text.active { color: var(--color-primary-600); }
.step-state-text.failed { color: var(--color-error-500); }
.step-state-text.pending { color: var(--color-text-muted); }

.progress-bar {
  height: 6px;
  background: var(--color-primary-100);
  border-radius: 3px;
  margin-top: 10px;
  overflow: hidden;
}

.progress-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--color-primary-400), var(--color-primary-600));
  border-radius: 3px;
  transition: width 0.5s ease;
}

.error-section {
  margin-top: 24px;
  padding: 16px;
  background: var(--color-error-50);
  border: 1px solid var(--color-error-100);
  border-radius: var(--radius-md);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.error-info {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  color: var(--color-error-600);
}

.error-title {
  font-size: 14px;
  font-weight: 600;
}

.error-msg {
  font-size: 13px;
  margin-top: 2px;
}

.retry-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 16px;
  border-radius: var(--radius-sm);
  background: var(--color-error-500);
  color: white;
  font-size: 13px;
  font-weight: 600;
  flex-shrink: 0;
  transition: all 0.2s ease;
}

.retry-btn:hover {
  background: var(--color-error-600);
}

.cancel-section {
  margin-top: 24px;
  text-align: center;
}

.cancel-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 20px;
  border-radius: var(--radius-sm);
  background: var(--color-gray-100);
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 500;
  margin: 0 auto;
  transition: all 0.2s ease;
}

.cancel-btn:hover:not(:disabled) {
  background: var(--color-error-50);
  color: var(--color-error-500);
}

.cancel-btn:disabled {
  opacity: 0.5;
}

.cancel-hint {
  font-size: 12px;
  color: var(--color-text-muted);
  margin-top: 8px;
}

.completed-section {
  margin-top: 24px;
  text-align: center;
}

.view-btn {
  padding: 10px 28px;
  border-radius: var(--radius-md);
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600));
  color: white;
  font-size: 14px;
  font-weight: 600;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
  transition: all 0.2s ease;
}

.view-btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
}

.output-content {
  min-height: 400px;
  max-height: 500px;
  overflow-y: auto;
}

.output-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 80px 24px;
  color: var(--color-text-muted);
  font-size: 14px;
}

.transcript-stream {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.stream-segment {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 12px;
  border-radius: var(--radius-md);
  background: var(--color-surface-alt);
  animation: slideIn 0.3s ease;
}

@keyframes slideIn {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}

.seg-time {
  font-size: 12px;
  font-family: monospace;
  color: var(--color-text-muted);
  flex-shrink: 0;
  margin-top: 2px;
}

.seg-speaker {
  font-size: 12px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 10px;
  flex-shrink: 0;
}

.speaker-0 { background: #dbeafe; color: #2563eb; }
.speaker-1 { background: #dcfce7; color: #16a34a; }
.speaker-2 { background: #fef3c7; color: #d97706; }

.seg-text {
  font-size: 14px;
  color: var(--color-text);
  line-height: 1.5;
}

.typing-indicator {
  display: flex;
  gap: 4px;
  padding: 12px;
  align-items: center;
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--color-primary-400);
  animation: bounce 1.4s ease-in-out infinite;
}

.dot:nth-child(2) { animation-delay: 0.2s; }
.dot:nth-child(3) { animation-delay: 0.4s; }

@keyframes bounce {
  0%, 80%, 100% { transform: scale(0.6); opacity: 0.4; }
  40% { transform: scale(1); opacity: 1; }
}

@media (max-width: 900px) {
  .two-column {
    grid-template-columns: 1fr;
  }
  .process-page {
    padding: 20px 16px;
  }
}
</style>
