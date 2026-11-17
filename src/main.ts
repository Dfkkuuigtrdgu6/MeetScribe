import { createApp } from 'vue'
import './style.css'
import App from './App.vue'
import router from './router'
import { initAuth } from './lib/auth'

async function bootstrap() {
  await initAuth()
  createApp(App).use(router).mount('#app')
}

bootstrap()
