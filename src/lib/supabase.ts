import { createClient } from '@supabase/supabase-js'
import type { User } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseAnonKey)

export type TaskStatus = 'queued' | 'uploading' | 'transcribing' | 'segmenting' | 'summarizing' | 'completed' | 'failed'

export interface Task {
  id: string
  user_id: string
  title: string
  status: TaskStatus
  project_id: string | null
  audio_file_name: string | null
  audio_file_size: number | null
  audio_duration: number
  audio_url: string | null
  audio_storage_path: string | null
  language: string
  speaker_separation: boolean
  template_id: string | null
  notes: string | null
  summary_preview: string | null
  progress: number
  current_step: string | null
  error_message: string | null
  created_at: string
  updated_at: string
  project?: Project | null
  template?: Template | null
  task_tags?: { tag: Tag }[]
}

export interface Project {
  id: string
  user_id: string
  name: string
  color: string
  created_at: string
}

export interface Template {
  id: string
  user_id: string
  name: string
  prompt: string
  description: string | null
  icon: string
  created_at: string
}

export interface Tag {
  id: string
  user_id: string
  name: string
  created_at: string
}

export interface TranscriptSegment {
  id: string
  task_id: string
  speaker: string | null
  speaker_index: number
  start_time: number
  end_time: number
  text: string
  created_at: string
}

export interface TodoItem {
  id: string
  text: string
  assignee: string
  due_date: string
  done: boolean
}

export interface KeyPoint {
  id: string
  text: string
}

export interface Decision {
  id: string
  text: string
}

export interface Minutes {
  id: string
  task_id: string
  summary: string | null
  key_points: KeyPoint[]
  todos: TodoItem[]
  decisions: Decision[]
  notes: string | null
  version: number
  created_at: string
}

export const STATUS_LABELS: Record<TaskStatus, string> = {
  queued: '待处理',
  uploading: '上传中',
  transcribing: '识别中',
  segmenting: '分离中',
  summarizing: '提炼中',
  completed: '已完成',
  failed: '失败',
}

export const STATUS_COLORS: Record<TaskStatus, string> = {
  queued: 'gray',
  uploading: 'blue',
  transcribing: 'blue',
  segmenting: 'blue',
  summarizing: 'blue',
  completed: 'green',
  failed: 'red',
}

export function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) return '00:00'
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = Math.floor(seconds % 60)
  if (h > 0) return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

export function formatFileSize(bytes: number): string {
  if (!bytes) return '0 B'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`
}

export function formatDate(iso: string): string {
  const d = new Date(iso)
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

export function formatDateTime(iso: string): string {
  const d = new Date(iso)
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  const h = String(d.getHours()).padStart(2, '0')
  const min = String(d.getMinutes()).padStart(2, '0')
  return `${m}-${day} ${h}:${min}`
}

export function formatTime(seconds: number): string {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = Math.floor(seconds % 60)
  if (h > 0) return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

// ============================================================
// 认证辅助
// ============================================================
export async function getCurrentUser(): Promise<User | null> {
  const { data } = await supabase.auth.getUser()
  return data.user ?? null
}

export async function signIn(email: string, password: string) {
  return supabase.auth.signInWithPassword({ email, password })
}

export async function signUp(email: string, password: string) {
  return supabase.auth.signUp({ email, password })
}

export async function signOut() {
  return supabase.auth.signOut()
}

// ============================================================
// 私有 Storage 辅助（audio 桶，按 user_id 目录隔离）
// ============================================================
export const AUDIO_BUCKET = 'audio'

function sanitizeFileName(name: string): string {
  // Supabase Storage 对象键只允许 ASCII 字母 / 数字 / 点 / 下划线 / 连字符，
  // 中文等非 ASCII 字符会导致 "Invalid key" 上传失败。
  const cleaned = name
    .replace(/[^a-zA-Z0-9._-]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^[._-]+|[._-]+$/g, '')
  return cleaned || 'audio'
}

function sanitizeExt(ext: string): string {
  return /^[a-z0-9]+$/.test(ext) ? ext : 'bin'
}

export async function uploadPrivateAudio(userId: string, file: File): Promise<string> {
  const ext = sanitizeExt(file.name.split('.').pop()?.toLowerCase() || '')
  const safeName = sanitizeFileName(file.name.replace(/\.[^.]+$/, ''))
  const storagePath = `${userId}/${Date.now()}-${safeName}.${ext}`

  const { error } = await supabase.storage
    .from(AUDIO_BUCKET)
    .upload(storagePath, file, { contentType: file.type, upsert: false })

  if (error) throw error
  return storagePath
}

export async function getPrivateAudioUrl(storagePath: string | null | undefined): Promise<string | null> {
  if (!storagePath) return null
  const { data } = await supabase.storage.from(AUDIO_BUCKET).createSignedUrl(storagePath, 60 * 60)
  return data?.signedUrl ?? null
}

export async function removePrivateAudio(storagePath: string | null | undefined): Promise<void> {
  if (!storagePath) return
  await supabase.storage.from(AUDIO_BUCKET).remove([storagePath])
}