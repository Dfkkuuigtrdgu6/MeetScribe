# Edge Function 接口文档

后端已完成两个 Edge Function：`transcribe`（语音转文字）和 `summarize`（生成会议纪要）。前端在 `TaskProcessView.vue` 里把当前的 mock 逻辑替换成调用这两个接口即可。

## 接口地址

已部署到云端，前端用 `supabase.functions.invoke()` 调用，无需手写 URL。

## 1. transcribe（语音转文字）

**作用**：接收 task_id，从 Storage 读音频，调阿里云 Paraformer 完成识别，把结果批量写入 `transcript_segments` 表，最后把 `tasks.status` 从 `queued` 更新为 `summarizing`。

**调用**：

```javascript
const { data, error } = await supabase.functions.invoke('transcribe', {
  body: { task_id: 'xxx-xxx-xxx' }
})
```

**参数**：

| 字段 | 类型 | 说明 |
|---|---|---|
| task_id | string | tasks 表的主键 uuid，必填 |

**成功返回**：

```json
{
  "message": "transcription complete",
  "task_id": "xxx",
  "sentence_count": 15
}
```

**失败返回**：

```json
{ "error": "错误描述" }
```

同时 `tasks.status = 'failed'`，`tasks.error_message` 会写入错误原因。

**耗时**：30 秒 - 5 分钟（取决于音频长度，1 分钟音频约 30-60 秒完成）。

## 2. summarize（生成会议纪要）

**作用**：读取 `transcript_segments`，拼接转录文本，调 DeepSeek 生成结构化纪要 JSON，写入 `minutes` 表，最后把 `tasks.status` 更新为 `completed`。

**前置条件**：必须在 `transcribe` 成功后（`tasks.status = 'summarizing'`）才能调用。

**调用**：

```javascript
const { data, error } = await supabase.functions.invoke('summarize', {
  body: { task_id: 'xxx-xxx-xxx' }
})
```

**参数**：同 transcribe，只需要 `task_id`。

**成功返回**：

```json
{
  "message": "summarization complete",
  "task_id": "xxx",
  "summary_length": 130,
  "key_points_count": 5,
  "todos_count": 4,
  "decisions_count": 3
}
```

**失败返回**：同 transcribe，`tasks.status = 'failed'`。

**耗时**：10-30 秒。

## 3. 推荐的前端调用流程

因为处理时间比较长（可能几分钟），**不要 await 整个流程阻塞用户**。推荐用"触发 + 轮询"模式：

```javascript
// 用户点"开始处理"后：

// 1. 触发 transcribe，不 await（fire and forget）
supabase.functions.invoke('transcribe', { body: { task_id } })
  .then(({ error }) => {
    if (error) console.error('transcribe 失败:', error)
    // 不用做别的，pollStatus 会感知到状态变化
  })

// 2. 保留现有的 pollStatus() 每 2 秒查 tasks 表
//    根据 tasks.status 判断当前进度：
//    - 'transcribing' → 显示"识别中"
//    - 'summarizing' → 转录完成，此时前端主动触发 summarize
//    - 'completed' → 全部完成，跳转到详情页
//    - 'failed' → 显示错误，读 tasks.error_message

// 3. 在 pollStatus 里检测到 status 变成 'summarizing' 时，触发 summarize
function pollStatus() {
  // ... 现有代码 ...
  if (data.status === 'summarizing' && !summarizeTriggered) {
    summarizeTriggered = true  // 用一个标志防止重复触发
    supabase.functions.invoke('summarize', { body: { task_id } })
      .then(({ error }) => {
        if (error) console.error('summarize 失败:', error)
      })
  }
  if (data.status === 'completed') {
    // 跳转到详情页
    router.push(`/tasks/${task_id}`)
  }
  if (data.status === 'failed') {
    // 显示错误提示，读 data.error_message
  }
}
```

## 4. 需要删掉的旧代码

`TaskProcessView.vue` 里以下三个函数是 mock 逻辑，可以全部删掉：

- `simulateProgress()`
- `generateMockSegments()`
- `generateMockMinutes()`

`startProcessing()` 函数里的 `simulateProgress()` 调用要替换成上面第 3 节的真实调用。

## 5. 已知限制

- **超时**：Paraformer 轮询上限约 10 分钟，超长音频（>1 小时）可能失败。当前场景够用。
- **触发链**：`transcribe` 完成后不会自动触发 `summarize`，需要前端手动串联（依赖 pollStatus 感知状态变化后主动触发）。以后可优化为数据库触发器自动串联。
- **JWT 校验**：当前部署时关闭了 JWT 验证（`--no-verify-jwt`），任何知道 URL 的人都能触发。MVP 阶段可接受，上线前需要打开并做用户身份校验。

## 6. 调试

- **看日志**：Supabase 控制台 → Edge Functions → 选中函数 → Logs 标签，能看到实时输出的 `console.log`
- **看数据库**：Table Editor → tasks / transcript_segments / minutes 表可以直接看写入结果
- **重试**：两个函数都是幂等的（会先删旧数据再插入），同一个 task_id 反复调没问题