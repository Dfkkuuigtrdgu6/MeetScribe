import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/LoginView.vue'),
      meta: { public: true },
    },
    {
      path: '/',
      name: 'dashboard',
      component: () => import('../views/DashboardView.vue'),
    },
    {
      path: '/new',
      name: 'new-task',
      component: () => import('../views/NewTaskView.vue'),
    },
    {
      path: '/tasks/:id/process',
      name: 'task-process',
      component: () => import('../views/TaskProcessView.vue'),
      props: true,
    },
    {
      path: '/tasks',
      name: 'task-list',
      component: () => import('../views/TaskListView.vue'),
    },
    {
      path: '/tasks/:id',
      name: 'task-detail',
      component: () => import('../views/TaskDetailView.vue'),
      props: true,
    },
  ],
})

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession()
  const isAuthenticated = !!data.session

  if (!to.meta.public && !isAuthenticated) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (to.name === 'login' && isAuthenticated) {
    return { name: 'dashboard' }
  }
})

export default router