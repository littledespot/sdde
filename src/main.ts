export const GREETING = "Hello, world!";

export type OutputWriter = (value: string) => void;

export function main(
  write: OutputWriter = (value) => {
    process.stdout.write(value);
  },
): void {
  write(`${GREETING}\n`);
}

if (require.main === module) {
  main();
}
