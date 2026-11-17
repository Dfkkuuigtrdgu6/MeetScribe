/*
# Create schema for voice transcription app

1. New Tables
- `tasks`: recording tasks with title, status, audio metadata, processing options
- `transcript_segments`: individual speech segments with speaker and timestamp
- `minutes`: AI-generated meeting minutes (summary, key points, todos, decisions)
- `templates`: reusable prompt templates for minutes generation
- `projects`: project categories for organizing tasks
- `tags`: tag labels
- `task_tags`: many-to-many between tasks and tags

2. Security
- Single-tenant app (no auth). RLS enabled on all tables.
- All policies use TO anon, authenticated with USING (true) since data is intentionally shared.
*/

-- Projects
CREATE TABLE IF NOT EXISTS projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  color text DEFAULT '#3b82f6',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_projects" ON projects;
CREATE POLICY "anon_select_projects" ON projects FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_projects" ON projects;
CREATE POLICY "anon_insert_projects" ON projects FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_projects" ON projects;
CREATE POLICY "anon_update_projects" ON projects FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_projects" ON projects;
CREATE POLICY "anon_delete_projects" ON projects FOR DELETE TO anon, authenticated USING (true);

-- Templates
CREATE TABLE IF NOT EXISTS templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  prompt text NOT NULL,
  icon text DEFAULT 'file-text',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_templates" ON templates;
CREATE POLICY "anon_select_templates" ON templates FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_templates" ON templates;
CREATE POLICY "anon_insert_templates" ON templates FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_templates" ON templates;
CREATE POLICY "anon_update_templates" ON templates FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_templates" ON templates;
CREATE POLICY "anon_delete_templates" ON templates FOR DELETE TO anon, authenticated USING (true);

-- Tags
CREATE TABLE IF NOT EXISTS tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_tags" ON tags;
CREATE POLICY "anon_select_tags" ON tags FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_tags" ON tags;
CREATE POLICY "anon_insert_tags" ON tags FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_tags" ON tags;
CREATE POLICY "anon_update_tags" ON tags FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_tags" ON tags;
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
DROP POLICY IF EXISTS "anon_select_tasks" ON tasks;
CREATE POLICY "anon_select_tasks" ON tasks FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_tasks" ON tasks;
CREATE POLICY "anon_insert_tasks" ON tasks FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_tasks" ON tasks;
CREATE POLICY "anon_update_tasks" ON tasks FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_tasks" ON tasks;
CREATE POLICY "anon_delete_tasks" ON tasks FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);

-- Task tags (many-to-many)
CREATE TABLE IF NOT EXISTS task_tags (
  task_id uuid REFERENCES tasks(id) ON DELETE CASCADE,
  tag_id uuid REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, tag_id)
);

ALTER TABLE task_tags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_task_tags" ON task_tags;
CREATE POLICY "anon_select_task_tags" ON task_tags FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_task_tags" ON task_tags;
CREATE POLICY "anon_insert_task_tags" ON task_tags FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_task_tags" ON task_tags;
CREATE POLICY "anon_update_task_tags" ON task_tags FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_task_tags" ON task_tags;
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
DROP POLICY IF EXISTS "anon_select_segments" ON transcript_segments;
CREATE POLICY "anon_select_segments" ON transcript_segments FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_segments" ON transcript_segments;
CREATE POLICY "anon_insert_segments" ON transcript_segments FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_segments" ON transcript_segments;
CREATE POLICY "anon_update_segments" ON transcript_segments FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_segments" ON transcript_segments;
CREATE POLICY "anon_delete_segments" ON transcript_segments FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_segments_task_id ON transcript_segments(task_id);
CREATE INDEX IF NOT EXISTS idx_segments_start_time ON transcript_segments(start_time);

-- Minutes (AI-generated)
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
DROP POLICY IF EXISTS "anon_select_minutes" ON minutes;
CREATE POLICY "anon_select_minutes" ON minutes FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_minutes" ON minutes;
CREATE POLICY "anon_insert_minutes" ON minutes FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_minutes" ON minutes;
CREATE POLICY "anon_update_minutes" ON minutes FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_minutes" ON minutes;
CREATE POLICY "anon_delete_minutes" ON minutes FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_minutes_task_id ON minutes(task_id);

-- Insert default templates
INSERT INTO templates (name, prompt, icon) VALUES
  ('会议纪要', '请根据以下转写内容生成会议纪要，包含：会议摘要、关键要点、待办事项（含负责人和截止日期）、决议结论。', 'file-text'),
  ('访谈摘要', '请根据以下转写内容生成访谈摘要，包含：访谈概述、关键信息、受访者观点、后续跟进事项。', 'message-square'),
  ('复盘总结', '请根据以下转写内容生成复盘总结，包含：目标回顾、执行情况、亮点与不足、改进计划。', 'refresh-cw')
ON CONFLICT DO NOTHING;

-- Insert default projects
INSERT INTO projects (name, color) VALUES
  ('产品会议', '#3b82f6'),
  ('客户访谈', '#10b981'),
  ('团队周会', '#f59e0b'),
  ('其他', '#6b7280')
ON CONFLICT DO NOTHING;
