const requiredEnvironmentVariables = ["SONAR_TOKEN"] as const;

function requireEnvironmentVariable(
  variableName: (typeof requiredEnvironmentVariables)[number],
): string {
  const value = process.env[variableName];

  if (value === undefined || value.trim() === "") {
    throw new Error(`${variableName} must be set before running SonarQube analysis`);
  }

  return value;
}

requireEnvironmentVariable("SONAR_TOKEN");
