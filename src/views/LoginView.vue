<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { signIn, signUp } from '../lib/supabase'
import { AudioLines, Mail, Lock, Loader2, AlertCircle, ArrowRight } from 'lucide-vue-next'

const router = useRouter()
const route = useRoute()

const mode = ref<'login' | 'register'>('login')
const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const loading = ref(false)
const errorMsg = ref('')

const isLogin = computed(() => mode.value === 'login')

async function submit() {
  errorMsg.value = ''

  if (!email.value || !password.value) {
    errorMsg.value = '请输入邮箱和密码'
    return
  }
  if (!isLogin.value && password.value.length < 6) {
    errorMsg.value = '密码至少 6 位'
    return
  }
  if (!isLogin.value && password.value !== confirmPassword.value) {
    errorMsg.value = '两次输入的密码不一致'
    return
  }

  loading.value = true
  try {
    if (isLogin.value) {
      const { error } = await signIn(email.value.trim(), password.value)
      if (error) throw error
    } else {
      const { error } = await signUp(email.value.trim(), password.value)
      if (error) throw error
      // 注册成功后自动登录（未开启邮箱确认时）
      const { error: loginError } = await signIn(email.value.trim(), password.value)
      if (loginError) throw loginError
    }

    const redirect = (route.query.redirect as string) || '/'
    router.replace(redirect)
  } catch (err: any) {
    errorMsg.value = err?.message || '操作失败，请重试'
  } finally {
    loading.value = false
  }
}

function switchMode() {
  mode.value = isLogin.value ? 'register' : 'login'
  errorMsg.value = ''
  confirmPassword.value = ''
}
</script>

<template>
  <div class="login-page">
    <div class="login-card">
      <div class="brand">
        <div class="brand-icon">
          <AudioLines :size="28" />
        </div>
        <h1>语音纪要</h1>
        <p>AI 语音转写与会议纪要，让每次会议都被妥善记录</p>
      </div>

      <div class="tabs">
        <button :class="{ active: isLogin }" @click="switchMode()">登录</button>
        <button :class="{ active: !isLogin }" @click="switchMode()">注册</button>
      </div>

      <div v-if="errorMsg" class="error-banner">
        <AlertCircle :size="16" />
        {{ errorMsg }}
      </div>

      <form class="form" @submit.prevent="submit">
        <label class="field">
          <Mail :size="16" class="field-icon" />
          <input v-model="email" type="email" placeholder="邮箱地址" autocomplete="email" />
        </label>

        <label class="field">
          <Lock :size="16" class="field-icon" />
          <input v-model="password" type="password" placeholder="密码" autocomplete="current-password" />
        </label>

        <label v-if="!isLogin" class="field">
          <Lock :size="16" class="field-icon" />
          <input v-model="confirmPassword" type="password" placeholder="确认密码" autocomplete="new-password" />
        </label>

        <button class="submit-btn" type="submit" :disabled="loading">
          <Loader2 v-if="loading" :size="18" class="spin" />
          <template v-else>
            {{ isLogin ? '登录' : '注册并开始使用' }}
            <ArrowRight :size="18" />
          </template>
        </button>
      </form>

      <p class="hint">
        {{ isLogin ? '还没有账号？' : '已有账号？' }}
        <button class="link" @click="switchMode">{{ isLogin ? '立即注册' : '去登录' }}</button>
      </p>
    </div>
  </div>
</template>

<style scoped>
.login-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background:
    radial-gradient(circle at 20% 20%, rgba(59, 130, 246, 0.12), transparent 40%),
    radial-gradient(circle at 80% 80%, rgba(6, 182, 212, 0.12), transparent 40%),
    var(--color-bg, #f8fafc);
}

.login-card {
  width: 100%;
  max-width: 400px;
  background: var(--color-surface, #fff);
  border: 1px solid var(--color-border, #e5e7eb);
  border-radius: 16px;
  padding: 40px 32px;
  box-shadow: 0 20px 60px rgba(15, 23, 42, 0.08);
}

.brand {
  text-align: center;
  margin-bottom: 28px;
}

.brand-icon {
  width: 56px;
  height: 56px;
  border-radius: 14px;
  background: linear-gradient(135deg, #3b82f6, #06b6d4);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 auto 16px;
}

.brand h1 {
  font-size: 22px;
  font-weight: 700;
  color: var(--color-text, #0f172a);
  margin-bottom: 6px;
}

.brand p {
  font-size: 13px;
  color: var(--color-text-secondary, #64748b);
  line-height: 1.5;
}

.tabs {
  display: flex;
  background: var(--color-gray-100, #f1f5f9);
  border-radius: 10px;
  padding: 4px;
  margin-bottom: 20px;
}

.tabs button {
  flex: 1;
  padding: 10px;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  color: var(--color-text-secondary, #64748b);
  transition: all 0.2s ease;
}

.tabs button.active {
  background: #fff;
  color: #2563eb;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.08);
}

.error-banner {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  background: #fef2f2;
  border: 1px solid #fee2e2;
  color: #dc2626;
  border-radius: 10px;
  font-size: 13px;
  margin-bottom: 16px;
}

.form {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.field {
  position: relative;
  display: block;
}

.field-icon {
  position: absolute;
  left: 14px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--color-text-muted, #94a3b8);
}

.field input {
  width: 100%;
  padding: 13px 14px 13px 42px;
  border: 1px solid var(--color-border, #e5e7eb);
  border-radius: 10px;
  font-size: 14px;
  color: var(--color-text, #0f172a);
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}

.field input:focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.12);
}

.submit-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 13px;
  border-radius: 10px;
  background: linear-gradient(135deg, #3b82f6, #2563eb);
  color: #fff;
  font-size: 15px;
  font-weight: 600;
  box-shadow: 0 4px 14px rgba(59, 130, 246, 0.35);
  transition: all 0.2s ease;
  margin-top: 4px;
}

.submit-btn:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: 0 6px 20px rgba(59, 130, 246, 0.45);
}

.submit-btn:disabled {
  opacity: 0.6;
}

.spin {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.hint {
  text-align: center;
  margin-top: 20px;
  font-size: 13px;
  color: var(--color-text-secondary, #64748b);
}

.link {
  color: #2563eb;
  font-weight: 600;
}

.link:hover {
  text-decoration: underline;
}
</style>