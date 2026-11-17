-- ============================================================
-- 语音纪要应用 - 完整建表语句（用于你自己的 Supabase 项目）
-- 在 Supabase Dashboard > SQL Editor 中粘贴执行即可
-- ============================================================

-- Projects
CREATE TABLE IF NOT EXISTS projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  color text DEFAULT '#3b82f6',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_select_projects" ON projects FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "anon_insert_projects" ON projects FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "anon_update_projects" ON projects FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon_delete_projects" ON projects FOR DELETE TO anon, authenticated USING (true);

-- Templates (含 description 字段)
CREATE TABLE IF NOT EXISTS templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  prompt text NOT NULL,
  description text,
  icon text DEFAULT 'file-text',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_select_templates" ON templates FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "anon_insert_templates" ON templates FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "anon_update_templates" ON templates FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon_delete_templates" ON templates FOR DELETE TO anon, authenticated USING (true);

-- Tags
CREATE TABLE IF NOT EXISTS tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_select_tags" ON tags FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "anon_insert_tags" ON tags FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "anon_update_tags" ON tags FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon_delete_tags" ON tags FOR DELETE TO anon, authenticated USING (true);

-- Tasks
CREATE TABLE IF NOT EXISTS tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  status text NOT NULL DEFAULT 'queued',
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  audio_file_name text,
  audio_file_size bigint,
  audio_duration numeric DEFAULT 0,
  audio_url text,
  language text DEFAULT 'auto',
  speaker_separation boolean DEFAULT false,
  template_id uuid REFERENCES templates(id) ON DELETE SET NULL,
  notes text,
  summary_preview text,
  progress int DEFAULT 0,
  current_step text,
  error_message text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_select_tasks" ON tasks FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "anon_insert_tasks" ON tasks FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "anon_update_tasks" ON tasks FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon_delete_tasks" ON tasks FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);

-- Task tags
CREATE TABLE IF NOT EXISTS task_tags (
  task_id uuid REFERENCES tasks(id) ON DELETE CASCADE,
  tag_id uuid REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, tag_id)
);

ALTER TABLE task_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_select_task_tags" ON task_tags FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "anon_insert_task_tags" ON task_tags FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "anon_update_task_tags" ON task_tags FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon_delete_task_tags" ON task_tags FOR DELETE TO anon, authenticated USING (true);

-- Transcript segments
CREATE TABLE IF NOT EXISTS transcript_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  speaker text,
  speaker_index int DEFAULT 0,
  start_time numeric NOT NULL DEFAULT 0,
  end_time numeric DEFAULT 0,
  text text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE transcript_segments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_select_segments" ON transcript_segments FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "anon_insert_segments" ON transcript_segments FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "anon_update_segments" ON transcript_segments FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon_delete_segments" ON transcript_segments FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_segments_task_id ON transcript_segments(task_id);
CREATE INDEX IF NOT EXISTS idx_segments_start_time ON transcript_segments(start_time);

-- Minutes
CREATE TABLE IF NOT EXISTS minutes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  summary text,
  key_points jsonb DEFAULT '[]'::jsonb,
  todos jsonb DEFAULT '[]'::jsonb,
  decisions jsonb DEFAULT '[]'::jsonb,
  notes text,
  version int DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE minutes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_select_minutes" ON minutes FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "anon_insert_minutes" ON minutes FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "anon_update_minutes" ON minutes FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "anon_delete_minutes" ON minutes FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_minutes_task_id ON minutes(task_id);

-- ============================================================
-- 默认模板数据（3个模板，各有不同的 prompt 和 description）
-- ============================================================
INSERT INTO templates (name, prompt, description, icon) VALUES
  (
    '会议纪要',
    '你是一个专业的会议纪要助手。请根据以下转写内容生成结构化会议纪要，必须包含以下部分：

【会议摘要】用2-3句话概括会议的核心议题和主要结论。

【关键要点】列出会议讨论的核心要点，每条一句话，编号排列。

【待办事项】列出需要跟进的任务，每条包含：任务描述、负责人（如转写中未提及则标注"待定"）、截止日期（如未提及则标注"待定"）。

【决议结论】列出会议中达成的明确决定和结论。',
    '适合正式会议场景，自动提取摘要、关键要点、待办事项和决议',
    'file-text'
  ),
  (
    '访谈摘要',
    '你是一个专业的访谈分析助手。请根据以下转写内容生成结构化访谈摘要，必须包含以下部分：

【访谈概述】用2-3句话概括访谈的背景、目的和主要话题。

【关键信息】列出访谈中获取的重要信息点，每条一句话，编号排列。

【受访者观点】列出受访者的核心观点和态度，标注是哪位受访者提出的。

【后续跟进事项】列出访谈后需要跟进的行动项，每条包含：事项描述、负责人、优先级（高/中/低）。',
    '适合客户访谈、用户调研场景，提取访谈概述、关键信息和受访者观点',
    'message-square'
  ),
  (
    '复盘总结',
    '你是一个专业的复盘分析助手。请根据以下转写内容生成结构化复盘总结，必须包含以下部分：

【目标回顾】列出本次复盘涉及的目标和预期成果。

【执行情况】评估目标达成情况，标注"已达成"或"未达成"，并简要说明原因。

【亮点与不足】分别列出做得好的方面和需要改进的方面，各至少2条。

【改进计划】列出具体的改进措施和行动计划，每条包含：改进方向、具体措施、责任人。',
    '适合项目复盘、迭代回顾场景，梳理目标达成情况和改进计划',
    'refresh-cw'
  )
ON CONFLICT DO NOTHING;

-- ============================================================
-- 默认项目分类
-- ============================================================
INSERT INTO projects (name, color) VALUES
  ('产品会议', '#3b82f6'),
  ('客户访谈', '#10b981'),
  ('团队周会', '#f59e0b'),
  ('其他', '#6b7280')
ON CONFLICT DO NOTHING;
