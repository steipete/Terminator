// Defines the core TypeScript interfaces for the Terminator MCP tool.
export interface TerminatorOptions {
    projectPath?: string;
    tag?: string;
    command?: string;
    background?: boolean;
    lines?: number;
    timeout?: number; // in seconds
    focus?: boolean;
}

export interface TerminatorExecuteParams {
    action: 'exec' | 'read' | 'list' | 'info' | 'focus' | 'kill';
    options?: { [key: string]: any }; // Raw options from AI, allowing for lenient parsing
}

export interface TerminatorResult {
    success: boolean;
    message: string; // User-facing message summarizing the result
} 