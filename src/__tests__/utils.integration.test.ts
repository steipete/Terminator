import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { expandTilde, resolveEffectiveProjectPath } from "../utils.js";

describe("utils integration tests", () => {
  let testDir: string;

  beforeEach(() => {
    // Create a temporary test directory
    testDir = path.join(os.tmpdir(), `terminator-test-${Date.now()}`);
    fs.mkdirSync(testDir, { recursive: true });
  });

  afterEach(() => {
    // Clean up test directory
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe("expandTilde", () => {
    it("should correctly expand tilde to actual home directory", () => {
      const homeDir = os.homedir();
      expect(expandTilde("~/Desktop")).toBe(path.join(homeDir, "Desktop"));
    });

    it("should handle various tilde patterns", () => {
      const homeDir = os.homedir();
      expect(expandTilde("~")).toBe("~"); // Just tilde without slash
      expect(expandTilde("~/")).toBe(homeDir);
      expect(expandTilde("~/Documents/Projects")).toBe(
        path.join(homeDir, "Documents", "Projects"),
      );
    });
  });

  describe("resolveEffectiveProjectPath", () => {
    it("should handle real /tmp directory (symlink on macOS)", () => {
      const result = resolveEffectiveProjectPath("/tmp");
      expect(result).toBe("/tmp");
    });

    it("should handle other macOS symlinks", () => {
      // These are common symlinks on macOS
      const symlinks = ["/var", "/etc"];
      for (const symlink of symlinks) {
        if (fs.existsSync(symlink)) {
          const result = resolveEffectiveProjectPath(symlink);
          expect(result).toBe(symlink);
        }
      }
    });

    it("should create non-existent directory", () => {
      const newDir = path.join(testDir, "new-project");
      expect(fs.existsSync(newDir)).toBe(false);

      const result = resolveEffectiveProjectPath(newDir);
      expect(result).toBe(newDir);
      expect(fs.existsSync(newDir)).toBe(true);
      expect(fs.statSync(newDir).isDirectory()).toBe(true);
    });

    it("should create deeply nested directories", () => {
      const deepDir = path.join(
        testDir,
        "level1",
        "level2",
        "level3",
        "level4",
      );
      expect(fs.existsSync(deepDir)).toBe(false);

      const result = resolveEffectiveProjectPath(deepDir);
      expect(result).toBe(deepDir);
      expect(fs.existsSync(deepDir)).toBe(true);
    });

    it("should reject files (not directories)", () => {
      const filePath = path.join(testDir, "test.txt");
      fs.writeFileSync(filePath, "test content");

      const result = resolveEffectiveProjectPath(filePath);
      expect(result).toBeNull();
    });

    it("should handle real tilde expansion", () => {
      const homeDir = os.homedir();
      const desktopPath = path.join(homeDir, "Desktop");

      // Only test if Desktop exists (it should on macOS)
      if (fs.existsSync(desktopPath)) {
        const result = resolveEffectiveProjectPath("~/Desktop");
        expect(result).toBe(desktopPath);
      }
    });

    it("should handle relative paths from current directory", () => {
      const originalCwd = process.cwd();
      try {
        process.chdir(testDir);

        // Create a subdirectory
        const subDir = "subdir";
        fs.mkdirSync(path.join(testDir, subDir));

        // Test relative path
        const result = resolveEffectiveProjectPath("./subdir");
        expect(result).toBe(path.join(testDir, subDir));
      } finally {
        process.chdir(originalCwd);
      }
    });

    it("should handle paths with spaces and special characters", () => {
      const specialDir = path.join(testDir, "My Projects & Tests!");

      const result = resolveEffectiveProjectPath(specialDir);
      expect(result).toBe(specialDir);
      expect(fs.existsSync(specialDir)).toBe(true);
    });

    it("should handle unicode in paths", () => {
      const unicodeDir = path.join(testDir, "日本語_проект_😀");

      const result = resolveEffectiveProjectPath(unicodeDir);
      expect(result).toBe(unicodeDir);
      expect(fs.existsSync(unicodeDir)).toBe(true);
    });

    it("should handle concurrent access gracefully", async () => {
      const concurrentDir = path.join(testDir, "concurrent");

      // Try to create the same directory from multiple "threads"
      const promises = Array(5)
        .fill(null)
        .map(() => Promise.resolve(resolveEffectiveProjectPath(concurrentDir)));

      const results = await Promise.all(promises);

      // All should succeed with the same path
      results.forEach((result) => {
        expect(result).toBe(concurrentDir);
      });

      expect(fs.existsSync(concurrentDir)).toBe(true);
    });

    it("should handle permission errors gracefully", () => {
      // This test would need to run as non-root and try to create in a protected directory
      // Skip if we can't test this properly
      if (process.getuid && process.getuid() !== 0) {
        const protectedPath = "/System/Library/test-dir";
        const result = resolveEffectiveProjectPath(protectedPath);
        expect(result).toBeNull();
      }
    });

    it("should resolve macOS common directories", () => {
      const commonDirs = [
        "/Applications",
        "/Users",
        "/Library",
        "/System",
        "/Volumes",
        os.homedir(),
      ];

      for (const dir of commonDirs) {
        if (fs.existsSync(dir)) {
          const result = resolveEffectiveProjectPath(dir);
          expect(result).toBe(dir);
        }
      }
    });
  });
});
