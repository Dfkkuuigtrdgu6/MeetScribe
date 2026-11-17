import { corsHeaders } from '../_shared/cors.ts'
import { createAdminClient } from '../_shared/supabaseClient.ts'

Deno.serve(async (req) => {
  // 浏览器 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. 解析前端传来的 task_id
    const { task_id } = await req.json()
    if (!task_id) {
      return jsonResponse({ error: 'task_id is required' }, 400)
    }

    console.log(`[transcribe] 开始处理任务: ${task_id}`)

        // 2. 从 tasks 表读取音频路径
        const supabase = createAdminClient()
        const { data: task, error: taskErr } = await supabase
          .from('tasks')
          .select('audio_storage_path, language, speaker_separation')
          .eq('id', task_id)
          .single()

        if (taskErr || !task) {
          throw new Error(`任务不存在或读取失败: ${taskErr?.message}`)
        }
        if (!task.audio_storage_path) {
          throw new Error('该任务未上传音频文件')
        }

        // 更新任务状态：进入转录中
        await supabase
          .from('tasks')
          .update({ status: 'transcribing', progress: 10, current_step: 'transcribing', updated_at: new Date().toISOString() })
          .eq('id', task_id)

        // 3. 生成音频的签名 URL（有效期 2 小时，供 Paraformer 下载）
        const { data: signed, error: signErr } = await supabase.storage
          .from('audio')
          .createSignedUrl(task.audio_storage_path, 60 * 60 * 2)

        if (signErr || !signed?.signedUrl) {
          throw new Error(`生成音频签名 URL 失败: ${signErr?.message}`)
        }
        const audioUrl = signed.signedUrl
        console.log(`[transcribe] 音频签名 URL 已生成`)

        // 4. 提交 Paraformer 任务（对应 Postman 请求 1）
        const dashscopeKey = Deno.env.get('DASHSCOPE_API_KEY')!
        const submitRes = await fetch(
          'https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription',
          {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${dashscopeKey}`,
              'Content-Type': 'application/json',
              'X-DashScope-Async': 'enable',
            },
            body: JSON.stringify({
              model: 'paraformer-v2',
              input: { file_urls: [audioUrl] },
              parameters: {
                channel_id: [0],
                language_hints: [task.language === 'auto' ? 'zh' : task.language],
                diarization_enabled: task.speaker_separation === true,
                ...(task.speaker_separation ? { speaker_count: 2 } : {}),
              },
            }),
          }
        )

        const submitJson = await submitRes.json()
        if (!submitRes.ok || submitJson.output?.task_status === 'FAILED') {
          throw new Error(`Paraformer 提交失败: ${JSON.stringify(submitJson)}`)
        }

        const paraformerTaskId = submitJson.output.task_id
        console.log(`[transcribe] Paraformer 任务已提交: ${paraformerTaskId}`)

            // 5. 轮询任务状态（对应 Postman 请求 2）
            let transcriptionUrl: string | null = null
            const maxAttempts = 120  // 最多轮询 120 次
            const intervalMs = 5000  // 每次间隔 5 秒 → 最长等 10 分钟

            for (let attempt = 1; attempt <= maxAttempts; attempt++) {
              await sleep(intervalMs)

              const queryRes = await fetch(
                `https://dashscope.aliyuncs.com/api/v1/tasks/${paraformerTaskId}`,
                {
                  headers: { 'Authorization': `Bearer ${dashscopeKey}` },
                }
              )
              const queryJson = await queryRes.json()
              const status = queryJson.output?.task_status

              console.log(`[transcribe] 轮询第 ${attempt} 次, 状态: ${status}`)

              // 更新前端进度（10% -> 60% 期间用轮询次数估算）
              const progress = Math.min(60, 10 + Math.floor((attempt / 20) * 50))
              await supabase
                .from('tasks')
                .update({ progress, updated_at: new Date().toISOString() })
                .eq('id', task_id)

              if (status === 'SUCCEEDED') {
                transcriptionUrl = queryJson.output.results?.[0]?.transcription_url
                if (!transcriptionUrl) {
                  throw new Error('Paraformer 返回成功但缺少 transcription_url')
                }
                break
              }

              if (status === 'FAILED') {
                const errMsg = queryJson.output?.message || 'Paraformer 处理失败'
                throw new Error(`Paraformer 失败: ${errMsg}`)
              }

              // PENDING 或 RUNNING 继续等
            }

            if (!transcriptionUrl) {
              throw new Error('Paraformer 处理超时（超过 10 分钟未完成）')
            }

            // 6. 下载转录结果 JSON
            console.log(`[transcribe] 下载转录结果 JSON`)
            const transcriptRes = await fetch(transcriptionUrl)
            if (!transcriptRes.ok) {
              throw new Error(`下载转录 JSON 失败: ${transcriptRes.status}`)
            }
            const transcriptJson = await transcriptRes.json()

               // 7. 解析 sentences，转换成数据库需要的格式
               const sentences = transcriptJson.transcripts?.[0]?.sentences ?? []
               if (sentences.length === 0) {
                 throw new Error('转录结果为空，未识别出任何句子')
               }

               console.log(`[transcribe] 识别到 ${sentences.length} 个句子，开始写入数据库`)

               // 先清空该任务旧的转录记录（避免重试时重复插入）
               await supabase.from('transcript_segments').delete().eq('task_id', task_id)

               // 组装批量插入数据
               const segmentsToInsert = sentences.map((s: any) => {
                 const speakerIndex = typeof s.speaker_id === 'number'
                   ? s.speaker_id
                   : parseInt(s.speaker_id ?? '0', 10) || 0
                 return {
                   task_id,
                   speaker: task.speaker_separation ? `发言人 ${speakerIndex + 1}` : null,
                   speaker_index: speakerIndex,
                   start_time: (s.begin_time ?? 0) / 1000,  // 毫秒 → 秒
                   end_time: (s.end_time ?? 0) / 1000,
                   text: s.text ?? '',
                 }
               })

               // 批量插入（分批以避免单次插入过大）
               const BATCH_SIZE = 100
               for (let i = 0; i < segmentsToInsert.length; i += BATCH_SIZE) {
                 const batch = segmentsToInsert.slice(i, i + BATCH_SIZE)
                 const { error: insertErr } = await supabase.from('transcript_segments').insert(batch)
                 if (insertErr) {
                   throw new Error(`写入转录片段失败: ${insertErr.message}`)
                 }
               }

               // 8. 更新任务状态：进入下一步（提炼纪要）
               await supabase
                 .from('tasks')
                 .update({
                   status: 'summarizing',
                   progress: 70,
                   current_step: 'summarizing',
                   updated_at: new Date().toISOString(),
                 })
                 .eq('id', task_id)

               console.log(`[transcribe] 完成，共写入 ${segmentsToInsert.length} 条记录`)

               return jsonResponse({
                 message: 'transcription complete',
                 task_id,
                 sentence_count: segmentsToInsert.length,
               })

    } catch (err) {
      console.error('[transcribe] 错误:', err)

      // 出错时把任务状态标记为 failed
      try {
        const { task_id } = await req.clone().json().catch(() => ({ task_id: null }))
        if (task_id) {
          const supabase = createAdminClient()
          await supabase
            .from('tasks')
            .update({
              status: 'failed',
              error_message: err.message || 'Unknown error',
              updated_at: new Date().toISOString(),
            })
            .eq('id', task_id)
        }
      } catch (_) { /* 忽略清理时的错误 */ }

      return jsonResponse({ error: err.message || 'Unknown error' }, 500)
    }
})

// 辅助函数：统一格式的 JSON 响应
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// 辅助函数：等待指定毫秒数
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}