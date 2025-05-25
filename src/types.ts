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
    action: 'exec' | 'read' | 'list' | 'info' | 'focus' | 'kill';
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
    signal?: AbortSignal;
    // progress?: (update: any) => void; // Define ProgressUpdate if needed
}

export interface RequestContextMeta {
    roots?: { uri?: { scheme?: string; path?: string } }[];
    // Add other relevant properties from requestContext if needed
} 