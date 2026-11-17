<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase, formatDateTime, formatDuration, STATUS_LABELS, type Task, type Project, type TaskStatus } from '../lib/supabase'
import StatusBadge from '../components/StatusBadge.vue'
import {
  Search,
  PlusCircle,
  ChevronDown,
  Eye,
  Download,
  Trash2,
  RotateCcw,
  XCircle,
  CheckSquare,
  Square,
  ChevronLeft,
  ChevronRight,
  FileText,
} from 'lucide-vue-next'

const router = useRouter()
const tasks = ref<Task[]>([])
const projects = ref<Project[]>([])
const loading = ref(true)

const searchQuery = ref('')
const statusFilter = ref<TaskStatus | ''>('')
const projectFilter = ref<string>('')
const sortBy = ref<'created_desc' | 'created_asc' | 'duration_desc' | 'status'>('created_desc')

const selectedIds = ref<Set<string>>(new Set())
const currentPage = ref(1)
const pageSize = 10

const filteredTasks = computed(() => {
  let result = [...tasks.value]
  if (searchQuery.value) {
    const q = searchQuery.value.toLowerCase()
    result = result.filter(t =>
      t.title.toLowerCase().includes(q) ||
      (t.summary_preview || '').toLowerCase().includes(q)
    )
  }
  if (statusFilter.value) {
    result = result.filter(t => t.status === statusFilter.value)
  }
  if (projectFilter.value) {
    result = result.filter(t => t.project_id === projectFilter.value)
  }
  switch (sortBy.value) {
    case 'created_desc':
      result.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
      break
    case 'created_asc':
      result.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())
      break
    case 'duration_desc':
      result.sort((a, b) => b.audio_duration - a.audio_duration)
      break
    case 'status':
      result.sort((a, b) => a.status.localeCompare(b.status))
      break
  }
  return result
})

const totalPages = computed(() => Math.ceil(filteredTasks.value.length / pageSize) || 1)
const pagedTasks = computed(() => {
  const start = (currentPage.value - 1) * pageSize
  return filteredTasks.value.slice(start, start + pageSize)
})

const allSelected = computed(() =>
  pagedTasks.value.length > 0 && pagedTasks.value.every(t => selectedIds.value.has(t.id))
)

function toggleSelect(id: string) {
  if (selectedIds.value.has(id)) selectedIds.value.delete(id)
  else selectedIds.value.add(id)
}

function toggleSelectAll() {
  if (allSelected.value) {
    pagedTasks.value.forEach(t => selectedIds.value.delete(t.id))
  } else {
    pagedTasks.value.forEach(t => selectedIds.value.add(t.id))
  }
}

async function deleteTask(id: string) {
  if (!confirm('确定要删除这个任务吗？')) return
  await supabase.from('tasks').delete().eq('id', id)
  tasks.value = tasks.value.filter(t => t.id !== id)
}

async function batchDelete() {
  if (selectedIds.value.size === 0) return
  if (!confirm(`确定要删除选中的 ${selectedIds.value.size} 个任务吗？`)) return
  const ids = Array.from(selectedIds.value)
  await supabase.from('tasks').delete().in('id', ids)
  tasks.value = tasks.value.filter(t => !selectedIds.value.has(t.id))
  selectedIds.value.clear()
}

async function reprocess(id: string) {
  await supabase.from('tasks').update({ status: 'queued', progress: 0, error_message: null, updated_at: new Date().toISOString() }).eq('id', id)
  router.push(`/tasks/${id}/process`)
}

async function cancelTask(id: string) {
  await supabase.from('tasks').update({ status: 'completed', updated_at: new Date().toISOString() }).eq('id', id)
  const t = tasks.value.find(x => x.id === id)
  if (t) t.status = 'completed'
}

function exportTask(task: Task) {
  const content = `# ${task.title}\n\n## 摘要\n${task.summary_preview || ''}\n\n## 基本信息\n- 创建时间: ${formatDateTime(task.created_at)}\n- 时长: ${formatDuration(task.audio_duration)}\n- 状态: ${STATUS_LABELS[task.status]}\n`
  const blob = new Blob([content], { type: 'text/markdown' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${task.title}.md`
  a.click()
  URL.revokeObjectURL(url)
}

async function batchExport() {
  for (const id of selectedIds.value) {
    const task = tasks.value.find(t => t.id === id)
    if (task) exportTask(task)
  }
}

async function loadData() {
  loading.value = true
  const [tasksRes, projectsRes] = await Promise.all([
    supabase.from('tasks').select('*, project:projects(*), task_tags(tag:tags(*))').order('created_at', { ascending: false }),
    supabase.from('projects').select('*').order('name'),
  ])
  tasks.value = tasksRes.data || []
  projects.value = projectsRes.data || []
  loading.value = false
}

onMounted(loadData)
</script>

<template>
  <div class="task-list-page">
    <div class="page-header">
      <div>
        <h1>录音任务</h1>
        <p>管理所有录音任务，支持搜索、筛选和批量操作</p>
      </div>
      <button class="new-btn" @click="router.push('/new')">
        <PlusCircle :size="18" />
        新建任务
      </button>
    </div>

    <!-- Filters -->
    <div class="filters-bar">
      <div class="search-box">
        <Search :size="16" class="search-icon" />
        <input v-model="searchQuery" type="text" placeholder="搜索任务标题或关键词..." />
      </div>

      <div class="filter-group">
        <div class="select-wrapper">
          <select v-model="statusFilter" class="filter-select">
            <option value="">全部状态</option>
            <option value="queued">待处理</option>
            <option value="transcribing">处理中</option>
            <option value="completed">已完成</option>
            <option value="failed">失败</option>
          </select>
          <ChevronDown :size="14" class="select-arrow" />
        </div>

        <div class="select-wrapper">
          <select v-model="projectFilter" class="filter-select">
            <option value="">全部项目</option>
            <option v-for="p in projects" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
          <ChevronDown :size="14" class="select-arrow" />
        </div>

        <div class="select-wrapper">
          <select v-model="sortBy" class="filter-select">
            <option value="created_desc">创建时间↓</option>
            <option value="created_asc">创建时间↑</option>
            <option value="duration_desc">录音时长↓</option>
            <option value="status">状态</option>
          </select>
          <ChevronDown :size="14" class="select-arrow" />
        </div>
      </div>
    </div>

    <!-- Table -->
    <div class="table-container">
      <div v-if="loading" class="loading">
        <div class="skeleton-row" v-for="i in 5" :key="i" />
      </div>

      <div v-else-if="pagedTasks.length === 0" class="empty-state">
        <FileText :size="40" />
        <p>没有找到匹配的任务</p>
      </div>

      <table v-else class="data-table">
        <thead>
          <tr>
            <th class="col-check">
              <button class="check-btn" @click="toggleSelectAll">
                <component :is="allSelected ? CheckSquare : Square" :size="16" />
              </button>
            </th>
            <th>任务标题</th>
            <th>项目</th>
            <th>状态</th>
            <th>时长</th>
            <th>创建时间</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="task in pagedTasks" :key="task.id">
            <td class="col-check">
              <button class="check-btn" @click="toggleSelect(task.id)">
                <component :is="selectedIds.has(task.id) ? CheckSquare : Square" :size="16" />
              </button>
            </td>
            <td>
              <span class="task-title-cell" @click="router.push(`/tasks/${task.id}`)">
                {{ task.title }}
              </span>
            </td>
            <td>
              <span v-if="task.project" class="project-tag" :style="{ background: task.project.color + '15', color: task.project.color }">
                {{ task.project.name }}
              </span>
              <span v-else class="no-project">-</span>
            </td>
            <td><StatusBadge :status="task.status" /></td>
            <td class="col-duration">{{ formatDuration(task.audio_duration) }}</td>
            <td class="col-date">{{ formatDateTime(task.created_at) }}</td>
            <td>
              <div class="action-btns">
                <button class="action-btn" title="查看" @click="router.push(`/tasks/${task.id}`)">
                  <Eye :size="15" />
                </button>
                <button class="action-btn" title="导出" @click="exportTask(task)">
                  <Download :size="15" />
                </button>
                <button v-if="task.status === 'failed'" class="action-btn" title="重新处理" @click="reprocess(task.id)">
                  <RotateCcw :size="15" />
                </button>
                <button v-if="['queued','uploading','transcribing','segmenting','summarizing'].includes(task.status)" class="action-btn" title="取消" @click="cancelTask(task.id)">
                  <XCircle :size="15" />
                </button>
                <button class="action-btn danger" title="删除" @click="deleteTask(task.id)">
                  <Trash2 :size="15" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Footer -->
    <div class="table-footer">
      <div class="batch-actions" v-if="selectedIds.size > 0">
        <span class="selected-count">已选 {{ selectedIds.size }} 项</span>
        <button class="batch-btn" @click="batchExport">
          <Download :size="14" />
          批量导出
        </button>
        <button class="batch-btn danger" @click="batchDelete">
          <Trash2 :size="14" />
          批量删除
        </button>
      </div>
      <div class="pagination">
        <button class="page-btn" :disabled="currentPage <= 1" @click="currentPage--">
          <ChevronLeft :size="16" />
        </button>
        <span class="page-info">{{ currentPage }} / {{ totalPages }}</span>
        <button class="page-btn" :disabled="currentPage >= totalPages" @click="currentPage++">
          <ChevronRight :size="16" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.task-list-page {
  padding: 32px 40px;
  max-width: 1200px;
  margin: 0 auto;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 24px;
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

.new-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 20px;
  border-radius: var(--radius-md);
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600));
  color: white;
  font-size: 14px;
  font-weight: 600;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
  transition: all 0.2s ease;
}

.new-btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
}

.filters-bar {
  display: flex;
  gap: 12px;
  margin-bottom: 16px;
  flex-wrap: wrap;
  align-items: center;
}

.search-box {
  position: relative;
  flex: 1;
  min-width: 200px;
}

.search-icon {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--color-text-muted);
}

.search-box input {
  width: 100%;
  padding: 10px 12px 10px 36px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  font-size: 14px;
  color: var(--color-text);
  transition: border-color 0.2s ease;
}

.search-box input:focus {
  outline: none;
  border-color: var(--color-primary-400);
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

.filter-group {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.select-wrapper {
  position: relative;
}

.filter-select {
  appearance: none;
  padding: 10px 32px 10px 14px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  font-size: 13px;
  color: var(--color-text);
  cursor: pointer;
  transition: border-color 0.2s ease;
}

.filter-select:focus {
  outline: none;
  border-color: var(--color-primary-400);
}

.select-arrow {
  position: absolute;
  right: 10px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--color-text-muted);
  pointer-events: none;
}

.table-container {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  overflow: hidden;
}

.loading {
  padding: 16px;
}

.skeleton-row {
  height: 52px;
  background: var(--color-surface-alt);
  border-bottom: 1px solid var(--color-border);
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
  padding: 64px;
  color: var(--color-text-muted);
}

.data-table {
  width: 100%;
  border-collapse: collapse;
}

.data-table th {
  padding: 12px 16px;
  text-align: left;
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text-secondary);
  background: var(--color-surface-alt);
  border-bottom: 1px solid var(--color-border);
  white-space: nowrap;
}

.data-table td {
  padding: 12px 16px;
  font-size: 14px;
  color: var(--color-text);
  border-bottom: 1px solid var(--color-border);
}

.data-table tbody tr {
  transition: background 0.15s ease;
}

.data-table tbody tr:hover {
  background: var(--color-primary-50);
}

.col-check {
  width: 40px;
  text-align: center;
}

.col-duration, .col-date {
  white-space: nowrap;
  color: var(--color-text-secondary);
  font-size: 13px;
}

.check-btn {
  background: none;
  color: var(--color-text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
}

.check-btn:hover {
  color: var(--color-primary-500);
}

.task-title-cell {
  font-weight: 500;
  color: var(--color-primary-600);
  cursor: pointer;
  transition: opacity 0.2s ease;
}

.task-title-cell:hover {
  opacity: 0.7;
}

.project-tag {
  display: inline-block;
  padding: 2px 10px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;
}

.no-project {
  color: var(--color-text-muted);
}

.action-btns {
  display: flex;
  gap: 4px;
}

.action-btn {
  width: 30px;
  height: 30px;
  border-radius: var(--radius-sm);
  background: var(--color-gray-100);
  color: var(--color-text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.action-btn:hover {
  background: var(--color-primary-50);
  color: var(--color-primary-600);
}

.action-btn.danger:hover {
  background: var(--color-error-50);
  color: var(--color-error-500);
}

.table-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 16px;
  flex-wrap: wrap;
  gap: 12px;
}

.batch-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.selected-count {
  font-size: 13px;
  color: var(--color-text-secondary);
  font-weight: 500;
}

.batch-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  color: var(--color-text);
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
}

.batch-btn:hover {
  border-color: var(--color-primary-300);
  background: var(--color-primary-50);
}

.batch-btn.danger:hover {
  border-color: var(--color-error-300);
  background: var(--color-error-50);
  color: var(--color-error-600);
}

.pagination {
  display: flex;
  align-items: center;
  gap: 8px;
}

.page-btn {
  width: 32px;
  height: 32px;
  border-radius: var(--radius-sm);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  color: var(--color-text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.page-btn:hover:not(:disabled) {
  border-color: var(--color-primary-300);
  color: var(--color-primary-600);
}

.page-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.page-info {
  font-size: 13px;
  color: var(--color-text-secondary);
  padding: 0 8px;
}

@media (max-width: 768px) {
  .task-list-page {
    padding: 20px 16px;
  }
  .data-table {
    font-size: 12px;
  }
  .data-table th, .data-table td {
    padding: 8px;
  }
  .col-date {
    display: none;
  }
}
</style>
