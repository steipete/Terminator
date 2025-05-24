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