import { defineConfig } from 'vitest/config';

// Scoped to the Amplify backend (Lambda handlers, utility functions) --
// this project's Dart/Flutter tests run separately via `flutter test`.
// See docs/agents/test-agent/test-agent.md's TypeScript responsibilities.
export default defineConfig({
  test: {
    include: ['amplify/**/*.test.ts'],
    environment: 'node',
  },
});
