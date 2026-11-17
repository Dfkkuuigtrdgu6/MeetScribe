<template>
  <div class="todo-summary-card">
    <div class="todo-summary-header">
      <div class="header-left">
        <h3>📋 待办事项汇总</h3>
        <span class="badge">{{ pendingTodos.length }} 项待办</span>
      </div>
    </div>
    
    <div v-if="loading" class="loading-state">加载中...</div>
    
    <div v-else-if="todos.length === 0" class="empty-state">
      <p>🎉 所有任务都已完成，暂无待办</p>
    </div>
    
    <div v-else>
      <!-- ===== 未完成待办 ===== -->
      <div v-if="pendingTodos.length > 0" class="todo-section">
        <div class="section-label">进行中</div>
        <div class="todo-summary-list">
          <div 
            v-for="todo in pendingDisplayTodos" 
            :key="todo.id" 
            class="todo-summary-item"
          >
            <!-- 【修改】点击圆点切换完成状态 -->
            <span class="todo-status" @click.stop="toggleTodo(todo)">
              <span class="status-circle"></span>
            </span>
            <span class="todo-text" @click="goToTask(todo.task_id)">{{ todo.text }}</span>
            <span class="todo-source" @click="goToTask(todo.task_id)">📎 {{ todo.task_title }}</span>
          </div>
          
          <div v-if="pendingTodos.length > 3" class="more-hint" @click="showAllPending = true">
            还有 {{ pendingTodos.length - 3 }} 项待办，点击查看全部 →
          </div>
        </div>
      </div>

      <!-- ===== 已完成待办（折叠/显示在最后） ===== -->
      <div v-if="completedTodos.length > 0" class="todo-section completed-section">
        <div class="section-label" @click="showCompleted = !showCompleted">
          <span>✅ 已完成 ({{ completedTodos.length }})</span>
          <span class="toggle-icon">{{ showCompleted ? '▼' : '▶' }}</span>
        </div>
        
        <div v-if="showCompleted" class="todo-summary-list">
          <div 
            v-for="todo in completedTodos" 
            :key="todo.id" 
            class="todo-summary-item done"
          >
            <span class="todo-status" @click.stop="toggleTodo(todo)">
              <span class="status-circle checked"></span>
            </span>
            <span class="todo-text" @click="goToTask(todo.task_id)">{{ todo.text }}</span>
            <span class="todo-source" @click="goToTask(todo.task_id)">📎 {{ todo.task_title }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- ===== 查看全部未完成待办的弹窗 ===== -->
    <div v-if="showAllPending" class="modal-overlay" @click.self="showAllPending = false">
      <div class="modal-content">
        <div class="modal-header">
          <h3>📋 全部待办事项 ({{ pendingTodos.length }})</h3>
          <button class="modal-close" @click="showAllPending = false">✕</button>
        </div>
        <div class="modal-body">
          <div 
            v-for="todo in pendingTodos" 
            :key="todo.id" 
            class="todo-summary-item"
          >
            <span class="todo-status" @click.stop="toggleTodo(todo)">
              <span class="status-circle"></span>
            </span>
            <span class="todo-text" @click="goToTask(todo.task_id)">{{ todo.text }}</span>
            <span class="todo-source" @click="goToTask(todo.task_id)">📎 {{ todo.task_title }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = useRouter()
const loading = ref(true)
const todos = ref<any[]>([])
const showAllPending = ref(false)
const showCompleted = ref(false)

// ===== 分组 =====
const pendingTodos = computed(() => todos.value.filter(t => !t.done))
const completedTodos = computed(() => todos.value.filter(t => t.done))
const pendingDisplayTodos = computed(() => pendingTodos.value.slice(0, 3))

const goToTask = (taskId: string) => {
  showAllPending.value = false
  router.push(`/tasks/${taskId}`)
}

// ===== 【核心】切换待办完成状态 =====
const toggleTodo = async (todo: any) => {
  try {
    // 切换本地状态（立即反馈）
    todo.done = !todo.done
    
    // 更新数据库中的 minutes 表
    // 先找到对应的 minutes 记录
    const { data: minutesData, error: findError } = await supabase
      .from('minutes')
      .select('id, todos')
      .eq('task_id', todo.task_id)
      .single()
    
    if (findError) throw findError
    
    // 更新 todos 数组中对应项的 done 状态
    const updatedTodos = minutesData.todos.map((item: any) => {
      // 匹配方式：如果 todo 是字符串，转为对象比较
      const itemText = typeof item === 'string' ? item : item.text
      if (itemText === todo.text || (item.id && item.id === todo.id)) {
        return { ...item, done: todo.done }
      }
      return item
    })
    
    // 保存到数据库
    const { error: updateError } = await supabase
      .from('minutes')
      .update({ todos: updatedTodos })
      .eq('id', minutesData.id)
    
    if (updateError) throw updateError
    
  } catch (error) {
    console.error('更新待办状态失败:', error)
    // 回滚本地状态
    todo.done = !todo.done
  }
}

const loadTodos = async () => {
  loading.value = true
  try {
    const { data: minutesData, error } = await supabase
      .from('minutes')
      .select('task_id, todos')
      .not('todos', 'is', null)
      .order('created_at', { ascending: false })
    
    if (error) throw error
    
    const taskIds = minutesData?.map((m: any) => m.task_id) || []
    const { data: tasks } = await supabase
      .from('tasks')
      .select('id, title')
      .in('id', taskIds.length > 0 ? taskIds : [''])
    
    const taskMap: Record<string, string> = {}
    tasks?.forEach((t: any) => { taskMap[t.id] = t.title })
    
    const allTodos: any[] = []
    minutesData?.forEach((record: any) => {
      if (Array.isArray(record.todos)) {
        record.todos.forEach((todo: any, index: number) => {
          // 兼容字符串和对象两种格式
          const isString = typeof todo === 'string'
          allTodos.push({
            id: `${record.task_id}-${index}`,
            text: isString ? todo : todo.text || '',
            done: isString ? false : (todo.done || false),
            assignee: isString ? '' : (todo.assignee || ''),
            due_date: isString ? '' : (todo.due_date || ''),
            task_id: record.task_id,
            task_title: taskMap[record.task_id] || '未命名任务',
            // 保存原始数据用于更新
            _minutesId: record.id,
            _rawTodo: todo
          })
        })
      }
    })
    
    todos.value = allTodos
  } catch (error) {
    console.error('加载待办失败:', error)
  } finally {
    loading.value = false
  }
}

onMounted(loadTodos)
</script>

<style scoped>
.todo-summary-card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: 20px 24px;
  margin-bottom: 20px;
}

.todo-summary-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 10px;
}

.todo-summary-header h3 {
  font-size: 16px;
  font-weight: 600;
  margin: 0;
}

.badge {
  background: var(--color-primary-100);
  color: var(--color-primary-600);
  padding: 2px 10px;
  border-radius: 12px;
  font-size: 13px;
  font-weight: 600;
}

.loading-state,
.empty-state {
  text-align: center;
  padding: 16px;
  color: var(--color-text-muted);
  font-size: 14px;
}

/* ===== 分组区域 ===== */
.todo-section {
  margin-bottom: 12px;
}

.todo-section:last-child {
  margin-bottom: 0;
}

.section-label {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text-secondary);
  padding: 4px 0 8px 0;
  border-bottom: 1px dashed var(--color-border);
  margin-bottom: 8px;
}

.completed-section .section-label {
  cursor: pointer;
  color: var(--color-text-muted);
  font-weight: 500;
}

.completed-section .section-label:hover {
  color: var(--color-text);
}

.toggle-icon {
  font-size: 12px;
  transition: transform 0.2s ease;
}

.todo-summary-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

/* ===== 单个待办项 ===== */
.todo-summary-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 10px;
  border-radius: var(--radius-sm);
  background: var(--color-surface-alt);
  transition: all 0.2s ease;
}

/* 【新增】已完成状态 - 降低透明度 */
.todo-summary-item.done {
  opacity: 0.5;
}

.todo-summary-item.done .todo-text {
  text-decoration: line-through;
  color: var(--color-text-muted);
}

.todo-summary-item:hover {
  background: var(--color-primary-50);
}

/* 【新增】圆点样式 - 可点击切换 */
.todo-status {
  flex-shrink: 0;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  transition: all 0.2s ease;
}

.status-circle {
  width: 16px;
  height: 16px;
  border-radius: 50%;
  border: 2px solid var(--color-text-muted);
  display: inline-block;
  transition: all 0.2s ease;
}

.status-circle:hover {
  border-color: var(--color-primary-500);
  transform: scale(1.1);
}

/* 【新增】已完成状态的圆点 - 带勾 */
.status-circle.checked {
  background: var(--color-success-500);
  border-color: var(--color-success-500);
  position: relative;
}

.status-circle.checked::after {
  content: '✓';
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  color: white;
  font-size: 10px;
  font-weight: 700;
}

/* 点击任务文字跳转 */
.todo-text {
  flex: 1;
  font-size: 14px;
  cursor: pointer;
}

.todo-source {
  font-size: 12px;
  color: var(--color-text-muted);
  flex-shrink: 0;
  cursor: pointer;
}

.more-hint {
  text-align: center;
  font-size: 13px;
  color: var(--color-primary-500);
  padding: 6px;
  cursor: pointer;
  font-weight: 500;
  border-radius: var(--radius-sm);
  transition: all 0.2s ease;
}

.more-hint:hover {
  background: var(--color-primary-50);
}

/* ===== 弹窗样式 ===== */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 20px;
}

.modal-content {
  background: var(--color-surface);
  border-radius: var(--radius-lg);
  max-width: 600px;
  width: 100%;
  max-height: 80vh;
  box-shadow: var(--shadow-xl);
  overflow: hidden;
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 24px;
  border-bottom: 1px solid var(--color-border);
}

.modal-header h3 {
  font-size: 18px;
  font-weight: 600;
}

.modal-close {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: var(--color-gray-100);
  color: var(--color-text-secondary);
  font-size: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.modal-close:hover {
  background: var(--color-error-50);
  color: var(--color-error-500);
}

.modal-body {
  padding: 16px 24px 24px;
  max-height: calc(80vh - 70px);
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
</style>