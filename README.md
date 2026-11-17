# 🎙️ MeetScribe - 智能录音纪要工具

基于语音识别的会议录音转纪要工具。提取会议录音内容，自动转写为文字并进行智能总结，提高会议记录效率。

## ✨ 核心功能
- 🎧 **音频上传/录制**：支持上传本地会议录音或直接在线录制。
- 📝 **语音转文字**：高准确率转写会议内容（后端接入 xxx 语音模型）。
- 📑 **智能摘要**：一键生成会议核心要点和待办事项（后端接入 xxx 大模型）。
- 📂 **历史记录**：保存并管理过往的会议纪要。

## 🛠️ 技术栈
- **前端框架**：Vue 3 + TypeScript + Vite
- **路由管理**：Vue Router
- **图标库**：lucide-vue-next
- **后端 / 数据库**：Supabase（认证鉴权、数据存储、Storage 音频桶、Edge Functions 云函数）

## 🚀 快速开始

### 环境要求
- Node.js >= 16.0
- npm / pnpm / yarn

### 安装依赖
```bash
npm install
# 或者 pnpm install
```

### 启动开发服务器
```bash
npm run dev
```

### 打包构建
```bash
npm run build
```