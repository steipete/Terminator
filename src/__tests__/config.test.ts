import { describe, it, expect, beforeEach, vi } from 'vitest';
import { 
    getEnvVar, 
    getEnvVarInt, 
    getEnvVarBool, 
    getCanonicalOptions,
    PARAM_ALIASES,
    ALIAS_PRIORITY_MAP
} from '../config.js';

describe('config', () => {
    beforeEach(() => {
        vi.resetModules();
        delete process.env.TEST_VAR;
    });

    describe('getEnvVar', () => {
        it('should return environment variable value when set', () => {
            process.env.TEST_VAR = 'test-value';
            expect(getEnvVar('TEST_VAR', 'default')).toBe('test-value');
        });

        it('should return default value when environment variable is not set', () => {
            expect(getEnvVar('TEST_VAR', 'default')).toBe('default');
        });
    });

    describe('getEnvVarInt', () => {
        it('should parse integer from environment variable', () => {
            process.env.TEST_VAR = '42';
            expect(getEnvVarInt('TEST_VAR', 10)).toBe(42);
        });

        it('should return default for non-numeric values', () => {
            process.env.TEST_VAR = 'not-a-number';
            expect(getEnvVarInt('TEST_VAR', 10)).toBe(10);
        });

        it('should return default for empty string', () => {
            process.env.TEST_VAR = '';
            expect(getEnvVarInt('TEST_VAR', 10)).toBe(10);
        });
    });

    describe('getEnvVarBool', () => {
        it.each(['true', '1', 't', 'yes', 'on'])('should return true for "%s"', (value) => {
            process.env.TEST_VAR = value;
            expect(getEnvVarBool('TEST_VAR', false)).toBe(true);
        });

        it.each(['TRUE', 'YES', 'ON'])('should handle uppercase "%s"', (value) => {
            process.env.TEST_VAR = value;
            expect(getEnvVarBool('TEST_VAR', false)).toBe(true);
        });

        it.each(['false', '0', 'f', 'no', 'off', 'random'])('should return false for "%s"', (value) => {
            process.env.TEST_VAR = value;
            expect(getEnvVarBool('TEST_VAR', true)).toBe(false);
        });

        it('should return default when not set', () => {
            expect(getEnvVarBool('TEST_VAR', true)).toBe(true);
        });
    });

    describe('getCanonicalOptions', () => {
        it('should handle undefined input', () => {
            expect(getCanonicalOptions(undefined)).toEqual({});
        });

        it('should map aliases to canonical keys', () => {
            const input = {
                timeoutseconds: 30,
                dir: '/path/to/project',
                bg: true,
                cmd: 'npm test'
            };
            const result = getCanonicalOptions(input);
            expect(result).toEqual({
                timeout: 30,
                project_path: '/path/to/project',
                background: true,
                command: 'npm test'
            });
        });

        it('should handle case-insensitive matching', () => {
            const input = {
                TIMEOUT: 30,
                Project_Path: '/path',
                Background: true
            };
            const result = getCanonicalOptions(input);
            expect(result).toEqual({
                timeout: 30,
                project_path: '/path',
                background: true
            });
        });

        it('should respect alias priority', () => {
            const input = {
                timeout: 30,
                timeoutseconds: 60,
                project_path: '/path1',
                dir: '/path2'
            };
            const result = getCanonicalOptions(input);
            expect(result.timeout).toBe(30); // 'timeout' has higher priority
            expect(result.project_path).toBe('/path1'); // 'project_path' has higher priority
        });

        it('should ignore unknown parameters', () => {
            const input = {
                timeout: 30,
                unknown_param: 'value',
                another_unknown: 123
            };
            const result = getCanonicalOptions(input);
            expect(result).toEqual({
                timeout: 30
            });
            expect(result).not.toHaveProperty('unknown_param');
            expect(result).not.toHaveProperty('another_unknown');
        });
    });

    describe('PARAM_ALIASES', () => {
        it('should have all aliases in lowercase', () => {
            Object.keys(PARAM_ALIASES).forEach(key => {
                expect(key).toBe(key.toLowerCase());
            });
        });

        it('should map to valid canonical keys', () => {
            const validKeys = Object.keys(ALIAS_PRIORITY_MAP);
            Object.values(PARAM_ALIASES).forEach(value => {
                expect(validKeys).toContain(value);
            });
        });
    });

    describe('ALIAS_PRIORITY_MAP', () => {
        it('should contain all canonical option keys', () => {
            const expectedKeys = ['timeout', 'lines', 'project_path', 'background', 'focus', 'tag', 'command'];
            expectedKeys.forEach(key => {
                expect(ALIAS_PRIORITY_MAP).toHaveProperty(key);
            });
        });

        it('should have aliases that exist in PARAM_ALIASES', () => {
            Object.entries(ALIAS_PRIORITY_MAP).forEach(([key, aliases]) => {
                if (aliases) {
                    aliases.forEach(alias => {
                        expect(PARAM_ALIASES).toHaveProperty(alias.toLowerCase());
                    });
                }
            });
        });
    });
});