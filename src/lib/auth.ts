import { ref } from 'vue'
import type { User } from '@supabase/supabase-js'
import { supabase, signIn, signUp, signOut, getCurrentUser } from './supabase'

const user = ref<User | null>(null)
const loading = ref(true)

export async function initAuth() {
  user.value = await getCurrentUser()
  loading.value = false
}

// 监听认证状态变化（登录/登出/令牌刷新）
supabase.auth.onAuthStateChange((_event, session) => {
  user.value = session?.user ?? null
  loading.value = false
})

export function useAuth() {
  return { user, loading, initAuth, signIn, signUp, signOut }
}