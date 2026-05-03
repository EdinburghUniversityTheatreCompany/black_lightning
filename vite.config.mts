import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import tailwindcss from '@tailwindcss/vite'
import { visualizer } from 'rollup-plugin-visualizer'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    tailwindcss(),
    visualizer(), // Open stats.html to view results
  ],
  css: {
    preprocessorOptions: {
      scss: {
        quietDeps: true,
      },
    },
  },
  optimizeDeps: {
    include: ['dropzone'],
  },
})
