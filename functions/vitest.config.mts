import {defineConfig} from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    // Rules tests talk to the Firestore emulator and share one project, so
    // they must not run side by side.
    fileParallelism: false,
    testTimeout: 20000,
  },
});
