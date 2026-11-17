<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuth } from './lib/auth'
import {
  LayoutDashboard,
  PlusCircle,
  ListChecks,
  Mic,
  AudioLines,
  ChevronLeft,
  LogOut,
} from 'lucide-vue-next'

const router = useRouter()
const route = useRoute()
const collapsed = ref(false)
const { user, loading, initAuth, signOut } = useAuth()

onMounted(async () => {
  if (loading.value) await initAuth()
})

async function handleLogout() {
  await signOut()
  router.replace('/login')
}

const navItems = [
  { name: 'dashboard', label: '工作台', icon: LayoutDashboard, path: '/' },
  { name: 'new-task', label: '新建任务', icon: PlusCircle, path: '/new' },
  { name: 'task-list', label: '任务列表', icon: ListChecks, path: '/tasks' },
]

function navigate(path: string) {
  router.push(path)
}

function isActive(name: string): boolean {
  if (name === 'task-list') {
    return route.name === 'task-list' || route.name === 'task-detail'
  }
  return route.name === name
}
</script>

<template>
  <div class="app-shell" :class="{ collapsed: collapsed }">
    <aside class="sidebar">
      <div class="logo-area">
        <div class="logo-icon">
          <AudioLines :size="24" />
        </div>
        <transition name="fade">
          <span v-if="!collapsed" class="logo-text">语音纪要</span>
        </transition>
      </div>

      <nav class="nav">
        <button
          v-for="item in navItems"
          :key="item.name"
          class="nav-item"
          :class="{ active: isActive(item.name) }"
          @click="navigate(item.path)"
        >
          <component :is="item.icon" :size="20" class="nav-icon" />
          <transition name="fade">
            <span v-if="!collapsed" class="nav-label">{{ item.label }}</span>
          </transition>
        </button>
      </nav>

      <div class="sidebar-footer">
        <button class="quick-record" @click="navigate('/new?mode=record')">
          <Mic :size="18" />
          <transition name="fade">
            <span v-if="!collapsed">快速录音</span>
          </transition>
        </button>

        <div v-if="user" class="user-box">
          <div class="user-avatar">{{ user.email?.slice(0, 1).toUpperCase() }}</div>
          <transition name="fade">
            <div v-if="!collapsed" class="user-info">
              <span class="user-email" :title="user.email">{{ user.email }}</span>
            </div>
          </transition>
          <button class="logout-btn" title="退出登录" @click="handleLogout">
            <LogOut :size="16" />
          </button>
        </div>
      </div>

      <button class="collapse-btn" @click="collapsed = !collapsed">
        <ChevronLeft :size="18" :class="{ rotated: collapsed }" />
      </button>
    </aside>

    <main class="main-content">
      <router-view v-slot="{ Component }">
        <transition name="fade" mode="out-in">
          <component :is="Component" />
        </transition>
      </router-view>
    </main>
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  min-height: 100vh;
}

.sidebar {
  width: 240px;
  background: var(--color-surface);
  border-right: 1px solid var(--color-border);
  display: flex;
  flex-direction: column;
  padding: 20px 16px;
  position: fixed;
  top: 0;
  left: 0;
  bottom: 0;
  z-index: 100;
  transition: width 0.3s ease;
}

.app-shell.collapsed .sidebar {
  width: 72px;
}

.logo-area {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 8px 24px;
}

.logo-icon {
  width: 40px;
  height: 40px;
  border-radius: var(--radius-md);
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-accent-500));
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  flex-shrink: 0;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.3);
}

.logo-text {
  font-size: 18px;
  font-weight: 700;
  color: var(--color-text);
  white-space: nowrap;
}

.nav {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  border-radius: var(--radius-md);
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 14px;
  font-weight: 500;
  transition: all 0.2s ease;
  white-space: nowrap;
  width: 100%;
}

.nav-item:hover {
  background: var(--color-primary-50);
  color: var(--color-primary-600);
}

.nav-item.active {
  background: var(--color-primary-50);
  color: var(--color-primary-600);
}

.nav-item.active .nav-icon {
  color: var(--color-primary-600);
}

.nav-icon {
  flex-shrink: 0;
  color: var(--color-text-muted);
  transition: color 0.2s ease;
}

.nav-label {
  white-space: nowrap;
}

.sidebar-footer {
  margin-top: auto;
  padding-top: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.user-box {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px;
  border-top: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-gray-100);
}

.user-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-accent-500));
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 14px;
  flex-shrink: 0;
}

.user-info {
  flex: 1;
  min-width: 0;
}

.user-email {
  display: block;
  font-size: 12px;
  color: var(--color-text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.logout-btn {
  margin-left: auto;
  width: 28px;
  height: 28px;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--color-text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: all 0.2s ease;
}

.logout-btn:hover {
  background: var(--color-error-50);
  color: var(--color-error-500);
}

.quick-record {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border-radius: var(--radius-md);
  background: linear-gradient(135deg, var(--color-primary-500), var(--color-accent-500));
  color: white;
  font-size: 14px;
  font-weight: 600;
  width: 100%;
  transition: all 0.2s ease;
  white-space: nowrap;
  box-shadow: 0 2px 8px rgba(59, 130, 246, 0.25);
}

.quick-record:hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.35);
}

.collapse-btn {
  position: absolute;
  bottom: 16px;
  right: -12px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--color-text-muted);
  transition: all 0.2s ease;
}

.collapse-btn:hover {
  color: var(--color-primary-600);
  border-color: var(--color-primary-300);
}

.rotated {
  transform: rotate(180deg);
}

.main-content {
  flex: 1;
  margin-left: 240px;
  min-height: 100vh;
  transition: margin-left 0.3s ease;
}

.app-shell.collapsed .main-content {
  margin-left: 72px;
}

@media (max-width: 768px) {
  .sidebar {
    width: 72px;
  }
  .logo-text, .nav-label, .quick-record span {
    display: none;
  }
  .main-content {
    margin-left: 72px;
  }
}
</style>
