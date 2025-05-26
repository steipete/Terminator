// Defines the core TypeScript interfaces for the Terminator MCP tool.
export interface TerminatorOptions {
    project_path?: string;
    tag?: string;
    command?: string;
    background?: boolean | string;
    lines?: number;
    timeout?: number; // in seconds
    focus?: boolean | string;
}

export interface TerminatorExecuteParams {
    action?: 'execute' | 'read' | 'list' | 'info' | 'focus' | 'kill';
    project_path: string;
    tag?: string;
    command?: string;
    background?: boolean | string;
    lines?: number;
    timeout?: number; // in seconds
    focus?: boolean | string;
}

export interface TerminatorResult {
    success: boolean;
    message: string; // User-facing message summarizing the result
}

export interface SdkCallContext {
    abortSignal?: AbortSignal;
    // progress?: (update: any) => void; // Define ProgressUpdate if needed
    logger?: {
        debug: (message: string, ...args: any[]) => void;
        info: (message: string, ...args: any[]) => void;
        warn: (message: string, ...args: any[]) => void;
        error: (message: string, ...args: any[]) => void;
    };
}

export interface RequestContextMeta {
    roots?: { uri?: { scheme?: string; path?: string } }[];
    // Add other relevant properties from requestContext if needed
}

export interface SwiftCLIResult {
    stdout: string;
    stderr: string;
    exitCode: number | null;
    cancelled: boolean;
    internalTimeoutHit: boolean;
    // Add other fields if your Swift CLI might return them
} 