export const GREETING = "Hello, world!";

export function main(): void {
  process.stdout.write(`${GREETING}\n`);
}

if (require.main === module) {
  main();
}
