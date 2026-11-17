import { corsHeaders } from '../_shared/cors.ts'
import { createAdminClient } from '../_shared/supabaseClient.ts'

// 沿用你 Postman 里调好的 system prompt
const SYSTEM_PROMPT = `你是一位专业的会议纪要助手。用户会给你一段音频转录文本（可能是会议、访谈、播客或任何口语内容）。请你分析内容，提炼出结构化纪要，并**严格**按照以下 JSON 格式返回，不要输出任何 JSON 以外的文字：

{
  "summary": "200 字以内的整体摘要",
  "key_points": [
    { "id": "1", "text": "要点1的具体内容" },
    { "id": "2", "text": "要点2的具体内容" }
  ],
  "todos": [
    { "id": "1", "text": "待办事项描述", "assignee": "负责人姓名或空字符串", "due_date": "截止时间或空字符串", "done": false }
  ],
  "decisions": [
    { "id": "1", "text": "明确达成的决策内容" }
  ]
}

规则：
1. 如果内容里没有明确的待办事项，todos 返回空数组 []
2. 如果内容里没有明确的决策，decisions 返回空数组 []
3. key_points 至少 3 条，最多 8 条
4. 每一项的 id 从 "1" 开始按顺序编号
5. assignee 和 due_date 如果原文没提到就填空字符串 ""，不要编造
6. done 字段永远填 false
7. 只输出 JSON，不要解释、不要 markdown 代码块、不要前后任何文字`

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { task_id } = await req.json()
    if (!task_id) {
      return jsonResponse({ error: 'task_id is required' }, 400)
    }

    console.log(`[summarize] 开始处理任务: ${task_id}`)
    const supabase = createAdminClient()

    // 1. 读取该任务的所有转录片段
    const { data: segments, error: segErr } = await supabase
      .from('transcript_segments')
      .select('text, speaker')
      .eq('task_id', task_id)
      .order('start_time', { ascending: true })

    if (segErr) {
      throw new Error(`读取转录片段失败: ${segErr.message}`)
    }
    if (!segments || segments.length === 0) {
      throw new Error('该任务没有转录内容，请先完成转录')
    }

    // 2. 拼接完整转录文本
    const fullText = segments
      .map((s) => (s.speaker ? `${s.speaker}: ${s.text}` : s.text))
      .join('\n')
    console.log(`[summarize] 转录文本长度: ${fullText.length} 字`)

    // 3. 更新进度
    await supabase
      .from('tasks')
      .update({ progress: 80, current_step: 'summarizing', updated_at: new Date().toISOString() })
      .eq('id', task_id)

    // 4. 调 DeepSeek 提炼纪要（对应 Postman 请求 3）
    const deepseekKey = Deno.env.get('DEEPSEEK_API_KEY')!
    const chatRes = await fetch('https://api.deepseek.com/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${deepseekKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'deepseek-chat',
        response_format: { type: 'json_object' },
        temperature: 0.3,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: `请为以下转录文本生成会议纪要：\n\n${fullText}` },
        ],
      }),
    })

    if (!chatRes.ok) {
      const errText = await chatRes.text()
      throw new Error(`DeepSeek 请求失败: ${chatRes.status} ${errText}`)
    }

    const chatJson = await chatRes.json()
    const content = chatJson.choices?.[0]?.message?.content
    if (!content) {
      throw new Error('DeepSeek 返回内容为空')
    }
    console.log(`[summarize] DeepSeek 返回，tokens: ${chatJson.usage?.total_tokens}`)

    // 5. 解析 DeepSeek 返回的 JSON 字符串
    let minutesData: {
      summary: string
      key_points: any[]
      todos: any[]
      decisions: any[]
    }
    try {
      minutesData = JSON.parse(content)
    } catch (e) {
      throw new Error(`DeepSeek 返回的 JSON 无法解析: ${content.slice(0, 200)}`)
    }

    // 6. 先删旧的纪要（支持重试）
    await supabase.from('minutes').delete().eq('task_id', task_id)

    // 7. 写入 minutes 表
    const { error: insertErr } = await supabase.from('minutes').insert({
      task_id,
      summary: minutesData.summary || '',
      key_points: minutesData.key_points || [],
      todos: minutesData.todos || [],
      decisions: minutesData.decisions || [],
    })
    if (insertErr) {
      throw new Error(`写入纪要失败: ${insertErr.message}`)
    }

    // 8. 更新 tasks 表：任务完成
    const summaryPreview = (minutesData.summary || '').slice(0, 100) +
      (minutesData.summary?.length > 100 ? '...' : '')
    await supabase
      .from('tasks')
      .update({
        status: 'completed',
        progress: 100,
        current_step: null,
        summary_preview: summaryPreview,
        updated_at: new Date().toISOString(),
      })
      .eq('id', task_id)

    console.log(`[summarize] 完成`)

    return jsonResponse({
      message: 'summarization complete',
      task_id,
      summary_length: minutesData.summary?.length ?? 0,
      key_points_count: minutesData.key_points?.length ?? 0,
      todos_count: minutesData.todos?.length ?? 0,
      decisions_count: minutesData.decisions?.length ?? 0,
    })

  } catch (err) {
    console.error('[summarize] 错误:', err)

    // 出错时把任务状态标记为 failed，方便前端展示
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

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}