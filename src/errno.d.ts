declare module "errno" {
  interface ErrnoCode {
    errno: number;
    code: string;
    description: string;
  }

  interface Errno {
    code: {
      [key: string]: ErrnoCode;
    };
    errno: {
      [key: number]: ErrnoCode;
    };
  }

  const errno: Errno;
  export default errno;
}
