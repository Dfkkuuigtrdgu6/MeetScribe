-- ============================================================
-- 用户多租户改造：邮箱登录 + 数据按用户隔离 + Storage 私有桶
-- 该迁移将应用：
--   1. 为业务表添加 user_id 并绑定 auth.users
--   2. 将 RLS 从「完全开放」改为「仅 authenticated 且仅本人数据」
--   3. 为新注册用户自动创建默认项目分类与纪要模板
--   4. 创建私有 storage 桶 audio，并按 audio/{user_id}/ 路径做 RLS 隔离
-- ============================================================

-- ------------------------------------------------------------
-- 1. 添加 user_id 列（先允许为空，用于清理历史数据后收紧）
-- ------------------------------------------------------------
alter table projects  add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table templates add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table tags      add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table tasks     add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table tasks     add column if not exists audio_storage_path text;

-- ------------------------------------------------------------
-- 2. 清理旧的历史 / 全局共享数据（开发期原型数据，直接移除）
--    tasks 删除会级联清空 transcript_segments / minutes / task_tags
-- ------------------------------------------------------------
delete from tasks where user_id is null;
delete from projects where user_id is null;
delete from templates where user_id is null;
delete from tags where user_id is null;

-- 收紧为 NOT NULL
alter table projects  alter column user_id set not null;
alter table templates alter column user_id set not null;
alter table tags      alter column user_id set not null;
alter table tasks     alter column user_id set not null;

-- tags 的唯一约束从「全局唯一」改为「同一用户内唯一」
alter table tags drop constraint if exists tags_name_key;
alter table tags add constraint tags_user_name_key unique (user_id, name);

-- ------------------------------------------------------------
-- 3. 重建 RLS：仅 authenticated，且只能访问 / 修改本人数据
-- ------------------------------------------------------------

-- ---------- projects ----------
drop policy if exists "anon_select_projects" on projects;
drop policy if exists "anon_insert_projects" on projects;
drop policy if exists "anon_update_projects" on projects;
drop policy if exists "anon_delete_projects" on projects;
create policy "select_own_projects" on projects for select to authenticated using (user_id = auth.uid());
create policy "insert_own_projects" on projects for insert to authenticated with check (user_id = auth.uid());
create policy "update_own_projects" on projects for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete_own_projects" on projects for delete to authenticated using (user_id = auth.uid());

-- ---------- templates ----------
drop policy if exists "anon_select_templates" on templates;
drop policy if exists "anon_insert_templates" on templates;
drop policy if exists "anon_update_templates" on templates;
drop policy if exists "anon_delete_templates" on templates;
create policy "select_own_templates" on templates for select to authenticated using (user_id = auth.uid());
create policy "insert_own_templates" on templates for insert to authenticated with check (user_id = auth.uid());
create policy "update_own_templates" on templates for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete_own_templates" on templates for delete to authenticated using (user_id = auth.uid());

-- ---------- tags ----------
drop policy if exists "anon_select_tags" on tags;
drop policy if exists "anon_insert_tags" on tags;
drop policy if exists "anon_update_tags" on tags;
drop policy if exists "anon_delete_tags" on tags;
create policy "select_own_tags" on tags for select to authenticated using (user_id = auth.uid());
create policy "insert_own_tags" on tags for insert to authenticated with check (user_id = auth.uid());
create policy "update_own_tags" on tags for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete_own_tags" on tags for delete to authenticated using (user_id = auth.uid());

-- ---------- tasks ----------
drop policy if exists "anon_select_tasks" on tasks;
drop policy if exists "anon_insert_tasks" on tasks;
drop policy if exists "anon_update_tasks" on tasks;
drop policy if exists "anon_delete_tasks" on tasks;
create policy "select_own_tasks" on tasks for select to authenticated using (user_id = auth.uid());
create policy "insert_own_tasks" on tasks for insert to authenticated with check (user_id = auth.uid());
create policy "update_own_tasks" on tasks for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete_own_tasks" on tasks for delete to authenticated using (user_id = auth.uid());

-- ---------- task_tags（通过 tasks 与 tags 双重归属校验）----------
drop policy if exists "anon_select_task_tags" on task_tags;
drop policy if exists "anon_insert_task_tags" on task_tags;
drop policy if exists "anon_update_task_tags" on task_tags;
drop policy if exists "anon_delete_task_tags" on task_tags;
create policy "select_own_task_tags" on task_tags for select to authenticated
  using (
    exists (select 1 from tasks where tasks.id = task_tags.task_id and tasks.user_id = auth.uid())
    and exists (select 1 from tags where tags.id = task_tags.tag_id and tags.user_id = auth.uid())
  );
create policy "insert_own_task_tags" on task_tags for insert to authenticated
  with check (
    exists (select 1 from tasks where tasks.id = task_tags.task_id and tasks.user_id = auth.uid())
    and exists (select 1 from tags where tags.id = task_tags.tag_id and tags.user_id = auth.uid())
  );
create policy "update_own_task_tags" on task_tags for update to authenticated
  using (
    exists (select 1 from tasks where tasks.id = task_tags.task_id and tasks.user_id = auth.uid())
    and exists (select 1 from tags where tags.id = task_tags.tag_id and tags.user_id = auth.uid())
  )
  with check (
    exists (select 1 from tasks where tasks.id = task_tags.task_id and tasks.user_id = auth.uid())
    and exists (select 1 from tags where tags.id = task_tags.tag_id and tags.user_id = auth.uid())
  );
create policy "delete_own_task_tags" on task_tags for delete to authenticated
  using (
    exists (select 1 from tasks where tasks.id = task_tags.task_id and tasks.user_id = auth.uid())
    and exists (select 1 from tags where tags.id = task_tags.tag_id and tags.user_id = auth.uid())
  );

-- ---------- transcript_segments（通过 task 归属）----------
drop policy if exists "anon_select_segments" on transcript_segments;
drop policy if exists "anon_insert_segments" on transcript_segments;
drop policy if exists "anon_update_segments" on transcript_segments;
drop policy if exists "anon_delete_segments" on transcript_segments;
create policy "select_own_segments" on transcript_segments for select to authenticated
  using (exists (select 1 from tasks where tasks.id = transcript_segments.task_id and tasks.user_id = auth.uid()));
create policy "insert_own_segments" on transcript_segments for insert to authenticated
  with check (exists (select 1 from tasks where tasks.id = transcript_segments.task_id and tasks.user_id = auth.uid()));
create policy "update_own_segments" on transcript_segments for update to authenticated
  using (exists (select 1 from tasks where tasks.id = transcript_segments.task_id and tasks.user_id = auth.uid()))
  with check (exists (select 1 from tasks where tasks.id = transcript_segments.task_id and tasks.user_id = auth.uid()));
create policy "delete_own_segments" on transcript_segments for delete to authenticated
  using (exists (select 1 from tasks where tasks.id = transcript_segments.task_id and tasks.user_id = auth.uid()));

-- ---------- minutes（通过 task 归属）----------
drop policy if exists "anon_select_minutes" on minutes;
drop policy if exists "anon_insert_minutes" on minutes;
drop policy if exists "anon_update_minutes" on minutes;
drop policy if exists "anon_delete_minutes" on minutes;
create policy "select_own_minutes" on minutes for select to authenticated
  using (exists (select 1 from tasks where tasks.id = minutes.task_id and tasks.user_id = auth.uid()));
create policy "insert_own_minutes" on minutes for insert to authenticated
  with check (exists (select 1 from tasks where tasks.id = minutes.task_id and tasks.user_id = auth.uid()));
create policy "update_own_minutes" on minutes for update to authenticated
  using (exists (select 1 from tasks where tasks.id = minutes.task_id and tasks.user_id = auth.uid()))
  with check (exists (select 1 from tasks where tasks.id = minutes.task_id and tasks.user_id = auth.uid()));
create policy "delete_own_minutes" on minutes for delete to authenticated
  using (exists (select 1 from tasks where tasks.id = minutes.task_id and tasks.user_id = auth.uid()));

-- ------------------------------------------------------------
-- 4. 新用户注册时自动创建默认项目分类与纪要模板
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.projects (user_id, name, color) values
    (new.id, '产品会议', '#3b82f6'),
    (new.id, '客户访谈', '#10b981'),
    (new.id, '团队周会', '#f59e0b'),
    (new.id, '其他', '#6b7280');

  insert into public.templates (user_id, name, prompt, description, icon) values
    (
      new.id,
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
      new.id,
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
      new.id,
      '复盘总结',
      '你是一个专业的复盘分析助手。请根据以下转写内容生成结构化复盘总结，必须包含以下部分：
【目标回顾】列出本次复盘涉及的目标和预期成果。
【执行情况】评估目标达成情况，标注"已达成"或"未达成"，并简要说明原因。
【亮点与不足】分别列出做得好的方面和需要改进的方面，各至少2条。
【改进计划】列出具体的改进措施和行动计划，每条包含：改进方向、具体措施、责任人。',
      '适合项目复盘、迭代回顾场景，梳理目标达成情况和改进计划',
      'refresh-cw'
    );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- 5. 私有 Storage 桶 audio + 按用户文件夹隔离
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('audio', 'audio', false, 524288000, array['audio/mpeg','audio/mp4','audio/x-m4a','audio/wav','audio/x-wav','audio/webm','audio/ogg','audio/flac','audio/aac','audio/x-ms-wma'])
on conflict (id) do update set public = false;

-- 允许 authenticated 读桶元数据
drop policy if exists "audio_bucket_select" on storage.objects;
-- 基于路径第一段 = 用户 id 的对象级策略
create policy "audio_select_own_folder" on storage.objects for select to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "audio_insert_own_folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "audio_update_own_folder" on storage.objects for update to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "audio_delete_own_folder" on storage.objects for delete to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text);