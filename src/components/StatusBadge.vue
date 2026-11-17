<script setup lang="ts">
import type { TaskStatus } from '../lib/supabase'
import { STATUS_LABELS } from '../lib/supabase'

const props = defineProps<{ status: TaskStatus }>()

const colorMap: Record<string, { bg: string; text: string; dot: string }> = {
  gray: { bg: '#f3f4f6', text: '#6b7280', dot: '#9ca3af' },
  blue: { bg: '#dbeafe', text: '#2563eb', dot: '#3b82f6' },
  green: { bg: '#dcfce7', text: '#16a34a', dot: '#22c55e' },
  red: { bg: '#fee2e2', text: '#dc2626', dot: '#ef4444' },
}

function getColor() {
  if (props.status === 'completed') return colorMap.green
  if (props.status === 'failed') return colorMap.red
  if (props.status === 'queued') return colorMap.gray
  return colorMap.blue
}
</script>

<template>
  <span
    class="status-badge"
    :style="{ background: getColor().bg, color: getColor().text }"
  >
    <span class="dot" :style="{ background: getColor().dot }" />
    {{ STATUS_LABELS[status] }}
  </span>
</template>

<style scoped>
.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
  white-space: nowrap;
}

.dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
}

.dot {
  animation: pulse 1.5s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}
</style>
